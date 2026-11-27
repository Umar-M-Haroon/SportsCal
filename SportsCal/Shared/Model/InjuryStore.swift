//
//  InjuryStore.swift
//  SportsCal
//
//  League-wide injury report (NBA, NFL, NHL, MLB) from the server's `/injuries`,
//  cached in the App Group so Siri/Shortcuts answers work without a fresh fetch.
//

import Foundation
import AppIntents
import SportsCalModel

@MainActor
@Observable
final class InjuryStore {
    static let shared = InjuryStore()

    private(set) var feed: InjuryFeed?
    private(set) var isLoading = false
    @ObservationIgnored private var lastFetch: Date?

    private static let cacheURL = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?
        .appendingPathComponent("injuries.json")

    private init() {
        if let url = Self.cacheURL, let data = try? Data(contentsOf: url) {
            feed = try? JSONDecoder.injuryFeed.decode(InjuryFeed.self, from: data)
        }
    }

    var injuries: [PlayerInjury] { feed?.injuries ?? [] }

    #if DEBUG
    /// Previews: show a fixed feed without the network.
    func usePreviewFeed(_ feed: InjuryFeed) {
        self.feed = feed
        lastFetch = .distantFuture
    }
    #endif

    /// Fetches when the last fetch is older than `maxAge` (the server refreshes from
    /// ESPN every couple of hours, so there's no point asking more often).
    func refreshIfStale(maxAge: TimeInterval = 15 * 60) async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < maxAge, feed != nil { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let fresh = await NetworkHandler.getInjuries() else { return }
        lastFetch = Date()
        feed = fresh
        if let url = Self.cacheURL, let data = try? JSONEncoder.injuryFeed.encode(fresh) {
            try? data.write(to: url, options: .atomic)
        }
        // Siri matches spoken player names against the suggested entities.
        SportsCalShortcuts.updateAppShortcutParameters()
    }

    /// Players whose name matches the query, best match first: the full name, then a
    /// surname, then any word starting with what was typed. Accents and case are
    /// ignored, so "doncic" finds Dončić.
    func search(_ query: String) -> [PlayerInjury] {
        InjurySearch.rank(injuries, query: query)
    }

    /// The injuries for one team, matched by name or any alias the team list knows.
    func injuries(forTeam name: String?) -> [PlayerInjury] {
        guard let name, !name.isEmpty else { return [] }
        let id = TeamsManager.shared.teamID(forName: name)
        let key = InjurySearch.fold(name)
        return injuries.filter { injury in
            if let id, TeamsManager.shared.teamID(forName: injury.teamName) == id { return true }
            return InjurySearch.fold(injury.teamName) == key
        }
        .sorted(by: InjuryText.severityOrder)
    }
}

private extension JSONDecoder {
    static let injuryFeed: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }()
}

private extension JSONEncoder {
    static let injuryFeed = JSONEncoder()
}

/// Name matching for the injury search, the Siri query and the day page's search.
enum InjurySearch {
    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    nonisolated static func rank(_ injuries: [PlayerInjury], query: String) -> [PlayerInjury] {
        let q = fold(query)
        guard q.count >= 2 else { return [] }
        let queryWords = q.split(separator: " ").map(String.init)
        func score(_ injury: PlayerInjury) -> Int? {
            let name = fold(injury.playerName)
            if name == q { return 0 }
            let words = name.split(separator: " ").map(String.init)
            let surname = words.dropFirst().joined(separator: " ")
            if words.count > 1, surname == q || words.last == q { return 1 }
            // Every typed word starts some word of the name: "jock lan", "lebron".
            if queryWords.allSatisfy({ typed in words.contains { $0.hasPrefix(typed) } }) { return 2 }
            if name.contains(q) { return 3 }
            return nil
        }
        var scored: [(injury: PlayerInjury, score: Int)] = []
        for injury in injuries {
            if let value = score(injury) { scored.append((injury, value)) }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.injury.playerName < rhs.injury.playerName
        }
        return scored.map { $0.injury }
    }
}

/// How an injury reads: the headline ("Right hip inflammation"), the status, and the
/// answer to "how much longer" from ESPN's estimated return day.
enum InjuryText {
    /// "Right hip inflammation", "Knee", "Upper body". Falls back to the status.
    nonisolated static func headline(_ injury: PlayerInjury) -> String {
        if injury.status == "Suspension" { return "Suspended" }
        var parts: [String] = []
        if let side = injury.side, side == "Left" || side == "Right" { parts.append(side) }
        if let part = injury.bodyPart { parts.append(part) }
        if let what = injury.injury, what != injury.bodyPart { parts.append(what) }
        guard !parts.isEmpty else { return injury.status }
        let text = parts.joined(separator: " ").lowercased()
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "Out", "Day-to-day", "Injured reserve" — sentence case for display.
    nonisolated static func status(_ injury: PlayerInjury) -> String {
        switch injury.status {
        case "Day-To-Day": "Day-to-day"
        case "Injured Reserve": "Injured reserve"
        case "Suspension": "Suspended"
        default: injury.status
        }
    }

    /// The status as it reads mid-sentence: "is out", "is on injured reserve".
    nonisolated static func statusPhrase(_ injury: PlayerInjury) -> String {
        switch injury.status {
        case "Injured Reserve": "on injured reserve"
        case "Suspension": "suspended"
        default: status(injury).lowercased()
        }
    }

    enum Severity: Int { case suspended, out, doubtful, questionable }

    nonisolated static func severity(_ injury: PlayerInjury) -> Severity {
        switch injury.status {
        case "Out", "Injured Reserve": .out
        case "Doubtful": .doubtful
        case "Suspension": .suspended
        default: .questionable
        }
    }

    /// Longest-out first, then by name.
    nonisolated static func severityOrder(_ a: PlayerInjury, _ b: PlayerInjury) -> Bool {
        let da = returnDay(a), db = returnDay(b)
        if da != db { return (da ?? .distantFuture) > (db ?? .distantFuture) }
        return a.playerName < b.playerName
    }

    nonisolated static func isOutForSeason(_ injury: PlayerInjury) -> Bool {
        let text = [injury.summary, injury.details].compactMap { $0?.lowercased() }.joined(separator: " ")
        return ["season-ending", "rest of the season", "remainder of the season",
                "out for the season", "miss the season", "miss the entire season"].contains { text.contains($0) }
    }

    nonisolated static func returnDay(_ injury: PlayerInjury, calendar: Calendar = .current) -> Date? {
        guard let raw = injury.returnDate else { return nil }
        let parts = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Whole days from today to the estimated return (negative once it's passed).
    nonisolated static func daysUntilReturn(_ injury: PlayerInjury, now: Date = Date(),
                                            calendar: Calendar = .current) -> Int? {
        guard let day = returnDay(injury, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day
    }

    /// "in 3 days", "in about 3 weeks", "in about 4 months".
    nonisolated static func span(days: Int) -> String {
        switch days {
        case ...0: "now"
        case 1: "tomorrow"
        case 2..<14: "in \(days) days"
        case 14..<60: "in about \(Int((Double(days) / 7).rounded())) weeks"
        default: "in about \(Int((Double(days) / 30.4).rounded())) months"
        }
    }

    /// The short "how long" line for lists: "Back Sun, Nov 29 · in 3 days".
    nonisolated static func returnLine(_ injury: PlayerInjury, now: Date = Date(),
                                       calendar: Calendar = .current) -> String {
        if isOutForSeason(injury) { return "Out for the season" }
        guard let day = returnDay(injury, calendar: calendar),
              let days = daysUntilReturn(injury, now: now, calendar: calendar) else {
            return "No return date yet"
        }
        if days <= 0 { return "Could return any day" }
        let date = format(day, wide: false, calendar: calendar)
        if days == 1 { return "Back tomorrow · \(date)" }
        return "Back \(date) · \(span(days: days))"
    }

    /// The spoken / written answer to "what's X out with and when is he back?".
    nonisolated static func answer(_ injury: PlayerInjury, now: Date = Date(),
                                   calendar: Calendar = .current) -> String {
        let what = headline(injury)
        var sentence = "\(injury.playerName) (\(injury.teamName)) is \(statusPhrase(injury))"
        if what != injury.status, injury.status != "Suspension" {
            sentence += " with \(what.lowercased())"
        }
        sentence += "."
        if isOutForSeason(injury) {
            sentence += " Reports say it's season-ending."
        } else if let day = returnDay(injury, calendar: calendar),
                  let days = daysUntilReturn(injury, now: now, calendar: calendar) {
            let date = format(day, wide: true, calendar: calendar)
            if days <= 0 {
                sentence += " The estimated return date has passed, so a return could come any game now."
            } else {
                sentence += " Estimated return: \(date), \(span(days: days))."
            }
        } else {
            sentence += " There's no estimated return date yet."
        }
        return sentence
    }

    /// "Sun, Nov 29" / "Sunday, November 29", in the calendar's own time zone.
    nonisolated static func format(_ day: Date, wide: Bool, calendar: Calendar) -> String {
        var style = wide
            ? Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
            : Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return day.formatted(style)
    }

    /// League slug → the schedule's sport, for colours and icons.
    nonisolated static func sport(_ injury: PlayerInjury) -> SportType {
        switch injury.league {
        case "nfl": .nfl
        case "nhl": .hockey
        case "mlb": .mlb
        default: .basketball
        }
    }

    nonisolated static func leagueName(_ slug: String) -> String { slug.uppercased() }
}
