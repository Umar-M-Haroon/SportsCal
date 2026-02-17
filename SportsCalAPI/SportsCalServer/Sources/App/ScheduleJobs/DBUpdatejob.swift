//
//  DBUpdateJob.swift
//  
//
//  Created by Umar Haroon on 10/21/22.
//

import Foundation
import Queues
import RediStack
import SportsCalModel
import Logging

struct ScheduleUpdateJob: AsyncScheduledJob {
    private static let logger = Logger(label: "com.sportscal.schedule-update")

    /// Extracts unique teams from games to ensure multi-season coverage
    private func extractTeamsFromGames(_ games: [Game]) -> [Team] {
        var teamsDict: [String: Team] = [:]

        for game in games {
            // Extract home team
            if let idHomeTeam = game.idHomeTeam, !idHomeTeam.isEmpty {
                if teamsDict[idHomeTeam] == nil {
                    teamsDict[idHomeTeam] = Team(
                        idTeam: idHomeTeam,
                        strTeam: game.strHomeTeam,
                        strTeamShort: nil,
                        strAlternate: nil,
                        strTeamBadge: game.strHomeTeamBadge
                    )
                }
            }

            // Extract away team
            if let idAwayTeam = game.idAwayTeam, !idAwayTeam.isEmpty {
                if teamsDict[idAwayTeam] == nil {
                    teamsDict[idAwayTeam] = Team(
                        idTeam: idAwayTeam,
                        strTeam: game.strAwayTeam,
                        strTeamShort: nil,
                        strAlternate: nil,
                        strTeamBadge: game.strAwayTeamBadge
                    )
                }
            }
        }

        return Array(teamsDict.values)
    }

    /// Merges teams from API with teams extracted from games
    /// Prefers API teams (which have more complete data like strTeamShort)
    private func mergeTeams(apiTeams: [Team], gameTeams: [Team]) -> [Team] {
        var mergedDict: [String: Team] = [:]

        // Add game teams first (as fallback)
        for team in gameTeams {
            if let idTeam = team.idTeam {
                mergedDict[idTeam] = team
            }
        }

        // Override with API teams (which have better data)
        for team in apiTeams {
            if let idTeam = team.idTeam {
                mergedDict[idTeam] = team
            }
        }

        return Array(mergedDict.values)
    }

    /// Counts total games across all sports in a LiveScore
    private func countGames(in score: LiveScore) -> Int {
        [score.nba, score.mlb, score.soccer, score.nfl, score.nhl, score.golf, score.tennis, score.racing]
            .compactMap { $0?.events.count }
            .reduce(0, +)
    }

    func run(context: Queues.QueueContext) async throws {
        let isDebug = context.application.environment == .development

        // Only fetch live scores if there are games happening or starting soon
        let shouldFetchLive = await Integrator.hasLiveOrUpcomingGames(
            redis: context.application.redis,
            isDebug: isDebug
        )

        if shouldFetchLive {
            Self.logger.info("Fetching TheSportsDB live scores")
            let liveResult = await Integrator.getAllLiveScores(context.application.client)
            try await context.application.redis.setex(RedisEndpoint.SportsDB.latestFullLiveInfo.getValue(isDebug: isDebug), toJSON: liveResult, expirationInSeconds: 60 * 30)
            try await context.application.redis.set(RedisEndpoint.SportsDB.latestLiveInfo.getValue(isDebug: isDebug), toJSON: liveResult)
            Self.logger.info("TheSportsDB live scores updated")
        } else {
            Self.logger.info("No live or upcoming games — skipping TheSportsDB live score fetch")
        }

        // Check if schedules already exist in Redis
        let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
        let teamsKey = RedisEndpoint.SportsDB.teams.getValue(isDebug: isDebug)
        let lastUpdateKey = RedisEndpoint.ESPN.scheduleLastUpdate.getValue(isDebug: isDebug)

        Self.logger.debug("Redis keys loaded", metadata: [
            "scheduleKey": "\(scheduleKey)",
            "teamsKey": "\(teamsKey)",
            "lastUpdateKey": "\(lastUpdateKey)"
        ])

        let existingSchedule = try await context.application.redis.get(scheduleKey, asJSON: LiveScore.self)
        let existingTeams = try await context.application.redis.get(teamsKey, asJSON: [Team].self)
        let lastUpdateTime = try await context.application.redis.get(lastUpdateKey, asJSON: Date.self)

        Self.logger.info("Cache status", metadata: [
            "scheduleExists": "\(existingSchedule != nil)",
            "teamsCount": "\(existingTeams?.count ?? 0)",
            "lastUpdate": "\(lastUpdateTime?.description ?? "never")"
        ])

        // Refresh schedules if missing or if it's been more than 1 hour
        let shouldRefreshSchedules: Bool
        if let _ = existingSchedule, let existingTeams, !existingTeams.isEmpty {
            if let lastUpdate = lastUpdateTime {
                let hoursSinceUpdate = Date().timeIntervalSince(lastUpdate) / 3600
                shouldRefreshSchedules = hoursSinceUpdate > 1
                if shouldRefreshSchedules {
                    Self.logger.info("Schedules stale, refreshing from API", metadata: ["hoursSinceUpdate": "\(String(format: "%.1f", hoursSinceUpdate))"])
                } else {
                    Self.logger.info("Using cached schedules", metadata: ["hoursSinceUpdate": "\(String(format: "%.1f", hoursSinceUpdate))"])
                }
            } else {
                shouldRefreshSchedules = true
                Self.logger.info("No update timestamp found, refreshing schedules to set baseline")
            }
        } else {
            shouldRefreshSchedules = true
            if existingSchedule == nil {
                Self.logger.info("No schedules in cache, fetching from API")
            } else if existingTeams?.isEmpty ?? true {
                Self.logger.info("No teams in cache, fetching from API")
            }
        }

        if !shouldRefreshSchedules {
            Self.logger.info("Skipping schedule fetch — using cached data")
            return
        }

        Self.logger.info("Fetching schedules from API")
        var schedule: LiveScore = LiveScore(nba: nil, mlb: nil, soccer: nil, nfl: nil, nhl: nil, golf: nil, tennis: nil, racing: nil)
        var apiTeams: [Team] = []
        var allGames: [Game] = []

        for league in Leagues.allCases {
            do {
                if let response = try await SportsDBNetworking.getTeamInfoForLeague(app: context.application, DecodeType: Teams.self, league: league.rawValue) {
                    apiTeams.append(contentsOf: response.teams)
                }
                let response = try await SportsDBNetworking.getSchedule(app: context.application, DecodeType: LiveEvent.self, league: league.rawValue, singleYearSeason: league.usesSingleYearSeason)
                    .compactMap({$0})
                var events = response
                    .reduce(into: LiveEvent(events: [])) { partialResult, next in
                    partialResult.events += next.events
                }
                events.events.removeAll(where: {$0.strTimestamp == nil})
                events.events = events.events.map({
                    if $0.isoDate == nil {
                        var game = $0
                        game.isoDate = game.getDate()
                        return game
                    }
                    return $0
                })

                // Collect all games for team extraction
                allGames.append(contentsOf: events.events)

                switch league {
                case .nfl:
                    schedule.nfl = events
                    let newGames: [Game] = schedule.nfl?.events.map({ game in
                        if let date = game.getDate(), date.timeIntervalSinceNow > 0 {
                            // Only include essential fields - strSport/strLeague are computed from idLeague
                            // Deprecated fields removed: strPlayer, idPlayer, intEventScore, intEventScoreTotal, strEventTime, dateEvent, updated
                            let newGame = Game(idLiveScore: game.idLiveScore, idEvent: game.idEvent, strSport: nil, idLeague: game.idLeague, strLeague: nil, idHomeTeam: game.idHomeTeam, idAwayTeam: game.idAwayTeam, strHomeTeam: game.strHomeTeam, strAwayTeam: game.strAwayTeam, strHomeTeamBadge: game.strHomeTeamBadge, strAwayTeamBadge: game.strAwayTeamBadge, intHomeScore: nil, intAwayScore: nil, strPlayer: nil, idPlayer: nil, intEventScore: nil, intEventScoreTotal: nil, strStatus: game.strStatus, strProgress: game.strProgress, strEventTime: nil, dateEvent: nil, updated: nil, strTimestamp: game.strTimestamp, isoDate: game.getDate())
                            return newGame
                        }
                        return game
                    }) ?? []
                    schedule.nfl?.events = newGames
                    Self.logger.info("Schedule loaded", metadata: ["sport": "nfl", "events": "\(events.events.count)"])
                case .nhl:
                    schedule.nhl = events
                    Self.logger.info("Schedule loaded", metadata: ["sport": "nhl", "events": "\(events.events.count)"])
                case .nba:
                    schedule.nba = events
                    Self.logger.info("Schedule loaded", metadata: ["sport": "nba", "events": "\(events.events.count)"])
                case .mlb:
                    schedule.mlb = events
                    Self.logger.info("Schedule loaded", metadata: ["sport": "mlb", "events": "\(events.events.count)"])
                case .pga:
                    schedule.golf = events
                    Self.logger.info("Schedule loaded", metadata: ["sport": "golf", "events": "\(events.events.count)"])
                case .atp, .wta:
                    if schedule.tennis == nil {
                        schedule.tennis = events
                    } else {
                        schedule.tennis?.events += events.events
                    }
                    Self.logger.info("Schedule loaded", metadata: ["sport": "tennis", "league": "\(league.leagueName)", "events": "\(events.events.count)"])
                case .formula1:
                    // TheSportsDB has event names but no results — fetch from ESPN for richer data
                    let currentYear = Calendar.current.component(.year, from: Date())
                    var espnScoreboards: [Scoreboard] = []
                    for year in [currentYear - 1, currentYear] {
                        if let scoreboard = try? await Integrator.getESPNScoreboard(for: .formula1, context.application.client, dates: year) {
                            espnScoreboards.append(scoreboard)
                        }
                    }
                    // Fetch constructor map from the first scoreboard that has race data
                    var f1ConstructorMap: [String: String] = [:]
                    for scoreboard in espnScoreboards {
                        let map = await ESPNNetworking.getF1ConstructorMap(req: context.application.client, scoreboard: scoreboard)
                        if !map.isEmpty {
                            f1ConstructorMap = map
                            break
                        }
                    }
                    // Fetch timing/gap data for all completed sessions
                    let f1TimingMap = await ESPNNetworking.getF1TimingMap(req: context.application.client, scoreboards: espnScoreboards)
                    var espnRacingGames: [Game] = []
                    for scoreboard in espnScoreboards {
                        if let liveEvent = LiveEvent(events: scoreboard, league: .formula1, constructorMap: f1ConstructorMap, timingMap: f1TimingMap) {
                            espnRacingGames.append(contentsOf: liveEvent.events)
                        }
                    }
                    if !espnRacingGames.isEmpty {
                        schedule.racing = LiveEvent(events: espnRacingGames)
                    } else {
                        schedule.racing = events // fallback to TheSportsDB
                    }
                    Self.logger.info("Schedule loaded", metadata: ["sport": "racing", "events": "\(schedule.racing?.events.count ?? 0)", "constructors": "\(f1ConstructorMap.count)", "timingCompetitions": "\(f1TimingMap.count)"])
                default:
                    if schedule.soccer == nil {
                        schedule.soccer = events
                    } else {
                        schedule.soccer?.events += events.events
                    }
                }
            } catch {
                Self.logger.error("Failed to fetch league schedule", metadata: [
                    "league": "\(league)",
                    "leagueID": "\(league.rawValue)",
                    "error": "\(error)"
                ])
            }
        }

        // Extract teams from all games (multi-season coverage)
        let gameTeams = extractTeamsFromGames(allGames)
        let mergedTeams = mergeTeams(apiTeams: apiTeams, gameTeams: gameTeams)
        Self.logger.info("Teams extracted and merged", metadata: [
            "fromGames": "\(gameTeams.count)",
            "fromAPI": "\(apiTeams.count)",
            "totalMerged": "\(mergedTeams.count)",
            "totalGames": "\(allGames.count)"
        ])

        // Compare with existing cache — only write to Redis if data actually changed
        let scheduleChanged = (existingSchedule != schedule)
        let newGameCount = countGames(in: schedule)
        let oldGameCount = existingSchedule.map { countGames(in: $0) } ?? 0

        if scheduleChanged {
            try await context.application.redis.set(scheduleKey, toJSON: schedule)
            try await context.application.redis.set(RedisEndpoint.SportsDB.teams.getValue(isDebug: isDebug), toJSON: mergedTeams)
            Self.logger.info("Schedules updated — new data detected", metadata: [
                "oldGameCount": "\(oldGameCount)",
                "newGameCount": "\(newGameCount)"
            ])
        } else {
            Self.logger.info("Schedules unchanged — no new data from API", metadata: [
                "gameCount": "\(newGameCount)"
            ])
        }

        // Seed the final "Teams" key if it doesn't exist yet (before ESPNTeamFetchJob runs)
        let finalTeamsKey = RedisEndpoint.teams.getValue(isDebug: isDebug)
        let existingFinalTeams = try await context.application.redis.get(finalTeamsKey, asJSON: [Team].self)
        if existingFinalTeams == nil || existingFinalTeams?.isEmpty == true {
            try await context.application.redis.set(finalTeamsKey, toJSON: mergedTeams)
            Self.logger.info("Seeded Teams endpoint", metadata: ["teamsCount": "\(mergedTeams.count)"])
        }

        // Always update the timestamp so we know when we last checked
        try await context.application.redis.set(lastUpdateKey, toJSON: Date())
        Self.logger.info("Schedule check complete", metadata: ["dataChanged": "\(scheduleChanged)"])
    }
}

class DateFormatters {
    static let isoFormatter = ISO8601DateFormatter()
    static let dateFormatter = DateFormatter()
    static let backupISOFormatter = DateFormatter()
}
