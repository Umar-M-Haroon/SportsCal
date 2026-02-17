//
//  Integrator.swift
//  
//
//  Created by Umar Haroon on 2/27/23.
//

import Foundation
import Vapor
import Redis
import SportsCalModel
import Logging

class Integrator {
    private static let logger = Logger(label: "com.sportscal.integrator")
    static func getAllLiveScores(_ client: some Client) async -> LiveScore {
        let leagues = Leagues.allCases

        func fetchSport(_ scoreType: SportsDBNetworking.LiveScoreType) async -> LiveEvent? {
            do {
                return try await SportsDBNetworking.callLiveScore(req: client, DecodeType: LiveEvent.self, scoreType: scoreType)
            } catch {
                logger.error("TheSportsDB live score failed for sport, continuing with others", metadata: [
                    "sport": "\(scoreType.rawValue)",
                    "error": "\(error)"
                ])
                return nil
            }
        }

        let basketball = await fetchSport(.basketball)
        var soccer = await fetchSport(.soccer)
        let filteredSoccer = soccer?.events.filter({ game in
            leagues.contains(where: {
                $0.rawValue == Int(game.idLeague ?? "")
            })
        }) ?? []
        soccer?.events = filteredSoccer
        let hockey = await fetchSport(.hockey)
        let mlb = await fetchSport(.mlb)
        let nfl = await fetchSport(.nfl)
        let golf = await fetchSport(.golf)
        let tennis = await fetchSport(.tennis)
        let racing = await fetchSport(.motorsport)
        var result = LiveScore(nba: basketball, mlb: mlb, soccer: soccer, nfl: nfl, nhl: hockey, golf: golf, tennis: tennis, racing: racing)
        result.removeOtherInfo()
        result.removeNonStarting()
        return result
    }
    
    private static func getESPNScores(_ client: some Client) async -> [SportType: Scoreboard] {
        return await withTaskGroup(of: (SportType, Scoreboard?).self) { group in
            var espnInfo: [SportType: Scoreboard] = [:]
            for sport in SportType.allCases.filter({$0.toLeague != nil}) {
                group.addTask {
                    do {
                        return (sport, try await getScoreboard(sport: sport, client: client))
                    } catch {
                        logger.error("ESPN fetch failed for sport, continuing with others", metadata: [
                            "sport": "\(sport)",
                            "error": "\(error)"
                        ])
                        return (sport, nil)
                    }
                }
            }
            for await (sport, scoreboard) in group {
                if let scoreboard {
                    espnInfo[sport] = scoreboard
                }
            }
            return espnInfo
        }
    }
    
    public static func getESPNScoreboard(for league: Leagues, _ client: some Client, dates: Int? = nil) async throws -> Scoreboard {
        try await ESPNNetworking.getScoreboard(req: client, DecodeType: Scoreboard.self, league: league, dates: dates)
    }
    
    static func getESPNLiveScore(_ client: some Client) async -> LiveScore {
        let espnScores = await getESPNScores(client)
        var events: [SportType: LiveEvent] = [:]
        for (sportType, scoreboard) in espnScores {
            if let league = sportType.toLeague {
                events[sportType] = LiveEvent(events: scoreboard, league: league)
            }
        }
        return LiveScore(nba: events[.basketball], mlb: events[.mlb], nfl: events[.nfl], nhl: events[.hockey], golf: events[.golf], tennis: events[.tennis], racing: events[.racing])
    }
    
    /// Checks if there are any live or upcoming games that warrant live score fetching.
    /// Returns true if games are currently in progress or starting within 30 minutes.
    static func hasLiveOrUpcomingGames(redis: RedisClient, isDebug: Bool) async -> Bool {
        let scheduleKey = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
        guard let schedule = try? await redis.get(scheduleKey, asJSON: LiveScore.self) else {
            logger.info("No schedule in Redis (first boot?) — assuming games may be happening")
            return true
        }

        let now = Date()
        let allGames = [schedule.nba, schedule.mlb, schedule.soccer, schedule.nfl, schedule.nhl, schedule.golf, schedule.tennis, schedule.racing]
            .compactMap { $0 }
            .flatMap { $0.events }

        return allGames.contains { game in
            guard let gameDate = game.isoDate ?? game.getDate() else { return false }
            let minutesFromNow = gameDate.timeIntervalSince(now) / 60
            // Game started within last 8 hours (could still be live)
            // OR game starting within next 30 minutes
            return minutesFromNow > -(8 * 60) && minutesFromNow <= 30
        }
    }

    static func getTeam(league: Leagues, client: some Client) async throws -> TeamResponse {
        try await ESPNNetworking.getTeam(req: client, DecodeType: TeamResponse.self, league: league)
    }

    static func getScoreboard(sport: SportType, client: Client) async throws -> Scoreboard {
        try await ESPNNetworking.getScoreboard(req: client, DecodeType: Scoreboard.self, scoreType: sport)
    }
}

extension SportType {
    public var toLeague: Leagues? {
        switch self {
        case .basketball:
            return .nba
        case .soccer:
            return nil
        case .hockey:
            return .nhl
        case .mlb:
            return .mlb
        case .nfl:
            return .nfl
        case .golf:
            return .pga
        case .tennis:
            return nil
        case .racing:
            return .formula1
        }
    }
}
