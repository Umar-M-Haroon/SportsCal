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
    let gameType: Int?           // 1 preseason, 2 regular season, 3 playoffs
    let startTimeUTC: String?
    let period: Int?
    let periodDescriptor: NHLPeriodDescriptor?
    let clock: NHLClock?
    /// Skater strength while play is on. The four-digit code's shape is confirmed from
    /// api-web's play-by-play ("1451"); that the scoreboard carries it live is not yet.
    let situation: NHLSituation?
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

        let live = strStatus == "in"
        return Game(
            idEvent: id.map { "nhl-\($0)" },
            idLeague: "\(Leagues.nhl.rawValue)",
            strHomeTeam: homeName,
            strAwayTeam: awayName,
            intHomeScore: home.score.map(String.init),
            intAwayScore: away.score.map(String.init),
            strStatus: strStatus,
            strProgress: live ? progress : nil,
            strTimestamp: startTimeUTC,
            isCompleted: completed,
            isoDate: nil,
            situation: live ? liveSituation : nil
        )
    }

    private var periodNumber: Int? { periodDescriptor?.number ?? period }

    private var periodType: String {
        if let type = periodDescriptor?.periodType { return type }
        guard let number = periodNumber else { return "REG" }
        return number <= 3 ? "REG" : (gameType == 3 || number == 4 ? "OT" : "SO")
    }

    /// The period as ESPN's hockey status names it: "2nd", "OT", "2OT", "SO".
    private var periodName: String? {
        guard let number = periodNumber else { return nil }
        switch periodType {
        case "OT":
            let overtime = number - (periodDescriptor?.maxRegulationPeriods ?? 3)
            return overtime > 1 ? "\(overtime)OT" : "OT"
        case "SO":
            return "SO"
        default:
            switch number {
            case 1: return "1st"
            case 2: return "2nd"
            case 3: return "3rd"
            default: return "\(number)th"
            }
        }
    }

    /// ESPN's short status format — "12:34 - 2nd", "End of 2nd", "SO" — so a game
    /// doesn't flip between two formats as the sources trade wins.
    var progress: String? {
        guard let name = periodName else { return nil }
        if periodType == "SO" { return name }
        if clock?.inIntermission == true { return "End of \(name)" }
        guard let remaining = clock?.timeRemaining else { return name }
        return "\(Self.espnClock(remaining)) - \(name)"
    }

    /// "08:12" → "8:12", as ESPN writes the clock.
    static func espnClock(_ clock: String) -> String {
        guard clock.count > 4, clock.hasPrefix("0") else { return clock }
        return String(clock.dropFirst())
    }

    /// Period, clock and skater strength. Without a situation block (or at an
    /// intermission) the teams are at even strength: 3-on-3 in regular-season overtime.
    var liveSituation: GameSituation? {
        guard let number = periodNumber else { return nil }
        var situation = GameSituation(period: number, clock: clock?.secondsRemaining.map(Double.init))
        guard periodType != "SO" else { return situation }
        let evenSkaters = periodType == "OT" && gameType != 3 ? 3 : 5
        if clock?.inIntermission == true {
            situation.setEvenStrength(skaters: evenSkaters)
        } else if let code = self.situation?.situationCode, situation.applyNHLSituationCode(code) {
            if situation.powerPlaySide != nil {
                situation.powerPlayClock = self.situation?.secondsRemaining.map(Double.init)
                    ?? self.situation?.timeRemaining.flatMap(Self.seconds)
            }
        } else {
            situation.setEvenStrength(skaters: evenSkaters)
        }
        return situation
    }

    /// "01:42" → 102.
    static func seconds(_ clock: String) -> Double? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Double(parts[0] * 60 + parts[1])
    }
}

struct NHLPeriodDescriptor: Content {
    let number: Int?
    let periodType: String?      // REG / OT / SO
    let maxRegulationPeriods: Int?
}

struct NHLClock: Content {
    let timeRemaining: String?
    let secondsRemaining: Int?
    let running: Bool?
    let inIntermission: Bool?
}

struct NHLSituation: Content {
    /// Away goalie, away skaters, home skaters, home goalie: "1451" is a home power play.
    let situationCode: String?
    /// Time left on the power play.
    let timeRemaining: String?
    let secondsRemaining: Int?

    enum CodingKeys: String, CodingKey { case situationCode, timeRemaining, secondsRemaining }

    /// Unverified live shape, so nothing here may throw: a surprise must cost the power
    /// play, never the scoreboard.
    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        if let code = try? c?.decodeIfPresent(String.self, forKey: .situationCode) {
            situationCode = code
        } else if let code = try? c?.decodeIfPresent(Int.self, forKey: .situationCode) {
            // A bare number drops the leading zero of a pulled away goalie: 651 is "0651".
            situationCode = String(format: "%04d", code)
        } else {
            situationCode = nil
        }
        timeRemaining = (try? c?.decodeIfPresent(String.self, forKey: .timeRemaining)) ?? nil
        secondsRemaining = (try? c?.decodeIfPresent(Int.self, forKey: .secondsRemaining)) ?? nil
    }
}

struct NHLTeam: Content {
    let abbrev: String?
    let score: Int?
    let name: NHLLocalizedName?
}

struct NHLLocalizedName: Content {
    let `default`: String?
}
