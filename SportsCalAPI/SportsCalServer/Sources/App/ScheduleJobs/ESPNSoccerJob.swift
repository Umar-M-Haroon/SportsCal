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
                        return (league, try await Integrator.getESPNScoreboard(for: league, context.application.client))
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

    /// Returns soccer leagues that should be fetched this tick. Driven by
    /// `Integrator.activeLeagues` (TSDB schedule ∪ ESPN schedule window). On cold start
    /// (both sources missing), falls back to fetching every soccer league.
    private func soccerLeaguesToFetch(redis: RedisClient, isDebug: Bool) async -> [Leagues] {
        guard let active = await Integrator.activeLeagues(redis: redis, isDebug: isDebug) else {
            return Leagues.allCases.filter { $0.isSoccer }
        }
        return active.filter { $0.isSoccer }
    }
}
