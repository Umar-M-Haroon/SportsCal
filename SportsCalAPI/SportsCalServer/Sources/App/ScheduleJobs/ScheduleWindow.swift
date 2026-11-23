//
//  ScheduleWindow.swift
//
//  The "hot" part of the schedule (recent and upcoming games) and on-demand history.
//
//  The full schedule is ~50k games / 33MB of JSON, ~29MB of it games that finished
//  more than two weeks ago, and every app decoded and filtered all of it at launch.
//  New apps fetch slices with `?window=hot` (the last two weeks and everything ahead,
//  ~6MB) and ask `/schedules/history` for older games only when a screen needs them
//  (a team's season, a past month, a league's results, one game). The full
//  `/schedules` and plain slices are unchanged for shipped apps.
//

import Foundation
import Vapor
import SportsCalModel

enum ScheduleWindow {
    /// Days before today the hot window keeps: the recent results every screen shows.
    /// Everything ahead is kept (a team's remaining season, an offseason team's next
    /// game): it's ~2.7MB, and lazily loading it would touch every forward-looking view.
    static let hotPastDays = 14

    /// UTC day number, so the hot window (and its cache variant) moves once a day.
    static func dayIndex(_ date: Date) -> Int {
        Int(floor(date.timeIntervalSince1970 / 86_400))
    }

    /// Start of the hot window: midnight UTC `hotPastDays` ago.
    static func hotStart(now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: now).addingTimeInterval(-Double(hotPastDays) * 86_400)
    }

    /// When a game starts and its last day (a race's final session, a golf
    /// tournament's Sunday). Mirrors the app's `standardDate` / `effectiveEndDate`.
    static func span(of game: Game) -> (start: Date, end: Date)? {
        guard let start = game.isoDate ?? game.strTimestamp.flatMap(DateParsers.parse) else { return nil }
        let end = game.sessions?.last?.startDate ?? game.endDate.flatMap(DateParsers.parse) ?? start
        return (start, max(start, end))
    }

    /// Hot if any part of the game (a golf week, a race weekend) is on or after `start`,
    /// if it's under way, or if it has no date (nothing to place it by, so keep it).
    static func isHot(_ game: Game, start: Date) -> Bool {
        if game.strStatus == "in" { return true }
        guard let (_, end) = span(of: game) else { return true }
        return end >= start
    }

    /// `key`'s slice with each game list cut to `isIncluded`. Members that aren't game
    /// lists (standings, World Cup enrichment) are copied byte-for-byte, so the wire
    /// format (including the college split older apps rely on) is untouched.
    static func filteredBody(for key: LiveScore.WireKey, in source: String,
                             isIncluded: (Game) -> Bool) -> String {
        let bytes = Array(source.utf8)
        let ranges = CollegePayload.topLevelValueRanges(in: bytes)
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        var out: [UInt8] = [UInt8(ascii: "{")]
        for member in key.members {
            guard let range = ranges[member] else { continue }
            let raw = Array(bytes[range])
            var value = raw
            if let event = try? decoder.decode(LiveEvent.self, from: Data(raw)),
               let encoded = try? encoder.encode(LiveEvent(events: event.events.filter(isIncluded))) {
                value = Array(encoded)
            }
            if out.count > 1 { out.append(UInt8(ascii: ",")) }
            out.append(contentsOf: Array("\"\(member)\":".utf8))
            out.append(contentsOf: value)
        }
        out.append(UInt8(ascii: "}"))
        return String(decoding: out, as: UTF8.self)
    }

    static func hotBody(for key: LiveScore.WireKey, in source: String, now: Date) -> String {
        let start = hotStart(now: now)
        return filteredBody(for: key, in: source) { isHot($0, start: start) }
    }
}

/// A `/schedules/history` request: one slice, narrowed by any of a date range, a team,
/// a league or a single event.
struct ScheduleHistoryQuery: Equatable {
    let key: LiveScore.WireKey
    let from: Date?
    let to: Date?
    let team: String?
    let league: String?
    let event: String?

    /// Parses and bounds the query. Nil for anything malformed (a 400).
    init?(key rawKey: String?, from: String?, to: String?, team: String?, league: String?, event: String?) {
        guard let rawKey, let key = LiveScore.WireKey(rawValue: rawKey) else { return nil }
        func day(_ s: String?) -> Date?? {
            guard let s else { return .some(nil) }
            guard s.count == 8, s.allSatisfy(\.isNumber) else { return nil }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd"
            guard let date = formatter.date(from: s) else { return nil }
            return .some(date)
        }
        func id(_ s: String?) -> String?? {
            guard let s else { return .some(nil) }
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_:"))
            guard !s.isEmpty, s.count <= 40, s.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
            return .some(s)
        }
        guard let from = day(from), let to = day(to),
              let team = id(team), let league = id(league), let event = id(event) else { return nil }
        if let from, let to, to < from { return nil }
        self.key = key
        self.from = from
        self.to = to.map { $0.addingTimeInterval(86_400) }   // `to` is inclusive
        self.team = team
        self.league = league
        self.event = event
    }

    func admits(_ game: Game) -> Bool {
        if let event, game.idEvent != event, game.id != event { return false }
        if let league, game.idLeague != league { return false }
        if let team, game.idHomeTeam != team, game.idAwayTeam != team { return false }
        if from != nil || to != nil {
            guard let (start, end) = ScheduleWindow.span(of: game) else { return false }
            if let from, end < from { return false }
            if let to, start >= to { return false }
        }
        return true
    }

    /// Stable cache/ETag key for this query.
    var variant: String {
        func f(_ d: Date?) -> String { d.map { String(Int($0.timeIntervalSince1970)) } ?? "" }
        return "history:\(key.rawValue)|\(f(from))|\(f(to))|\(team ?? "")|\(league ?? "")|\(event ?? "")"
    }
}

/// Each slice member's games, decoded once per *calendar* version of its slice, so a
/// history request filters games in memory instead of decoding megabytes of JSON
/// (tennis alone is ~17MB) every time. Keyed on the calendar version rather than the
/// blob's content version: live ticks rewrite the blob every minute, but a past game's
/// fixture data is what history serves, and the calendar version moves when that does.
actor ScheduleHistoryIndex {
    static let shared = ScheduleHistoryIndex()

    private struct Member {
        let stamp: String
        /// The member verbatim when it isn't a game list; empty otherwise.
        let raw: [UInt8]
        let games: [Game]?
    }

    private var members: [String: Member] = [:]

    func body(for query: ScheduleHistoryQuery, source blob: String, stamp: String) -> String {
        let names = query.key.members
        if names.contains(where: { members[$0]?.stamp != stamp }) {
            let source = Array(blob.utf8)
            let ranges = CollegePayload.topLevelValueRanges(in: source)
            for name in names where members[name]?.stamp != stamp {
                guard let range = ranges[name] else { members[name] = nil; continue }
                let raw = Array(source[range])
                let games = (try? JSONDecoder().decode(LiveEvent.self, from: Data(raw)))?.events
                members[name] = Member(stamp: stamp, raw: games == nil ? raw : [], games: games)
            }
        }
        let encoder = JSONEncoder()
        var out: [UInt8] = [UInt8(ascii: "{")]
        for name in names {
            guard let member = members[name] else { continue }
            var value = member.raw
            if let games = member.games,
               let encoded = try? encoder.encode(LiveEvent(events: games.filter(query.admits))) {
                value = Array(encoded)
            }
            if out.count > 1 { out.append(UInt8(ascii: ",")) }
            out.append(contentsOf: Array("\"\(name)\":".utf8))
            out.append(contentsOf: value)
        }
        out.append(UInt8(ascii: "}"))
        return String(decoding: out, as: UTF8.self)
    }
}
