//
//  MotorsportWeekends.swift
//
//  Race weekends from TheSportsDB, for series whose results come from elsewhere
//  (IndyCar, IMSA, WEC). TheSportsDB lists each session as its own event — "6 Hours of
//  Spa Practice 1", "… Qualifying - Hypercar", "… Hyperpole - LMGT3" — next to the race
//  itself; this groups them back into one weekend per race.
//

import Foundation
import Vapor
import SportsCalModel

/// The fields of a TheSportsDB v2 schedule row a race weekend needs. Decoded directly
/// rather than through `Game`, which drops the venue.
struct TSDBRacingEvent: Decodable, Equatable {
    let idEvent: String
    let strEvent: String
    let strTimestamp: String?
    let dateEvent: String?
    let strVenue: String?
    let strCountry: String?
    let intRound: String?

    /// Kickoff, or nil. TheSportsDB writes midnight for "time not announced" on some
    /// series (IMSA), which is kept: the day is still right.
    var start: Date? {
        strTimestamp.flatMap { MotorsportWeekends.utcDate($0) }
            ?? dateEvent.flatMap { MotorsportWeekends.utcDate($0 + "T00:00:00") }
    }
}

private struct TSDBRacingScheduleResponse: Decodable {
    let schedule: [TSDBRacingEvent]?
}

struct MotorsportWeekend {
    let race: TSDBRacingEvent
    var sessions: [Session]

    struct Session {
        let event: TSDBRacingEvent
        /// `EventSession.sessionType`: "practice" or "qual".
        let type: String
        let name: String
    }

    var venue: String? { race.strVenue.flatMap { $0.isEmpty ? nil : $0 } ?? sessions.lazy.compactMap { $0.event.strVenue }.first { !$0.isEmpty } }
}

enum MotorsportWeekends {
    /// One season of a league's events from TheSportsDB (v2, keyed).
    static func events(league: Leagues, season: Int, client: some Client) async throws -> [TSDBRacingEvent] {
        let url = "https://www.thesportsdb.com/api/v2/json/schedule/league/\(league.rawValue)/\(season)"
        let response = try await client.get(URI(string: url)) { req in
            if let key = Environment.get("SportsDB_API_KEY") { req.headers.add(name: "X-API-KEY", value: key) }
        }
        guard response.status == .ok else { throw Abort(.badGateway, reason: "TheSportsDB \(league) \(season): \(response.status.code)") }
        return (try? response.content.decode(TSDBRacingScheduleResponse.self))?.schedule ?? []
    }

    /// Groups sessions under their race. A session belongs to the race with the same
    /// base name, else to the first race at the same venue within six days after it.
    /// Test days and prologues aren't race weekends and are dropped.
    static func group(_ events: [TSDBRacingEvent]) -> [MotorsportWeekend] {
        let usable = events.filter { !isTestEvent($0.strEvent) }
        var races: [MotorsportWeekend] = []
        var sessions: [(event: TSDBRacingEvent, kind: SessionKind)] = []
        for event in usable {
            if let kind = sessionKind(event.strEvent) {
                sessions.append((event, kind))
            } else {
                races.append(MotorsportWeekend(race: event, sessions: []))
            }
        }
        races.sort { ($0.race.start ?? .distantFuture) < ($1.race.start ?? .distantFuture) }
        for (event, kind) in sessions {
            let byName = races.firstIndex { normalized($0.race.strEvent) == normalized(kind.base) }
            let byVenue = races.firstIndex { weekend in
                guard let raceStart = weekend.race.start, let start = event.start else { return false }
                let gap = raceStart.timeIntervalSince(start)
                return gap >= -6 * 3600 && gap <= 6 * 24 * 3600
                    && normalized(weekend.race.strVenue ?? "") == normalized(event.strVenue ?? "")
            }
            guard let index = byName ?? byVenue else { continue }
            races[index].sessions.append(.init(event: event, type: kind.type, name: kind.name))
        }
        for index in races.indices {
            races[index].sessions.sort { ($0.event.start ?? .distantFuture) < ($1.event.start ?? .distantFuture) }
        }
        return races
    }

    struct SessionKind: Equatable {
        let base: String
        let type: String
        let name: String
    }

    /// Splits "6 Hours of Spa Qualifying - Hypercar" into the race name and the session;
    /// nil for the race itself.
    static func sessionKind(_ name: String) -> SessionKind? {
        let patterns: [(String, String)] = [
            (#"\s+(Free Practice \d+)$"#, "practice"),
            (#"\s+(High Line and Final Practice)$"#, "practice"),
            (#"\s+(Final Practice)$"#, "practice"),
            (#"\s+(Practice(?: \d+)?)$"#, "practice"),
            (#"\s+(Warm[ -]?Up)$"#, "practice"),
            // The Indianapolis 500's month of May.
            (#"\s+(Fast Friday|Carb Day|Rookie Orientation)$"#, "practice"),
            // "Qualifying - Hypercar", "Hyperpole 1 - LMP2 & LMGT3", "Hyperpole Qualifying – Hypercar".
            (#"\s+(Hyperpole(?: \d+)?(?: Qualifying)?(?: [-–] .+)?)$"#, "qual"),
            (#"\s+(Qualifying(?: \d+)?(?: [-–] .+)?)$"#, "qual"),
        ]
        for (pattern, type) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let sessionRange = Range(match.range(at: 1), in: name),
                  let fullRange = Range(match.range, in: name) else { continue }
            let session = String(name[sessionRange]).replacingOccurrences(of: " - ", with: " ").replacingOccurrences(of: " – ", with: " ")
            return SessionKind(base: String(name[..<fullRange.lowerBound]), type: type, name: session)
        }
        return nil
    }

    static func isTestEvent(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("prologue") || lowered.hasPrefix("roar before") || lowered.contains(" test")
    }

    static func normalized(_ string: String) -> String {
        string.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func utcDate(_ string: String) -> Date? {
        utcFormatter.date(from: string) ?? DateParsers.parse(string)
    }

    static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Status of a session with no results feed: done once it's well past, else upcoming.
    static func scheduledStatus(start: Date?, now: Date, length: TimeInterval = 2 * 3600) -> String {
        guard let start else { return "pre" }
        return now.timeIntervalSince(start) > length ? "post" : "pre"
    }
}
