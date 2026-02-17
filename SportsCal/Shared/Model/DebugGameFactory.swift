//
//  DebugGameFactory.swift
//  SportsCal (iOS)
//
//  Created for debug/testing of auto-follow → live activity flow.
//

import Foundation
import SportsCalModel

enum DebugGameFactory {
    static let isFakeEventPrefix = "debug-fake-"

    /// Creates a fake upcoming game scheduled N seconds from now.
    static func createFakeUpcomingGame(sport: SportType = .basketball, secondsFromNow: TimeInterval = 10) -> Game {
        let uuid = UUID().uuidString.prefix(8)
        let eventID = "\(isFakeEventPrefix)\(uuid)"
        let leagueID = leagueID(for: sport)
        let futureDate = Date.now.addingTimeInterval(secondsFromNow)

        return Game(
            idLiveScore: eventID,
            idEvent: eventID,
            idLeague: "\(leagueID)",
            idHomeTeam: "debug-home-\(uuid)",
            idAwayTeam: "debug-away-\(uuid)",
            strHomeTeam: "Debug Lions",
            strAwayTeam: "Debug Tigers",
            intHomeScore: "0",
            intAwayScore: "0",
            strStatus: "NS",
            strProgress: nil,
            strTimestamp: ISO8601DateFormatter().string(from: futureDate),
            isoDate: futureDate
        )
    }

    /// Creates a fake game that is already live with scores.
    static func createFakeLiveGame(sport: SportType = .basketball) -> Game {
        let uuid = UUID().uuidString.prefix(8)
        let eventID = "\(isFakeEventPrefix)\(uuid)"
        let leagueID = leagueID(for: sport)

        return Game(
            idLiveScore: eventID,
            idEvent: eventID,
            idLeague: "\(leagueID)",
            idHomeTeam: "debug-home-\(uuid)",
            idAwayTeam: "debug-away-\(uuid)",
            strHomeTeam: "Debug Lions",
            strAwayTeam: "Debug Tigers",
            intHomeScore: "42",
            intAwayScore: "38",
            strStatus: "in",
            strProgress: "6:30 - 2nd",
            strTimestamp: ISO8601DateFormatter().string(from: .now),
            isoDate: .now
        )
    }

    /// Creates synthetic Team objects for fake games.
    static func fakeTeams(for game: Game) -> (home: Team, away: Team) {
        let home = Team(
            idTeam: game.idHomeTeam,
            strTeam: game.strHomeTeam,
            strTeamShort: "DBG",
            strAlternate: "Debug Lions",
            strTeamBadge: nil
        )
        let away = Team(
            idTeam: game.idAwayTeam,
            strTeam: game.strAwayTeam,
            strTeamShort: "DBG",
            strAlternate: "Debug Tigers",
            strTeamBadge: nil
        )
        return (home, away)
    }

    /// Transitions a fake upcoming game to live status.
    static func transitionToLive(_ game: Game) -> Game {
        Game(
            idLiveScore: game.idLiveScore,
            idEvent: game.idEvent,
            idLeague: game.idLeague,
            idHomeTeam: game.idHomeTeam,
            idAwayTeam: game.idAwayTeam,
            strHomeTeam: game.strHomeTeam,
            strAwayTeam: game.strAwayTeam,
            intHomeScore: "12",
            intAwayScore: "9",
            strStatus: "in",
            strProgress: "4:20 - 1st",
            strTimestamp: game.strTimestamp,
            isoDate: game.isoDate
        )
    }

    /// Returns the default league ID for a given sport.
    private static func leagueID(for sport: SportType) -> Int {
        switch sport {
        case .basketball: return Leagues.nba.rawValue
        case .soccer:     return Leagues.English_Premier_League.rawValue
        case .hockey:     return Leagues.nhl.rawValue
        case .mlb:        return Leagues.mlb.rawValue
        case .nfl:        return Leagues.nfl.rawValue
        case .golf:       return Leagues.pga.rawValue
        case .tennis:     return Leagues.atp.rawValue
        case .racing:     return Leagues.formula1.rawValue
        }
    }
}
