//
//  ESPNTennisJob.swift
//
//  Created by Umar Haroon on 2/7/26.
//

import Foundation
import Queues
import RediStack
import SportsCalModel
import Logging

struct ESPNTennisJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.espn-tennis")

    func run(context: Queues.QueueContext) async throws {
        let isDebug = context.application.environment == .development
        let ttlKey = RedisEndpoint.ESPN.allTennisScoreboards.getValue(isDebug: isDebug)
        let latestKey = RedisEndpoint.ESPN.latestTennisScoreboards.getValue(isDebug: isDebug)

        var priorBoards: [Leagues: Scoreboard] = [:]
        if let cached = try? await context.application.redis.get(ttlKey, asJSON: [Leagues: Scoreboard].self) {
            priorBoards = cached
        } else if let cached = try? await context.application.redis.get(latestKey, asJSON: [Leagues: Scoreboard].self) {
            priorBoards = cached
        }

        let leaguesToFetch = await tennisLeaguesToFetch(redis: context.application.redis, isDebug: isDebug)
        guard !leaguesToFetch.isEmpty else {
            if !priorBoards.isEmpty {
                try await context.application.redis.setex(ttlKey, toJSON: priorBoards, expirationInSeconds: 60 * 15)
                try await context.application.redis.set(latestKey, toJSON: priorBoards)
            }
            return
        }

        Self.logger.info("Fetching tennis leagues", metadata: ["leagues": "\(leaguesToFetch)"])
        var espnInfo = await withTaskGroup(of: (Leagues, Scoreboard?).self) { group in
            var results: [Leagues: Scoreboard] = [:]
            for league in leaguesToFetch {
                group.addTask {
                    do {
                        return (league, try await Integrator.getESPNScoreboard(for: league, context.application.client))
                    } catch {
                        Self.logger.debug("Failed to fetch tennis scoreboard", metadata: [
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
        espnInfo.merge(priorBoards) { new, _ in new }

        try await context.application.redis.setex(ttlKey, toJSON: espnInfo, expirationInSeconds: 60 * 15)
        try await context.application.redis.set(latestKey, toJSON: espnInfo)
    }

    private func tennisLeaguesToFetch(redis: RedisClient, isDebug: Bool) async -> [Leagues] {
        guard let active = await Integrator.activeLeagues(redis: redis, isDebug: isDebug) else {
            return Leagues.allCases.filter { $0.isTennis }
        }
        return active.filter { $0.isTennis }
    }
}
