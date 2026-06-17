//
//  ESPNSoccerJob.swift
//
//  Created by Umar Haroon on 2/23/23.
//

import Foundation
import Queues
import RediStack
import SportsCalModel
import Logging

struct ESPNSoccerJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.espn-soccer")

    func run(context: Queues.QueueContext) async throws {
        let isDebug = context.application.environment == .development
        let ttlKey = RedisEndpoint.ESPN.allSoccerScoreboards.getValue(isDebug: isDebug)
        let latestKey = RedisEndpoint.ESPN.latestSoccerScoreboards.getValue(isDebug: isDebug)

        // Prior cache (may be stale — we use it only for the merge write-back so leagues
        // not refetched this tick still ship in the full snapshot).
        var priorBoards: [Leagues: Scoreboard] = [:]
        if let cached = try? await context.application.redis.get(ttlKey, asJSON: [Leagues: Scoreboard].self) {
            priorBoards = cached
        } else if let cached = try? await context.application.redis.get(latestKey, asJSON: [Leagues: Scoreboard].self) {
            priorBoards = cached
        }

        let leaguesToFetch = await soccerLeaguesToFetch(redis: context.application.redis, isDebug: isDebug)
        guard !leaguesToFetch.isEmpty else {
            // Nothing active right now. Refresh the TTL so the cache key doesn't expire,
            // keeping the full prior snapshot around for /schedules consumers.
            if !priorBoards.isEmpty {
                try await context.application.redis.setex(ttlKey, toJSON: priorBoards, expirationInSeconds: 60 * 15)
                try await context.application.redis.set(latestKey, toJSON: priorBoards)
            }
            return
        }

        Self.logger.info("Fetching soccer leagues", metadata: ["leagues": "\(leaguesToFetch)"])
        var espnInfo = await withTaskGroup(of: (Leagues, Scoreboard?).self) { group in
            var results: [Leagues: Scoreboard] = [:]
            for league in leaguesToFetch {
                group.addTask {
                    do {
                        if league == .FIFA_World_Cup {
                            // The season query (`?dates=<year>`) carries the full fixture
                            // list for the hub/hero, but ESPN serves its live clock and the
                            // FT transition more slowly on that endpoint than on the default
                            // (today) scoreboard — so a WC match would lag and linger at the
                            // last in-play minute after it ended. Fetch both concurrently and
                            // prefer today's fresher copy for any in-progress fixture, while
                            // keeping the season board's full fixture list.
                            let year = Calendar.current.component(.year, from: Date())
                            async let seasonReq = Integrator.getESPNScoreboard(for: league, context.application.client, dates: year)
                            async let todayReq = Integrator.getESPNScoreboard(for: league, context.application.client, dates: nil)
                            var season = try await seasonReq
                            if let today = try? await todayReq {
                                season.events = Self.mergeWorldCupEvents(season: season.events, today: today.events)
                            }
                            return (league, season)
                        }
                        // Other leagues use ESPN's default (imminent) window.
                        return (league, try await Integrator.getESPNScoreboard(for: league, context.application.client, dates: nil))
                    } catch {
                        Self.logger.debug("Failed to fetch soccer scoreboard", metadata: [
                            "league": "\(league)",
                            "error":  "\(error)"
                        ])
                        return (league, nil)
                    }
                }
            }
            for await (league, board) in group {
                if let board { results[league] = board }
            }
            return results
        }
        // Fill in leagues we didn't refetch with their prior cache (don't drop them).
        espnInfo.merge(priorBoards) { new, _ in new }

        try await context.application.redis.setex(ttlKey, toJSON: espnInfo, expirationInSeconds: 60 * 15)
        try await context.application.redis.set(latestKey, toJSON: espnInfo)
    }

    /// Merges the World Cup season-query events with the fresher "today" events,
    /// preferring today's copy for any fixture present in both (its live clock, score
    /// and FT transition are more current). Season-only events are kept in place so
    /// the full fixture list survives; today-only events are appended. Order-preserving
    /// and pure, so it's unit-testable without booting the job. `internal` for tests.
    static func mergeWorldCupEvents(season: [Event], today: [Event]) -> [Event] {
        guard !today.isEmpty else { return season }
        let todayByID = Dictionary(today.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var seen = Set<String>()
        var merged: [Event] = []
        merged.reserveCapacity(season.count + today.count)
        for event in season {
            seen.insert(event.id)
            merged.append(todayByID[event.id] ?? event)
        }
        for event in today where !seen.contains(event.id) {
            merged.append(event)
        }
        return merged
    }

    /// Returns soccer leagues that should be fetched this tick. Driven by
    /// `Integrator.activeLeagues` (TSDB schedule ∪ ESPN schedule window). On cold start
    /// (both sources missing), falls back to fetching every soccer league.
    private func soccerLeaguesToFetch(redis: RedisClient, isDebug: Bool) async -> [Leagues] {
        var leagues: [Leagues]
        if let active = await Integrator.activeLeagues(redis: redis, isDebug: isDebug) {
            leagues = active.filter { $0.isSoccer }
        } else {
            leagues = Leagues.allCases.filter { $0.isSoccer }
        }
        // The World Cup's fixtures don't enter the live window until ~30 min before
        // kickoff, but the Games-tab hero and the World Cup hub need upcoming matches
        // days ahead (next-kickoff countdown, fixture ticker). Keep it in the fetch
        // set for the tournament era so ESPN's `fifa.world` schedule populates eagerly.
        if Self.worldCupFetchWindow.contains(Date()), !leagues.contains(.FIFA_World_Cup) {
            leagues.append(.FIFA_World_Cup)
        }
        return leagues
    }

    /// Pre-tournament lead-in through the final: fetch World Cup fixtures eagerly in
    /// this range so they're in the schedule before they reach the live window.
    /// (2026 FIFA Men's World Cup: Jun 11 – Jul 19, 2026.)
    private static let worldCupFetchWindow: ClosedRange<Date> = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 15)) ?? .distantPast
        let end = cal.date(from: DateComponents(year: 2026, month: 7, day: 20)) ?? .distantFuture
        return start...end
    }()
}
