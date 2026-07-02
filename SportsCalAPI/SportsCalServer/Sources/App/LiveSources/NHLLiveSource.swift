//
//  NHLLiveSource.swift
//
//  NHL live scores from the official Web API (api-web.nhle.com) — free, no auth.
//  `scoreboard/now` returns all current games (full team names, scores, clock) in one
//  call; the ticker overlays by team-name + day. Use `scoreboard/now` (not `score/now`,
//  which 307-redirects). Structure verified against real playoff data; enable + confirm
//  during the season. Pin to `v1` (NHL has rev'd this API before).
//

import Foundation
import Vapor
import SportsCalModel

struct NHLLiveSource: LiveSource {
    let name = "nhl-apiweb"
    let sport: SportType = .hockey
    let matchStrategy: LiveMerge.MatchStrategy = .teamsAndDay

    private static let logger = Logger(label: "com.sportscal.live-source.nhl")

    func fetchLive(leagues: Set<Leagues>, app: Application) async throws -> [Game] {
        guard leagues.contains(.nhl) else { return [] }

        let response = try await app.client.get(URI(string: "https://api-web.nhle.com/v1/scoreboard/now")) { req in
            req.headers.replaceOrAdd(name: .accept, value: "application/json")
        }
        let decoded = try response.content.decode(NHLScoreboardResponse.self)

        let games = decoded.gamesByDate.flatMap { $0.games }.compactMap { $0.toGame() }
        Self.logger.info("NHL live fetched", metadata: ["liveOrFinal": "\(games.count)"])
        return games
    }
}

// MARK: - Decode (only the fields we consume)

struct NHLScoreboardResponse: Content {
    let gamesByDate: [NHLDate]
}

struct NHLDate: Content {
    let games: [NHLGame]
}

struct NHLGame: Content {
    let id: Int?
    let gameState: String?       // FUT/PRE/LIVE/CRIT/FINAL/OFF
    let startTimeUTC: String?
    let period: Int?
    let clock: NHLClock?
    let homeTeam: NHLTeam?
    let awayTeam: NHLTeam?

    func toGame() -> Game? {
        guard let home = homeTeam, let away = awayTeam,
              let homeName = home.name?.default, let awayName = away.name?.default,
              let state = gameState else { return nil }

        let strStatus: String
        let completed: Bool
        switch state {
        case "LIVE", "CRIT":  strStatus = "in";   completed = false
        case "FINAL", "OFF":  strStatus = "post"; completed = true
        default: return nil   // FUT / PRE → not a live update
        }

        var progress: String? = nil
        if strStatus == "in" {
            if clock?.inIntermission == true {
                progress = period.map { "INT P\($0)" }
            } else if let p = period, let rem = clock?.timeRemaining {
                progress = "P\(p) \(rem)"
            }
        }

        return Game(
            idEvent: id.map { "nhl-\($0)" },
            idLeague: "\(Leagues.nhl.rawValue)",
            strHomeTeam: homeName,
            strAwayTeam: awayName,
            intHomeScore: home.score.map(String.init),
            intAwayScore: away.score.map(String.init),
            strStatus: strStatus,
            strProgress: progress,
            strTimestamp: startTimeUTC,
            isCompleted: completed,
            isoDate: nil
        )
    }
}

struct NHLClock: Content {
    let timeRemaining: String?
    let running: Bool?
    let inIntermission: Bool?
}

struct NHLTeam: Content {
    let abbrev: String?
    let score: Int?
    let name: NHLLocalizedName?
}

struct NHLLocalizedName: Content {
    let `default`: String?
}
