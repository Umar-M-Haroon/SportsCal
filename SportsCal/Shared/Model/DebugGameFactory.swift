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

    /// Creates a fake final (completed) team-sport game.
    static func createFakeFinalGame(sport: SportType = .basketball) -> Game {
        let uuid = UUID().uuidString.prefix(8)
        let eventID = "\(isFakeEventPrefix)\(uuid)"
        let leagueID = leagueID(for: sport)
        let date = Date.now.addingTimeInterval(-3 * 60 * 60)

        return Game(
            idLiveScore: eventID,
            idEvent: eventID,
            idLeague: "\(leagueID)",
            idHomeTeam: "debug-home-\(uuid)",
            idAwayTeam: "debug-away-\(uuid)",
            strHomeTeam: "Debug Lions",
            strAwayTeam: "Debug Tigers",
            intHomeScore: "112",
            intAwayScore: "98",
            strStatus: "post",
            strProgress: "Final",
            strTimestamp: ISO8601DateFormatter().string(from: date),
            isCompleted: true,
            isoDate: date
        )
    }

    /// Creates a fake playoff game with seeds and win-loss records.
    static func createFakePlayoffGame(sport: SportType = .basketball) -> Game {
        let base = createFakeLiveGame(sport: sport)
        return Game(
            idLiveScore: base.idLiveScore,
            idEvent: base.idEvent,
            idLeague: base.idLeague,
            idHomeTeam: base.idHomeTeam,
            idAwayTeam: base.idAwayTeam,
            strHomeTeam: base.strHomeTeam,
            strAwayTeam: base.strAwayTeam,
            intHomeScore: base.intHomeScore,
            intAwayScore: base.intAwayScore,
            strStatus: base.strStatus,
            strProgress: base.strProgress,
            strTimestamp: base.strTimestamp,
            isoDate: base.isoDate,
            homeRecord: "56-26",
            awayRecord: "51-31",
            homeSeed: 1,
            awaySeed: 4
        )
    }

    /// Creates a fake two-leg soccer aggregate game.
    static func createFakeTwoLegSoccer() -> Game {
        let base = createFakeLiveGame(sport: .soccer)
        return Game(
            idLiveScore: base.idLiveScore,
            idEvent: base.idEvent,
            idLeague: base.idLeague,
            idHomeTeam: base.idHomeTeam,
            idAwayTeam: base.idAwayTeam,
            strHomeTeam: "Real Madrid",
            strAwayTeam: "Manchester City",
            intHomeScore: "2",
            intAwayScore: "1",
            strStatus: "in",
            strProgress: "78'",
            strTimestamp: base.strTimestamp,
            isoDate: base.isoDate,
            legDisplay: "2nd Leg",
            aggregateScore: "Agg 4-3"
        )
    }

    /// Creates a fake upcoming F1 race.
    static func createFakeUpcomingRace() -> Game {
        let uuid = UUID().uuidString.prefix(8)
        let eventID = "\(isFakeEventPrefix)\(uuid)"
        let futureDate = Date.now.addingTimeInterval(3 * 24 * 60 * 60)

        return Game(
            idLiveScore: eventID,
            idEvent: eventID,
            idLeague: "\(Leagues.formula1.rawValue)",
            idHomeTeam: nil,
            idAwayTeam: nil,
            strHomeTeam: "Miami Grand Prix",
            strAwayTeam: "",
            strStatus: "NS",
            strTimestamp: ISO8601DateFormatter().string(from: futureDate),
            isoDate: futureDate,
            circuitInfo: F1CircuitInfo(
                circuitName: "Miami International Autodrome",
                locality: "Miami Gardens",
                country: "USA"
            )
        )
    }

    /// Creates a fake live F1 race with a top-3 leaderboard.
    static func createFakeLiveRace() -> Game {
        let uuid = UUID().uuidString.prefix(8)
        let eventID = "\(isFakeEventPrefix)\(uuid)"

        let leaderboard = """
        Max Verstappen|1|Leader|Red Bull
        Lando Norris|2|+2.341|McLaren
        Charles Leclerc|3|+5.872|Ferrari
        """

        return Game(
            idLiveScore: eventID,
            idEvent: eventID,
            idLeague: "\(Leagues.formula1.rawValue)",
            idHomeTeam: nil,
            idAwayTeam: nil,
            strHomeTeam: "Monaco Grand Prix",
            strAwayTeam: "",
            strStatus: "in",
            strProgress: "Lap 42/78",
            strTimestamp: ISO8601DateFormatter().string(from: .now),
            lastPlay: leaderboard,
            isoDate: .now,
            circuitInfo: F1CircuitInfo(
                circuitName: "Circuit de Monaco",
                locality: "Monte Carlo",
                country: "Monaco"
            )
        )
    }

    /// Creates a fake upcoming tournament (golf / tennis).
    static func createFakeUpcomingTournament(sport: SportType = .golf) -> Game {
        let uuid = UUID().uuidString.prefix(8)
        let eventID = "\(isFakeEventPrefix)\(uuid)"
        let leagueID = leagueID(for: sport)
        let futureDate = Date.now.addingTimeInterval(2 * 24 * 60 * 60)

        let name = sport == .golf ? "The Players Championship" : "Indian Wells Masters"

        return Game(
            idLiveScore: eventID,
            idEvent: eventID,
            idLeague: "\(leagueID)",
            idHomeTeam: nil,
            idAwayTeam: nil,
            strHomeTeam: name,
            strAwayTeam: "",
            strStatus: "NS",
            strTimestamp: ISO8601DateFormatter().string(from: futureDate),
            isoDate: futureDate,
            tournamentName: name
        )
    }

    /// Creates a fake live tournament (golf / tennis) with a top-5 leaderboard.
    static func createFakeLiveTournament(sport: SportType = .golf, isMajor: Bool = false) -> Game {
        let uuid = UUID().uuidString.prefix(8)
        let eventID = "\(isFakeEventPrefix)\(uuid)"
        let leagueID = leagueID(for: sport)

        let golfBoard = """
        Scottie Scheffler|-14
        Rory McIlroy|-12
        Xander Schauffele|-10
        Collin Morikawa|-9
        Jon Rahm|-8
        """
        let tennisBoard = """
        Carlos Alcaraz|6-4, 3-2
        Jannik Sinner|4-6, 2-3
        """
        let board = sport == .golf ? golfBoard : tennisBoard
        let leader = sport == .golf ? "Scottie Scheffler" : "Carlos Alcaraz"
        let tournamentName: String = {
            if sport == .tennis { return "US Open" }
            return isMajor ? "The Masters" : "The Players Championship"
        }()

        return Game(
            idLiveScore: eventID,
            idEvent: eventID,
            idLeague: "\(leagueID)",
            idHomeTeam: nil,
            idAwayTeam: nil,
            strHomeTeam: tournamentName,
            strAwayTeam: leader,
            strStatus: "in",
            strProgress: sport == .golf ? "Round 3" : "Semifinal",
            strTimestamp: ISO8601DateFormatter().string(from: .now),
            lastPlay: board,
            isoDate: .now,
            tournamentName: tournamentName
        )
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
