//
//  ESPNCricketJob.swift
//
//  Cricket is ESPN-only (TheSportsDB has no live cricket and patchy internationals; the
//  TheSportsDB schedule job skips cricket leagues). ESPN files every international tour
//  under a fresh league id, so instead of per-league scoreboards everything comes from
//  one board: the all-cricket score panel, decoded by `ESPNCricketBoard`, whose
//  `games()` already drops the competitions we don't carry.
//
//  Two halves:
//  - Schedule: this job sweeps `scorepanel?dates=` for every day from −5 to +120 (~126
//    requests, a few at a time), de-dupes by `idEvent` (a Test is on the panel every day
//    it spans) and owns `schedule.cricket` in the shared schedule blob. Hourly, gated to
//    a real sweep every ~6h.
//  - Live: `liveGames` fetches the undated panel. ESPNFetchJob calls it every minute
//    while a cricket league is active, and the LiveTicker overlays in-progress matches
//    from it on the fast cadence (`Paced.cricket`).
//

import Foundation
import Vapor
import Queues
import RediStack
import SportsCalModel
import Logging

struct ESPNCricketJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.espn-cricket")

    /// The sweep. ESPN serves about a month of past days (older ones 502) and months ahead.
    static let daysBack = 5
    static let daysAhead = 120
    static let refreshInterval: TimeInterval = 6 * 3600
    static let maxConcurrent = 3
    /// Finished matches older than this fall out of the schedule (the sweep only ever
    /// re-fetches the last `daysBack` days, so older results are kept, not refreshed).
    static let historyRetention: TimeInterval = 180 * 86_400

    func run(context: Queues.QueueContext) async throws {
        let app = context.application
        let isDebug = app.environment == .development
        let updateKey = RedisEndpoint.ESPN.cricketScheduleLastUpdate.getValue(isDebug: isDebug)
        let cacheKey = RedisEndpoint.ESPN.cricketSchedule.getValue(isDebug: isDebug)

        if let last = try? await app.redis.get(updateKey, asJSON: Date.self),
           Date().timeIntervalSince(last) < Self.refreshInterval,
           ((try? await app.redis.exists(cacheKey).get()) ?? 0) > 0 {
            await JobHeartbeat.recordSuccess(.cricket, app: app, isDebug: isDebug)
            return
        }

        let now = Date()
        let days = Self.dayKeys(now: now)
        let results = await Self.sweep(days: days, client: app.client)
        let fetched = results.compactMap { $0.games }
        let coveredDays = Set(results.filter { $0.games != nil }.map { Self.isoDay(fromKey: $0.day) })
        Self.logger.info("Cricket sweep finished", metadata: [
            "days": "\(days.count)",
            "failed": "\(days.count - fetched.count)",
            "games": "\(fetched.reduce(0) { $0 + $1.count })"
        ])
        // Every day failing is an outage (or the Akamai block), not an empty calendar:
        // keep what we have and retry next hour.
        guard !fetched.isEmpty else {
            Self.logger.warning("Cricket sweep fetched nothing — keeping the previous schedule")
            return
        }
        let fresh = Self.dedupedAcrossDays(fetched)

        let prior = (try? await app.redis.get(cacheKey, asJSON: [Game].self)) ?? []
        let sweep = Self.mergingSweep(fresh: fresh, prior: prior, coveredDays: coveredDays, now: now)
        try await app.redis.set(cacheKey, toJSON: sweep)

        let outcome = try await ScheduleStore.update(
            app: app, isDebug: isDebug, logger: Self.logger, writer: "ESPNCricketJob"
        ) { schedule in
            // Nothing to merge into until ScheduleUpdateJob seeds the blob; it picks the
            // cached sweep up when it does.
            guard var schedule else { return nil }
            let merged = Self.mergingSweep(
                fresh: sweep, prior: schedule.cricket?.events ?? [], coveredDays: coveredDays, now: now
            )
            schedule.cricket = merged.isEmpty ? nil : LiveEvent(events: merged)
            return schedule
        }
        if outcome == .lockTimeout { return }
        try await app.redis.set(updateKey, toJSON: now)
        await JobHeartbeat.recordSuccess(.cricket, app: app, isDebug: isDebug)
    }

    // MARK: - Fetching

    /// Today's (and live) cricket from the undated score panel, or nil when ESPN failed.
    static func liveGames(client: some Client) async -> [Game]? {
        do {
            return try await ESPNNetworking.getCricketScorePanel(req: client).games()
        } catch {
            logger.debug("Cricket live panel fetch failed", metadata: ["error": "\(error)"])
            return nil
        }
    }

    /// One score panel per day, `maxConcurrent` at a time, in `days` order. `games` is nil
    /// for a day that failed twice.
    static func sweep(days: [Int], client: some Client) async -> [(day: Int, games: [Game]?)] {
        var results: [Int: [Game]?] = [:]
        var iterator = days.makeIterator()
        await withTaskGroup(of: (Int, [Game]?).self) { group in
            func addNext() {
                guard let day = iterator.next() else { return }
                group.addTask { (day, await fetchDay(day, client: client)) }
            }
            for _ in 0..<min(maxConcurrent, days.count) { addNext() }
            while let (day, games) = await group.next() {
                results[day] = .some(games)
                addNext()
            }
        }
        return days.map { day in (day, results[day] ?? nil) }
    }

    /// ESPN's panel answers the odd day with a 400/502 that succeeds on a second try.
    private static func fetchDay(_ day: Int, client: some Client) async -> [Game]? {
        for attempt in 0..<2 {
            do {
                return try await ESPNNetworking.getCricketScorePanel(req: client, dates: day).games()
            } catch NetworkError.cooledDown {
                return nil
            } catch {
                if attempt == 0 { try? await Task.sleep(nanoseconds: 500_000_000) }
                logger.debug("Cricket panel fetch failed", metadata: ["day": "\(day)", "error": "\(error)"])
            }
        }
        return nil
    }

    /// `yyyyMMdd` keys from `daysBack` before `now` to `daysAhead` after it, UTC.
    static func dayKeys(now: Date = Date()) -> [Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return (-daysBack...daysAhead).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: now).flatMap { Int(formatter.string(from: $0)) }
        }
    }

    /// 20261121 → "2026-11-21".
    static func isoDay(fromKey key: Int) -> String {
        let digits = String(key)
        guard digits.count == 8 else { return digits }
        let year = digits.prefix(4)
        let month = digits.dropFirst(4).prefix(2)
        let day = digits.suffix(2)
        return "\(year)-\(month)-\(day)"
    }

    // MARK: - Merging (pure, for tests)

    /// One game per `idEvent` across day panels given in chronological order. A multi-day
    /// Test is on every day it spans: the copy from the latest day wins, unless an earlier
    /// day's copy is further along (pre < in < post). First-seen order is kept.
    static func dedupedAcrossDays(_ days: [[Game]]) -> [Game] {
        var order: [String] = []
        var byID: [String: Game] = [:]
        var unkeyed: [Game] = []
        for games in days {
            for game in games {
                guard let id = game.idEvent, !id.isEmpty else { unkeyed.append(game); continue }
                if let existing = byID[id] {
                    if stateRank(game) >= stateRank(existing) { byID[id] = game }
                } else {
                    order.append(id)
                    byID[id] = game
                }
            }
        }
        return order.compactMap { byID[$0] } + unkeyed
    }

    /// The new cricket schedule from a sweep (`fresh`) and what was there before (`prior`).
    ///
    /// - A fresh game replaces its prior copy, unless the prior one is further along: the
    ///   live merge (ESPNFetchJob) may have moved it on while the sweep was running.
    /// - A prior game the sweep didn't return is dropped only when ESPN was asked about its
    ///   day and both neighbours (the panel's day boundary isn't UTC) — it was moved or
    ///   called off. Games on days the sweep didn't cover (older results, a failed day)
    ///   are kept, back to `historyRetention`.
    static func mergingSweep(fresh: [Game], prior: [Game], coveredDays: Set<String>, now: Date) -> [Game] {
        let priorByID = Dictionary(prior.compactMap { g in g.idEvent.map { ($0, g) } }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var result: [Game] = []
        result.reserveCapacity(fresh.count + prior.count)
        for game in fresh {
            guard let id = game.idEvent else { result.append(game); continue }
            guard seen.insert(id).inserted else { continue }
            if let old = priorByID[id], stateRank(old) > stateRank(game) {
                result.append(old)
            } else {
                result.append(game)
            }
        }
        let cutoff = now.addingTimeInterval(-historyRetention)
        for game in prior {
            guard let id = game.idEvent, !seen.contains(id) else { continue }
            let date = kickoff(game)
            if let date, date < cutoff { continue }
            if let date, isCovered(date, by: coveredDays) { continue }
            seen.insert(id)
            result.append(game)
        }
        return result.sorted { (kickoff($0) ?? .distantFuture) < (kickoff($1) ?? .distantFuture) }
    }

    /// Live panel games merged into the schedule's cricket bucket by `idEvent` (both come
    /// from the same ESPN builder, so ids match exactly). A live copy replaces the
    /// schedule's unless the schedule's is further along; live-only games are appended.
    static func mergingLive(schedule: LiveEvent?, live: LiveEvent?) -> LiveEvent? {
        guard let live, !live.events.isEmpty else { return schedule }
        guard let schedule else { return live }
        var liveByID: [String: Game] = [:]
        for game in live.events {
            if let id = game.idEvent { liveByID[id] = game }
        }
        var used = Set<String>()
        var events = schedule.events.map { game -> Game in
            guard let id = game.idEvent, let fresh = liveByID[id] else { return game }
            used.insert(id)
            return stateRank(game) > stateRank(fresh) ? game : fresh
        }
        for game in live.events {
            guard let id = game.idEvent, !used.contains(id) else { continue }
            used.insert(id)
            events.append(game)
        }
        return LiveEvent(events: events)
    }

    static func stateRank(_ game: Game) -> Int {
        switch game.strStatus {
        case "post": return 2
        case "in": return 1
        default: return game.isCompleted == true ? 2 : 0
        }
    }

    private static func kickoff(_ game: Game) -> Date? {
        game.isoDate ?? game.strTimestamp.flatMap(DateParsers.parse)
    }

    private static func isCovered(_ date: Date, by days: Set<String>) -> Bool {
        guard !days.isEmpty else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return [-86_400.0, 0, 86_400].allSatisfy { days.contains(formatter.string(from: date.addingTimeInterval($0))) }
    }
}
