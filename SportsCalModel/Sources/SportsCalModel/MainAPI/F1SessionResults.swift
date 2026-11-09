//
//  F1SessionResults.swift
//  SportsCalModel
//
//  Official classifications from Jolpica, used to fill what ESPN's per-driver core
//  calls leave out (gaps from P8 down, teams) and to add qualifying's Q1/Q2/Q3.
//  The server caches these by race day and folds them into the F1 sessions; ESPN's
//  values always win where both exist.
//

import Foundation

/// One driver's line in a Jolpica classification.
public struct F1ResultRow: Codable, Equatable, Hashable {
    public var position: Int
    public var driverName: String
    public var constructor: String?
    /// Race/sprint: P1's total time, else "+0.799", "+1 Lap" or the status ("Retired").
    public var gap: String?
    /// Qualifying: Q1…Q3 as far as the driver got.
    public var qualifyingTimes: [String]?

    public init(position: Int, driverName: String, constructor: String? = nil, gap: String? = nil, qualifyingTimes: [String]? = nil) {
        self.position = position
        self.driverName = driverName
        self.constructor = constructor
        self.gap = gap
        self.qualifyingTimes = qualifyingTimes
    }
}

/// Everything Jolpica has for one Grand Prix weekend.
public struct F1RoundResults: Codable, Equatable, Hashable {
    public var round: Int
    /// The Grand Prix's day, "yyyy-MM-dd" (UTC): how a weekend is matched to ESPN's.
    public var raceDate: String
    public var qualifying: [F1ResultRow]
    public var sprint: [F1ResultRow]
    public var race: [F1ResultRow]
    /// Laps the winner completed, once the race is classified.
    public var raceLaps: Int?

    public init(round: Int, raceDate: String, qualifying: [F1ResultRow] = [], sprint: [F1ResultRow] = [], race: [F1ResultRow] = [], raceLaps: Int? = nil) {
        self.round = round
        self.raceDate = raceDate
        self.qualifying = qualifying
        self.sprint = sprint
        self.race = race
        self.raceLaps = raceLaps
    }

    public var isEmpty: Bool { qualifying.isEmpty && sprint.isEmpty && race.isEmpty }

    /// Rows for an ESPN session type, or nil for sessions Jolpica doesn't classify.
    public func rows(forSessionType type: String) -> [F1ResultRow]? {
        switch type.lowercased() {
        case "qual", "qualifying": qualifying
        case "sr", "sprint": sprint
        case "race", "r": race
        default: nil
        }
    }

    /// Q1 knocks out everyone below this place, Q2 everyone below the next: 22 cars
    /// race in 2026 (16/10), 20 before (15/10).
    public static func qualifyingCutLines(fieldSize: Int) -> (q1: Int, q2: Int) {
        fieldSize >= 22 ? (16, 10) : (15, 10)
    }
}

public extension Game {
    /// The UTC day of the weekend's Race session ("2026-11-01").
    var f1RaceDay: String? {
        guard let race = sessions?.first(where: { $0.sessionType.caseInsensitiveCompare("Race") == .orderedSame }),
              let start = race.startDate else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Sessions with Jolpica's classification folded in: missing teams and gaps filled,
    /// qualifying times added. Nil when nothing changed, so callers can skip the copy.
    func sessionsFilled(with results: F1RoundResults) -> [EventSession]? {
        guard let sessions, !results.isEmpty else { return nil }
        var changed = false
        let filled = sessions.map { session -> EventSession in
            guard let rows = results.rows(forSessionType: session.sessionType), !rows.isEmpty,
                  session.status == "post" else { return session }
            let next = session.filled(with: rows)
            if next != session { changed = true }
            return next
        }
        return changed ? filled : nil
    }
}

public extension Game {
    /// This weekend with Jolpica's classification and the race distance folded in, or nil
    /// when neither changes anything.
    func applyingF1Enrichment(results: F1RoundResults?, raceLaps: Int?) -> Game? {
        var sessions = results.flatMap(sessionsFilled(with:)) ?? self.sessions
        var changed = sessions != self.sessions
        if let laps = raceLaps ?? results?.raceLaps, laps > 0, let current = sessions {
            let withDistance = current.map { $0.importance == 6 ? $0.withRaceDistance(laps) : $0 }
            if withDistance != current {
                sessions = withDistance
                changed = true
            }
        }
        return changed ? updated(sessions: sessions) : nil
    }
}

public extension EventSession {
    /// A race's lap state with its distance set where it was unknown ("Lap 23" → "Lap 23/57").
    func withRaceDistance(_ laps: Int) -> EventSession {
        guard var state = raceState, state.totalLaps == 0, laps > 0 else { return self }
        state.totalLaps = laps
        return EventSession(sessionType: sessionType, sessionName: sessionName, status: status,
                            progress: progress == "Lap \(state.lap)" ? state.lapLabel : progress,
                            date: date, leaderboard: leaderboard, raceState: state)
    }

    /// This session with each driver's missing team/gap (and qualifying times) taken
    /// from `rows`, matched by name.
    func filled(with rows: [F1ResultRow]) -> EventSession {
        let entries = leaderboard.map { entry -> LeaderboardEntry in
            guard let row = F1ResultRow.match(entry.name, in: rows) else { return entry }
            return entry.filling(constructor: row.constructor, gap: row.gap, qualifyingTimes: row.qualifyingTimes)
        }
        return replacingLeaderboard(entries)
    }

    /// Same session, new leaderboard.
    func replacingLeaderboard(_ entries: [LeaderboardEntry]) -> EventSession {
        EventSession(sessionType: sessionType, sessionName: sessionName, status: status, progress: progress,
                     date: date, leaderboard: entries, raceState: raceState)
    }

    /// Keeps what enrichment added (teams, gaps, qualifying times) when a fresher copy of
    /// the same session arrives without them: live ticks rebuild sessions from ESPN alone.
    func carryingEnrichment(from stale: EventSession) -> EventSession {
        guard stale.sessionType == sessionType else { return self }
        // The race distance comes from the schedule build; a live tick only knows the lap.
        let result = stale.raceState.map { withRaceDistance($0.totalLaps) } ?? self
        return result.carryingEntries(from: stale)
    }

    private func carryingEntries(from stale: EventSession) -> EventSession {
        guard !stale.leaderboard.isEmpty else { return self }
        let byName = Dictionary(stale.leaderboard.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        let entries = leaderboard.map { entry -> LeaderboardEntry in
            guard let old = byName[entry.name],
                  (entry.constructor == nil && old.constructor != nil)
                    || (entry.gap == nil && old.gap != nil)
                    || (entry.qualifyingTimes == nil && old.qualifyingTimes != nil) else { return entry }
            changed = true
            return entry.filling(constructor: old.constructor, gap: old.gap, qualifyingTimes: old.qualifyingTimes)
        }
        return changed ? replacingLeaderboard(entries) : self
    }
}

public extension Array where Element == EventSession {
    /// `carryingEnrichment(from:)` across a weekend, matched by session type.
    func carryingEnrichment(from stale: [EventSession]?) -> [EventSession] {
        guard let stale, !stale.isEmpty else { return self }
        return map { fresh in
            stale.first { $0.sessionType == fresh.sessionType }.map(fresh.carryingEnrichment(from:)) ?? fresh
        }
    }
}

extension F1ResultRow {
    /// Same driver across ESPN and Jolpica: the folded full name, else a unique surname
    /// (ESPN "Andrea Kimi Antonelli" vs Jolpica "Kimi Antonelli").
    static func match(_ name: String, in rows: [F1ResultRow]) -> F1ResultRow? {
        let key = F1Standings.driverKey(name)
        if let exact = rows.first(where: { F1Standings.driverKey($0.driverName) == key }) { return exact }
        let surname = key.split(separator: " ").last.map(String.init)
        let hits = rows.filter { F1Standings.driverKey($0.driverName).split(separator: " ").last.map(String.init) == surname }
        return hits.count == 1 ? hits.first : nil
    }
}
