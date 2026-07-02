//
//  MLBLiveSource.swift
//
//  MLB live scores from the official Stats API (statsapi.mlb.com) — free, no auth,
//  the source of record and fresher than ESPN. One schedule call with the linescore
//  hydrate returns every game's score + inning in a single request; the ticker
//  overlays them onto the snapshot by team-name + day (gamePk lives in a different
//  namespace than ESPN's idEvent).
//
//  Note: statsapi terms permit individual, non-commercial use only — see the plan's
//  legal caveat. Decode is defensive; failures degrade to the ESPN path.
//

import Foundation
import Vapor
import SportsCalModel

struct MLBLiveSource: LiveSource {
    let name = "mlb-statsapi"
    let sport: SportType = .mlb
    let matchStrategy: LiveMerge.MatchStrategy = .teamsAndDay

    private static let logger = Logger(label: "com.sportscal.live-source.mlb")

    func fetchLive(leagues: Set<Leagues>, app: Application) async throws -> [Game] {
        guard leagues.contains(.mlb) else { return [] }

        // 3-day UTC window covers late games that cross the date boundary.
        let (start, end) = Self.dateWindow()
        let url = "https://statsapi.mlb.com/api/v1/schedule?sportId=1&startDate=\(start)&endDate=\(end)&hydrate=linescore"
        let response = try await app.client.get(URI(string: url)) { req in
            req.headers.replaceOrAdd(name: .accept, value: "application/json")
        }
        let decoded = try response.content.decode(MLBScheduleResponse.self)

        let games = decoded.dates.flatMap { $0.games }.compactMap { $0.toGame() }
        Self.logger.info("MLB live fetched", metadata: [
            "window": "\(start)…\(end)",
            "liveOrFinal": "\(games.count)"
        ])
        return games
    }

    static func dateWindow(now: Date = Date()) -> (String, String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
        return (df.string(from: yesterday), df.string(from: tomorrow))
    }
}

// MARK: - Decode (only the fields we consume)

struct MLBScheduleResponse: Content {
    let dates: [MLBDate]
}

struct MLBDate: Content {
    let games: [MLBGame]
}

struct MLBGame: Content {
    let gamePk: Int?
    let gameDate: String?
    let status: MLBStatus?
    let teams: MLBTeams?
    let linescore: MLBLinescore?

    func toGame() -> Game? {
        guard let teams = teams,
              let homeName = teams.home?.team?.name,
              let awayName = teams.away?.team?.name,
              let state = status?.abstractGameState else { return nil }

        let strStatus: String
        let completed: Bool
        switch state {
        case "Live":  strStatus = "in";   completed = false
        case "Final": strStatus = "post"; completed = true
        default: return nil   // Preview / other → not a live update
        }

        // "Bot 9" / "Top 3" while live.
        var progress: String? = nil
        if strStatus == "in", let inning = linescore?.currentInning {
            let half = (linescore?.inningState?.prefix(3)).map(String.init) ?? ""
            progress = half.isEmpty ? "\(inning)" : "\(half) \(inning)"
        }

        return Game(
            idEvent: gamePk.map { "mlb-\($0)" },
            idLeague: "\(Leagues.mlb.rawValue)",
            strHomeTeam: homeName,
            strAwayTeam: awayName,
            intHomeScore: teams.home?.score.map(String.init),
            intAwayScore: teams.away?.score.map(String.init),
            strStatus: strStatus,
            strProgress: progress,
            strTimestamp: gameDate,
            isCompleted: completed,
            isoDate: nil
        )
    }
}

struct MLBStatus: Content {
    let abstractGameState: String?
    let detailedState: String?
}

struct MLBTeams: Content {
    let home: MLBTeamSide?
    let away: MLBTeamSide?
}

struct MLBTeamSide: Content {
    let score: Int?
    let team: MLBTeamRef?
}

struct MLBTeamRef: Content {
    let name: String?
}

struct MLBLinescore: Content {
    let currentInning: Int?
    let inningState: String?
}
