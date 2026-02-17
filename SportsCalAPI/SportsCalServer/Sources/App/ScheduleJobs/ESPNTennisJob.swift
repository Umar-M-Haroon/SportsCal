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

    func run(context: Queues.QueueContext) async throws {
        let endpoint = RedisEndpoint.ESPN.allTennisScoreboards.getValue(isDebug: context.application.environment == .development)
        let tennisScoreboards = try await context.application.redis.get(endpoint, asJSON: [Leagues: Scoreboard].self)
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
        if leaguesToFetch == Leagues.allCases.filter({$0.isTennis}) {
            try await context.application.redis.setex(RedisEndpoint.ESPN.allTennisScoreboards.getValue(isDebug: context.application.environment == .development), toJSON: espnInfo, expirationInSeconds: 60 * 60)
        }
        try await context.application.redis.set(RedisEndpoint.ESPN.latestTennisScoreboards.getValue(isDebug: context.application.environment == .development), toJSON: espnInfo)
    }

    func getActiveLeagues(tennisScoreboards: [Leagues: Scoreboard]?) -> [Leagues] {
        var activeScoreboards: [Leagues: Scoreboard] = [:]

        let formatter = DateFormatters.backupISOFormatter
        formatter.timeZone = .init(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        let calendar = Calendar.current
        if let tennisBoards = tennisScoreboards {
            for (league, scoreboard) in tennisBoards {
                let date = Date()
                let hasAnyUpcomingEvents = scoreboard.events.contains(where: { game in
                    guard let gameDate = formatter.date(from: game.date) else { return false }
                    let components = calendar.dateComponents([.day, .hour, .month, .year, .minute], from: date, to: gameDate)
                    let isValidTime = components.day ?? -1 == 0 &&
                    components.hour ?? -1 == 0 &&
                    components.month ?? -1 == 0 &&
                    components.year ?? -1 == 0 &&
                    components.minute ?? -1 <= 1
                    return isValidTime
                })
                let hasLiveEvents = scoreboard.events.contains(where: { game in
                    guard let status = game.status else { return false }
                    return !status.type.completed && status.type.state != "pre" && status.type.state != "post"
                })
                if hasAnyUpcomingEvents || hasLiveEvents {
                    activeScoreboards[league] = scoreboard
                }
            }
            return activeScoreboards.map({$0.key})
        } else {
            return Leagues.allCases.filter({$0.isTennis})
        }
    }
}
