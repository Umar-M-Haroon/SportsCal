//
//  FIFALiveSource.swift
//
//  World Cup live scores from FIFA's official match-center backend
//  (api.fifa.com/api/v3) — free, no auth, the authoritative source of record and
//  fresher than ESPN's `fifa.world` scoreboard. One calendar call returns all
//  matches with live scores; the ticker overlays them onto the snapshot by
//  team-name + day (FIFA's IdMatch lives in a different namespace than ESPN's).
//
//  Undocumented website backend: structure can change without notice, so decode is
//  defensive (only the fields we need) and failures degrade to the ESPN path.
//

import Foundation
import Vapor
import SportsCalModel

struct FIFALiveSource: LiveSource {
    let name = "fifa"
    let sport: SportType = .soccer
    let matchStrategy: LiveMerge.MatchStrategy = .teamsAndDay

    private static let logger = Logger(label: "com.sportscal.live-source.fifa")
    private static let base = "https://api.fifa.com/api/v3"
    /// FIFA World Cup competition id is stable; the 2026 season id is overridable in case
    /// FIFA re-keys it. Verified live: idCompetition=17, idSeason=285023.
    private static let idCompetition = "17"

    private static var idSeason: String {
        Environment.get("FIFA_WC_SEASON_ID") ?? "285023"
    }

    func fetchLive(leagues: Set<Leagues>, app: Application) async throws -> [Game] {
        // We only serve the World Cup; ignore any other leagues routed here.
        guard leagues.contains(.FIFA_World_Cup) else { return [] }

        let url = "\(Self.base)/calendar/matches?idCompetition=\(Self.idCompetition)&idSeason=\(Self.idSeason)&count=104"
        let response = try await app.client.get(URI(string: url)) { req in
            req.headers.replaceOrAdd(name: .accept, value: "application/json")
        }
        let decoded = try response.content.decode(FIFACalendarResponse.self)

        let games = decoded.Results.compactMap { $0.toGame() }
        Self.logger.info("FIFA live fetched", metadata: [
            "matches": "\(decoded.Results.count)",
            "liveOrFinal": "\(games.count)"
        ])
        return games
    }
}

// MARK: - Decode (only the fields we consume)

/// Top-level calendar payload. Extra keys are ignored by Codable.
struct FIFACalendarResponse: Content {
    let Results: [FIFAMatch]
}

struct FIFAMatch: Content {
    let IdMatch: String?
    let Date: String?
    /// 0 = finished, 1 = upcoming, 3 = live (observed live). Others ignored.
    let MatchStatus: Int?
    let MatchTime: String?
    let Home: FIFACompetitor?
    let Away: FIFACompetitor?

    /// Maps a FIFA match to a fast-overlay `Game`. Only live (3) and just-finished (0)
    /// matches produce a game — those are the states that can update an in-progress
    /// snapshot game. Upcoming (1) and unknown statuses are dropped.
    func toGame() -> Game? {
        guard let home = Home, let away = Away,
              let homeName = home.name, let awayName = away.name,
              let status = MatchStatus else { return nil }

        let strStatus: String
        let completed: Bool
        switch status {
        case 3: strStatus = "in"; completed = false
        case 0: strStatus = "post"; completed = true
        default: return nil
        }

        let progress = (MatchTime?.isEmpty == false) ? MatchTime : nil

        return Game(
            idEvent: IdMatch.map { "fifa-\($0)" },
            idLeague: "\(Leagues.FIFA_World_Cup.rawValue)",
            strHomeTeam: homeName,
            strAwayTeam: awayName,
            intHomeScore: home.Score.map(String.init),
            intAwayScore: away.Score.map(String.init),
            strStatus: strStatus,
            strProgress: progress,
            strTimestamp: Date,
            isCompleted: completed,
            isoDate: nil
        )
    }
}

struct FIFACompetitor: Content {
    let Score: Int?
    let Abbreviation: String?
    let TeamName: [FIFALocalized]?

    /// First localized team name (en-GB).
    var name: String? { TeamName?.first?.Description }
}

struct FIFALocalized: Content {
    let Locale: String?
    let Description: String?
}
