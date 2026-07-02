//
//  NBALiveSource.swift
//
//  NBA live scores from cdn.nba.com liveData (free, no auth). One scoreboard call
//  returns all current games; the ticker overlays by team-name + day.
//
//  ⚠️ UNVERIFIED + BLOCKED FROM DEV: cdn.nba.com returns Akamai "Access Denied" to our
//  dev IP, so the decode below follows the documented nba_api shape but has NOT been
//  validated against a live response, and prod reachability is unconfirmed. OFF by
//  default (LIVE_SOURCE_NBA unset). Before enabling: confirm the prod server can reach
//  cdn.nba.com and that this decode matches a live payload. Decode is defensive — a
//  shape mismatch yields no games and degrades to the ESPN path rather than crashing.
//

import Foundation
import Vapor
import SportsCalModel

struct NBALiveSource: LiveSource {
    let name = "nba-cdn"
    let sport: SportType = .basketball
    let matchStrategy: LiveMerge.MatchStrategy = .teamsAndDay

    private static let logger = Logger(label: "com.sportscal.live-source.nba")

    func fetchLive(leagues: Set<Leagues>, app: Application) async throws -> [Game] {
        guard leagues.contains(.nba) else { return [] }

        let url = "https://cdn.nba.com/static/json/liveData/scoreboard/todaysScoreboard_00.json"
        let response = try await app.client.get(URI(string: url)) { req in
            req.headers.replaceOrAdd(name: .accept, value: "application/json")
        }
        let decoded = try response.content.decode(NBAScoreboardResponse.self)

        let games = decoded.scoreboard.games.compactMap { $0.toGame() }
        Self.logger.info("NBA live fetched", metadata: ["liveOrFinal": "\(games.count)"])
        return games
    }
}

// MARK: - Decode (only the fields we consume; documented nba_api shape, unverified)

struct NBAScoreboardResponse: Content {
    let scoreboard: NBAScoreboard
}

struct NBAScoreboard: Content {
    let games: [NBAGame]
}

struct NBAGame: Content {
    let gameId: String?
    let gameStatus: Int?         // 1 upcoming, 2 live, 3 final
    let gameTimeUTC: String?
    let period: Int?
    let gameClock: String?
    let homeTeam: NBATeam?
    let awayTeam: NBATeam?

    func toGame() -> Game? {
        guard let home = homeTeam, let away = awayTeam,
              let homeName = home.fullName, let awayName = away.fullName,
              let status = gameStatus else { return nil }

        let strStatus: String
        let completed: Bool
        switch status {
        case 2: strStatus = "in";   completed = false
        case 3: strStatus = "post"; completed = true
        default: return nil   // 1 = upcoming
        }

        let progress: String? = (strStatus == "in") ? period.map { "Q\($0)" } : nil

        return Game(
            idEvent: gameId.map { "nba-\($0)" },
            idLeague: "\(Leagues.nba.rawValue)",
            strHomeTeam: homeName,
            strAwayTeam: awayName,
            intHomeScore: home.score.map(String.init),
            intAwayScore: away.score.map(String.init),
            strStatus: strStatus,
            strProgress: progress,
            strTimestamp: gameTimeUTC,
            isCompleted: completed,
            isoDate: nil
        )
    }
}

struct NBATeam: Content {
    let teamCity: String?
    let teamName: String?
    let score: Int?

    /// "Los Angeles Lakers" — matches ESPN's displayName.
    var fullName: String? {
        switch (teamCity, teamName) {
        case let (city?, name?): return "\(city) \(name)"
        case (nil, let name?):   return name
        default:                 return nil
        }
    }
}
