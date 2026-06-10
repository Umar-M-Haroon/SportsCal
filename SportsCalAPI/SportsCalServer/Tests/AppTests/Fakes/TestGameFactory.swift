import Foundation
@testable import App
import SportsCalModel

/// Minimal Game builder for server-side tests. Only populates fields APNSJob /
/// ESPNFetchJob actually read. Mirrors `DebugGameFactory` on the client but
/// without the SwiftUI / ActivityKit dependencies.
enum TestGameFactory {
    static func make(
        idEvent: String,
        idLeague: String? = "4387",
        idHomeTeam: String? = nil,
        idAwayTeam: String? = nil,
        strHomeTeam: String,
        strAwayTeam: String,
        intHomeScore: String? = "0",
        intAwayScore: String? = "0",
        strStatus: String? = "pre",
        strProgress: String? = nil,
        strTimestamp: String? = nil,
        isoDate: Date? = Date(),
        tournamentName: String? = nil,
        round: String? = nil
    ) -> Game {
        Game(
            idLiveScore: nil,
            idEvent: idEvent,
            strSport: nil,
            idLeague: idLeague,
            strLeague: nil,
            idHomeTeam: idHomeTeam,
            idAwayTeam: idAwayTeam,
            strHomeTeam: strHomeTeam,
            strAwayTeam: strAwayTeam,
            strHomeTeamBadge: nil,
            strAwayTeamBadge: nil,
            intHomeScore: intHomeScore,
            intAwayScore: intAwayScore,
            strPlayer: nil,
            idPlayer: nil,
            intEventScore: nil,
            intEventScoreTotal: nil,
            strStatus: strStatus,
            strProgress: strProgress,
            strEventTime: nil,
            dateEvent: nil,
            updated: nil,
            strTimestamp: strTimestamp,
            lastPlay: nil,
            homeLinescores: nil,
            awayLinescores: nil,
            homeLeaders: nil,
            awayLeaders: nil,
            isCompleted: false,
            isoDate: isoDate,
            leaderboardEntries: nil,
            sessions: nil,
            venueName: nil,
            homeTeamColor: nil,
            awayTeamColor: nil,
            homeRecord: nil,
            awayRecord: nil,
            circuitInfo: nil,
            golfCourseInfo: nil,
            legDisplay: nil,
            aggregateScore: nil,
            homeSeed: nil,
            awaySeed: nil,
            tournamentName: tournamentName,
            round: round,
            homeInjuries: nil,
            awayInjuries: nil,
            raceTiming: nil,
            playoff: nil,
            lastPlayScoreboardID: nil
        )
    }

    /// Convenience: wrap a single NBA game in a LiveScore so jobs can consume it.
    static func liveScore(nba: [Game] = [], mlb: [Game] = [], nfl: [Game] = [], nhl: [Game] = [], soccer: [Game] = [], golf: [Game] = [], tennis: [Game] = [], racing: [Game] = []) -> LiveScore {
        LiveScore(
            nba: nba.isEmpty ? nil : LiveEvent(events: nba),
            mlb: mlb.isEmpty ? nil : LiveEvent(events: mlb),
            soccer: soccer.isEmpty ? nil : LiveEvent(events: soccer),
            nfl: nfl.isEmpty ? nil : LiveEvent(events: nfl),
            nhl: nhl.isEmpty ? nil : LiveEvent(events: nhl),
            golf: golf.isEmpty ? nil : LiveEvent(events: golf),
            tennis: tennis.isEmpty ? nil : LiveEvent(events: tennis),
            racing: racing.isEmpty ? nil : LiveEvent(events: racing)
        )
    }
}
