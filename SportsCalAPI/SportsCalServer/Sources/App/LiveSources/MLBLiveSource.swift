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
    /// 1 or 2 on a doubleheader day.
    let gameNumber: Int?
    /// "N" for a single game, "Y" (traditional) or "S" (split) for a doubleheader.
    let doubleHeader: String?

    /// What ESPN would say for this state, so the two sources racing for a game don't
    /// flip its status between formats: "Bot 9th", "Mid 3rd", "Rain Delay", "Final".
    struct ESPNStyleStatus: Equatable {
        var strStatus: String
        var progress: String?
        var completed: Bool
    }

    static func espnStyleStatus(abstract: String?, detailed: String?, inning: Int?, inningState: String?, inningOrdinal: String?) -> ESPNStyleStatus? {
        let detail = (detailed ?? "").lowercased()
        switch abstract {
        case "Live":
            // Delays stay in progress (ESPN keeps them "in"), but read as the delay,
            // not as an inning.
            if detail.hasPrefix("delayed") || detail.hasPrefix("delay") {
                return ESPNStyleStatus(strStatus: "in", progress: detail.contains("rain") ? "Rain Delay" : "Delayed", completed: false)
            }
            if detail.hasPrefix("suspended") {
                return ESPNStyleStatus(strStatus: "post", progress: "Suspended", completed: false)
            }
            return ESPNStyleStatus(strStatus: "in", progress: inningText(inning: inning, state: inningState, ordinal: inningOrdinal), completed: false)
        case "Final":
            // A suspended game is over for today but not finished: it resumes on
            // another day, so it must not be archived as a final.
            if detail.hasPrefix("suspended") {
                return ESPNStyleStatus(strStatus: "post", progress: "Suspended", completed: false)
            }
            if detail.hasPrefix("postponed") || detail.hasPrefix("cancelled") || detail.hasPrefix("canceled") {
                return nil
            }
            return ESPNStyleStatus(strStatus: "post", progress: nil, completed: true)
        default:
            return nil   // Preview / other → not a live update
        }
    }

    /// "Top 9th" / "Bot 9th" / "Mid 9th" / "End 9th", ESPN's shortDetail format.
    static func inningText(inning: Int?, state: String?, ordinal: String?) -> String? {
        guard let inning else { return nil }
        let number = ordinal ?? Self.ordinal(inning)
        let half: String
        switch state?.lowercased() {
        case "top": half = "Top"
        case "bottom": half = "Bot"
        case "middle": half = "Mid"
        case "end": half = "End"
        default: return number
        }
        return "\(half) \(number)"
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    func toGame() -> Game? {
        guard let teams = teams,
              let homeName = teams.home?.team?.name,
              let awayName = teams.away?.team?.name,
              let state = Self.espnStyleStatus(
                abstract: status?.abstractGameState,
                detailed: status?.detailedState,
                inning: linescore?.currentInning,
                inningState: linescore?.inningState,
                inningOrdinal: linescore?.currentInningOrdinal
              ) else { return nil }
        let strStatus = state.strStatus
        let isDoubleheader = doubleHeader == "Y" || doubleHeader == "S"

        return Game(
            idEvent: gamePk.map { "mlb-\($0)" },
            idLeague: "\(Leagues.mlb.rawValue)",
            strHomeTeam: homeName,
            strAwayTeam: awayName,
            intHomeScore: teams.home?.score.map(String.init),
            intAwayScore: teams.away?.score.map(String.init),
            strStatus: strStatus,
            strProgress: state.progress,
            strTimestamp: gameDate,
            isCompleted: state.completed,
            isoDate: nil,
            // No count or runners through a delay.
            situation: strStatus == "in" && state.progress?.contains("Delay") != true ? linescore?.situation : nil,
            // Only to tell a doubleheader's games apart in the merge; a partial
            // source's extras never replace ESPN's.
            scoreboardExtras: isDoubleheader ? gameNumber.map { ScoreboardExtras(doubleheaderGame: $0) } : nil
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
    /// "9th"
    let currentInningOrdinal: String?
    let inningState: String?
    let balls: Int?
    let strikes: Int?
    let outs: Int?
    let offense: MLBOffense?
    let defense: MLBDefense?

    /// Count, outs, runners and matchup — fresher than ESPN's, which only arrives on the
    /// slow pipeline. statsapi publishes no win probability; ESPN's stays until replaced.
    var situation: GameSituation? {
        guard let currentInning else { return nil }
        return GameSituation(
            period: currentInning,
            inningHalf: inningState.flatMap { GameSituation.inningHalf(from: $0) },
            balls: balls,
            strikes: strikes,
            outs: outs,
            onFirst: offense?.first != nil,
            onSecond: offense?.second != nil,
            onThird: offense?.third != nil,
            batter: offense?.batter?.shortName,
            pitcher: defense?.pitcher?.shortName
        )
    }
}

struct MLBOffense: Content {
    let batter: MLBPerson?
    let first: MLBPerson?
    let second: MLBPerson?
    let third: MLBPerson?
}

struct MLBDefense: Content {
    let pitcher: MLBPerson?
}

struct MLBPerson: Content {
    let id: Int?
    let fullName: String?

    /// "Carson Benge" → "C. Benge", matching ESPN's short names.
    var shortName: String? {
        guard let fullName else { return nil }
        let parts = fullName.split(separator: " ")
        guard parts.count >= 2, let initial = parts.first?.first else { return fullName }
        return "\(initial). \(parts.dropFirst().joined(separator: " "))"
    }
}
