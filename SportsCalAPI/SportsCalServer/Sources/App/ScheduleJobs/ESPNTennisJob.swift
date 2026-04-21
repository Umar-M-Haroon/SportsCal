//
//  ESPNTennisJob.swift
//
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
    private static var isFirstRun = true

    func run(context: Queues.QueueContext) async throws {
        let isDebug = context.application.environment == .development
        let ttlKey = RedisEndpoint.ESPN.allTennisScoreboards.getValue(isDebug: isDebug)
        let latestKey = RedisEndpoint.ESPN.latestTennisScoreboards.getValue(isDebug: isDebug)

        let tennisScoreboards: [Leagues: Scoreboard]?
        if Self.isFirstRun {
            Self.isFirstRun = false
            if let seeded = try? await context.application.redis.get(latestKey, asJSON: [Leagues: Scoreboard].self) {
                tennisScoreboards = seeded
                Self.logger.info("First run after startup — seeded from latestTennisScoreboards (\(seeded.count) leagues cached)")
            } else {
                tennisScoreboards = nil
                Self.logger.info("First run after startup — no cached scoreboards, fetching all tennis leagues")
            }
        } else {
            if let cached = try await context.application.redis.get(ttlKey, asJSON: [Leagues: Scoreboard].self) {
                tennisScoreboards = cached
            } else {
                tennisScoreboards = try? await context.application.redis.get(latestKey, asJSON: [Leagues: Scoreboard].self)
            }
        }
        let leaguesToFetch = getActiveLeagues(tennisScoreboards: tennisScoreboards)
        Self.logger.info("Fetching tennis leagues", metadata: ["leagues": "\(leaguesToFetch)"])
        var espnInfo = try await withThrowingTaskGroup(of: [Leagues: Scoreboard].self) { group in
            var espnInfo: [Leagues: Scoreboard] = [:]
            for league in leaguesToFetch {
                group.addTask {
                    do {
                        return [league : try await Integrator.getESPNScoreboard(for: league, context.application.client)]
                    } catch {
                        Self.logger.error("Failed to fetch tennis scoreboard", metadata: [
                            "league": "\(league)",
                            "error": "\(error)"
                        ])
                    }
                    return [:]
                }
            }
            for try await scores in group {
                espnInfo.merge(scores, uniquingKeysWith: { s1, s2 in
                    return s1
                })
            }
            return espnInfo
        }
        if let boards = tennisScoreboards {
            espnInfo.merge(boards, uniquingKeysWith: { s1, s2 in
                return s1
            })
        }
        // Always refresh the TTL — espnInfo already includes cached scoreboards for skipped
        // leagues via the merge above, so a full snapshot is written every run.
        try await context.application.redis.setex(ttlKey, toJSON: espnInfo, expirationInSeconds: 60 * 15)
        try await context.application.redis.set(latestKey, toJSON: espnInfo)
    }

    func getActiveLeagues(tennisScoreboards: [Leagues: Scoreboard]?) -> [Leagues] {
        var activeScoreboards: [Leagues: Scoreboard] = [:]

        let formatter = DateFormatters.backupISOFormatter
        formatter.timeZone = .init(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        if let tennisBoards = tennisScoreboards {
            for (league, scoreboard) in tennisBoards {
                let date = Date()
                let hasAnyUpcomingEvents = scoreboard.events.contains(where: { game in
                    guard let gameDate = formatter.date(from: game.date) else { return false }
                    let minutesUntil = gameDate.timeIntervalSince(date) / 60
                    return minutesUntil >= -1 && minutesUntil <= 5
                })
                let hasLiveEvents = scoreboard.events.contains(where: { game in
                    guard let status = game.status else { return false }
                    return !status.type.completed && status.type.state != "pre" && status.type.state != "post"
                })
                let hasProbablyStartedEvents = scoreboard.events.contains(where: { game in
                    guard let gameDate = formatter.date(from: game.date) else { return false }
                    let minutesAgo = date.timeIntervalSince(gameDate) / 60
                    let status = game.status?.type
                    let isStillMarkedPre = status?.state == "pre" || status == nil
                    return isStillMarkedPre && minutesAgo >= 2 && minutesAgo <= 180
                })
                if hasAnyUpcomingEvents || hasLiveEvents || hasProbablyStartedEvents {
                    activeScoreboards[league] = scoreboard
                }
            }
            return activeScoreboards.map({$0.key})
        } else {
            return Leagues.allCases.filter({$0.isTennis})
        }
    }
}
