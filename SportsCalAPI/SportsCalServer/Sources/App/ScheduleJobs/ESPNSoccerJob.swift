//
//  File.swift
//
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
    /// Forces a full fetch on the first run after server startup, bypassing stale cached statuses.
    private static var isFirstRun = true

    func run(context: Queues.QueueContext) async throws {
        let isDebug = context.application.environment == .development
        let ttlKey = RedisEndpoint.ESPN.allSoccerScoreboards.getValue(isDebug: isDebug)
        let latestKey = RedisEndpoint.ESPN.latestSoccerScoreboards.getValue(isDebug: isDebug)

        let soccerScoreboards: [Leagues: Scoreboard]?
        if Self.isFirstRun {
            Self.isFirstRun = false
            if let seeded = try? await context.application.redis.get(latestKey, asJSON: [Leagues: Scoreboard].self) {
                soccerScoreboards = seeded
                Self.logger.info("First run after startup — seeded from latestSoccerScoreboards (\(seeded.count) leagues cached)")
            } else {
                soccerScoreboards = nil
                Self.logger.info("First run after startup — no cached scoreboards, fetching all soccer leagues")
            }
        } else {
            if let cached = try await context.application.redis.get(ttlKey, asJSON: [Leagues: Scoreboard].self) {
                soccerScoreboards = cached
            } else {
                soccerScoreboards = try? await context.application.redis.get(latestKey, asJSON: [Leagues: Scoreboard].self)
            }
        }
        let leaguesToFetch = getActiveLeagues(soccerScoreboards: soccerScoreboards)
        Self.logger.info("Fetching soccer leagues", metadata: ["leagues": "\(leaguesToFetch)"])
        var espnInfo = try await withThrowingTaskGroup(of: [Leagues: Scoreboard].self) { group in
            var espnInfo: [Leagues: Scoreboard] = [:]
            for league in leaguesToFetch {
                group.addTask {
                    do {
                        return [league : try await Integrator.getESPNScoreboard(for: league, context.application.client)]
                    } catch {
                        Self.logger.error("Failed to fetch soccer scoreboard", metadata: [
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
        if let boards = soccerScoreboards {
            espnInfo.merge(boards, uniquingKeysWith: { s1, s2 in
                return s1
            })
        }
        // Always refresh the TTL — espnInfo already includes cached scoreboards for skipped
        // leagues via the merge above, so a full snapshot is written every run. Without this,
        // selective-refetch runs would let the key expire and the next tick would cold-fanout.
        try await context.application.redis.setex(ttlKey, toJSON: espnInfo, expirationInSeconds: 60 * 15)
        try await context.application.redis.set(latestKey, toJSON: espnInfo)
    }
    
    func getActiveLeagues(soccerScoreboards: [Leagues: Scoreboard]?) -> [Leagues] {
        var activeScoreboards: [Leagues: Scoreboard] = [:]

        let formatter = DateFormatters.backupISOFormatter
        formatter.timeZone = .init(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        if let soccerBoards = soccerScoreboards {
            for (league, scoreboard) in soccerBoards {

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
                // Check if any game should have started recently but cache still shows "pre".
                // This catches games that started after the last full scoreboard refresh —
                // the cached status is stale ("pre") but the scheduled time is in the past.
                let hasProbablyStartedEvents = scoreboard.events.contains(where: { game in
                    guard let gameDate = formatter.date(from: game.date) else { return false }
                    let minutesAgo = date.timeIntervalSince(gameDate) / 60
                    let status = game.status?.type
                    let isStillMarkedPre = status?.state == "pre" || status == nil
                    // Game was scheduled 2–180 min ago but cache still says "pre"
                    return isStillMarkedPre && minutesAgo >= 2 && minutesAgo <= 180
                })
                if hasAnyUpcomingEvents || hasLiveEvents || hasProbablyStartedEvents {
                    activeScoreboards[league] = scoreboard
                }
            }
            return activeScoreboards.map({$0.key})
        } else {
            return Leagues.allCases.filter({$0.isSoccer})
        }

    }
}
