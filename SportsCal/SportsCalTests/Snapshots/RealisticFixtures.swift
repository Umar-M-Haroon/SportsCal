//
//  RealisticFixtures.swift
//  SportsCalTests
//
//  High-fidelity game-day fixtures for hero screenshots.
//  Real teams, real scores, real leaders, real tournament fields.
//

import Foundation
import SwiftUI
@testable import Scoreline
import SportsCalModel

enum RealisticFixtures {

    // MARK: - Time anchors

    /// Game day anchor — 2:30 PM today in the simulator's timezone. Using a dynamic
    /// anchor keeps DayPage's default selected date (startOfDay(today)) aligned with the games.
    private static let anchor: Date = {
        Calendar.current.date(
            bySettingHour: 14, minute: 30, second: 0,
            of: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
    }()

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    // MARK: - Team helpers

    private static func team(id: String, name: String, short: String, league: String) -> Team {
        Team(
            idTeam: "\(league)-\(id)",
            strTeam: name,
            strTeamShort: short,
            strAlternate: short,
            strTeamBadge: nil  // Nil → clean initials-in-circle fallback (no loading spinners)
        )
    }

    /// Pre-warm URL cache so NukeUI finds badges immediately when the view mounts.
    static func prewarmBadges() async {
        let urls = allTeams.compactMap { $0.strTeamBadge }.compactMap { URL(string: $0) }
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    _ = try? await URLSession.shared.data(from: url)
                }
            }
        }
    }

    // MARK: - NBA: Celtics vs Lakers (live, 4th quarter)

    static let nbaHomeTeam = team(id: "bos", name: "Boston Celtics", short: "BOS", league: "nba")
    static let nbaAwayTeam = team(id: "lal", name: "Los Angeles Lakers", short: "LAL", league: "nba")

    static var nbaLive: Game {
        Game(
            idLiveScore: "nba-bos-lal-001",
            idEvent: "nba-bos-lal-001",
            idLeague: "\(Leagues.nba.rawValue)",
            idHomeTeam: nbaHomeTeam.idTeam,
            idAwayTeam: nbaAwayTeam.idTeam,
            strHomeTeam: nbaHomeTeam.strTeam ?? "",
            strAwayTeam: nbaAwayTeam.strTeam ?? "",
            strHomeTeamBadge: nbaHomeTeam.strTeamBadge,
            strAwayTeamBadge: nbaAwayTeam.strTeamBadge,
            intHomeScore: "104",
            intAwayScore: "98",
            strStatus: "in",
            strProgress: "4:22 - 4th",
            strTimestamp: iso(anchor),
            homeLinescores: [28, 24, 26, 26],
            awayLinescores: [22, 28, 22, 26],
            homeLeaders: [
                GameLeader(category: "points", categoryDisplay: "PTS", playerName: "Jayson Tatum", displayValue: "28 PTS, 9 REB"),
                GameLeader(category: "rebounds", categoryDisplay: "REB", playerName: "Kristaps Porziņģis", displayValue: "14 REB, 3 BLK"),
                GameLeader(category: "assists", categoryDisplay: "AST", playerName: "Jrue Holiday", displayValue: "9 AST, 11 PTS")
            ],
            awayLeaders: [
                GameLeader(category: "points", categoryDisplay: "PTS", playerName: "LeBron James", displayValue: "24 PTS, 8 AST"),
                GameLeader(category: "rebounds", categoryDisplay: "REB", playerName: "Anthony Davis", displayValue: "12 REB, 20 PTS"),
                GameLeader(category: "assists", categoryDisplay: "AST", playerName: "Austin Reaves", displayValue: "7 AST, 15 PTS")
            ],
            isoDate: anchor,
            venueName: "TD Garden",
            homeTeamColor: "007A33",
            awayTeamColor: "552583",
            homeRecord: "52-18",
            awayRecord: "38-32"
        )
    }

    // MARK: - NFL: Chiefs vs 49ers (playoff, final)

    static let nflHomeTeam = team(id: "kc", name: "Kansas City Chiefs", short: "KC", league: "nfl")
    static let nflAwayTeam = team(id: "sf", name: "San Francisco 49ers", short: "SF", league: "nfl")

    static var nflFinal: Game {
        Game(
            idLiveScore: "nfl-kc-sf-001",
            idEvent: "nfl-kc-sf-001",
            idLeague: "\(Leagues.nfl.rawValue)",
            idHomeTeam: nflHomeTeam.idTeam,
            idAwayTeam: nflAwayTeam.idTeam,
            strHomeTeam: nflHomeTeam.strTeam ?? "",
            strAwayTeam: nflAwayTeam.strTeam ?? "",
            strHomeTeamBadge: nflHomeTeam.strTeamBadge,
            strAwayTeamBadge: nflAwayTeam.strTeamBadge,
            intHomeScore: "25",
            intAwayScore: "22",
            strStatus: "post",
            strProgress: "Final / OT",
            strTimestamp: iso(anchor.addingTimeInterval(-60 * 60)),
            homeLinescores: [0, 10, 3, 6, 6],
            awayLinescores: [7, 3, 0, 9, 3],
            homeLeaders: [
                GameLeader(category: "passing", categoryDisplay: "PASS", playerName: "Patrick Mahomes", displayValue: "333 YDS, 2 TD"),
                GameLeader(category: "rushing", categoryDisplay: "RUSH", playerName: "Isiah Pacheco", displayValue: "64 YDS, TD"),
                GameLeader(category: "receiving", categoryDisplay: "REC", playerName: "Travis Kelce", displayValue: "9 REC, 93 YDS")
            ],
            awayLeaders: [
                GameLeader(category: "passing", categoryDisplay: "PASS", playerName: "Brock Purdy", displayValue: "255 YDS, TD"),
                GameLeader(category: "rushing", categoryDisplay: "RUSH", playerName: "Christian McCaffrey", displayValue: "80 YDS, TD"),
                GameLeader(category: "receiving", categoryDisplay: "REC", playerName: "Brandon Aiyuk", displayValue: "3 REC, 49 YDS")
            ],
            isCompleted: true,
            isoDate: anchor.addingTimeInterval(-60 * 60),
            venueName: "Allegiant Stadium",
            homeTeamColor: "E31837",
            awayTeamColor: "AA0000",
            homeRecord: "14-3",
            awayRecord: "13-4",
            homeSeed: 1,
            awaySeed: 2
        )
    }

    // MARK: - MLB: Dodgers vs Yankees (live, top 7th)

    static let mlbHomeTeam = team(id: "lad", name: "Los Angeles Dodgers", short: "LAD", league: "mlb")
    static let mlbAwayTeam = team(id: "nyy", name: "New York Yankees", short: "NYY", league: "mlb")

    static var mlbLive: Game {
        Game(
            idLiveScore: "mlb-lad-nyy-001",
            idEvent: "mlb-lad-nyy-001",
            idLeague: "\(Leagues.mlb.rawValue)",
            idHomeTeam: mlbHomeTeam.idTeam,
            idAwayTeam: mlbAwayTeam.idTeam,
            strHomeTeam: mlbHomeTeam.strTeam ?? "",
            strAwayTeam: mlbAwayTeam.strTeam ?? "",
            strHomeTeamBadge: mlbHomeTeam.strTeamBadge,
            strAwayTeamBadge: mlbAwayTeam.strTeamBadge,
            intHomeScore: "4",
            intAwayScore: "3",
            strStatus: "in",
            strProgress: "Top 7",
            strTimestamp: iso(anchor),
            homeLinescores: [0, 1, 0, 2, 0, 1, 0],
            awayLinescores: [0, 0, 2, 0, 0, 1, 0],
            homeLeaders: [
                GameLeader(category: "hitting", categoryDisplay: "HIT", playerName: "Shohei Ohtani", displayValue: "2-3, HR, 2 RBI"),
                GameLeader(category: "pitching", categoryDisplay: "PIT", playerName: "Tyler Glasnow", displayValue: "6 IP, 7 K, 2 ER")
            ],
            awayLeaders: [
                GameLeader(category: "hitting", categoryDisplay: "HIT", playerName: "Aaron Judge", displayValue: "1-3, HR, RBI"),
                GameLeader(category: "pitching", categoryDisplay: "PIT", playerName: "Gerrit Cole", displayValue: "5.2 IP, 6 K, 3 ER")
            ],
            isoDate: anchor,
            venueName: "Dodger Stadium",
            homeTeamColor: "005A9C",
            awayTeamColor: "003087",
            homeRecord: "45-22",
            awayRecord: "41-26"
        )
    }

    // MARK: - NHL: Bruins vs Maple Leafs (live, 2nd period)

    static let nhlHomeTeam = team(id: "bos", name: "Boston Bruins", short: "BOS", league: "nhl")
    static let nhlAwayTeam = team(id: "tor", name: "Toronto Maple Leafs", short: "TOR", league: "nhl")

    static var nhlLive: Game {
        Game(
            idLiveScore: "nhl-bos-tor-001",
            idEvent: "nhl-bos-tor-001",
            idLeague: "\(Leagues.nhl.rawValue)",
            idHomeTeam: nhlHomeTeam.idTeam,
            idAwayTeam: nhlAwayTeam.idTeam,
            strHomeTeam: nhlHomeTeam.strTeam ?? "",
            strAwayTeam: nhlAwayTeam.strTeam ?? "",
            strHomeTeamBadge: nhlHomeTeam.strTeamBadge,
            strAwayTeamBadge: nhlAwayTeam.strTeamBadge,
            intHomeScore: "3",
            intAwayScore: "2",
            strStatus: "in",
            strProgress: "12:08 - 2nd",
            strTimestamp: iso(anchor),
            homeLinescores: [2, 1, 0],
            awayLinescores: [1, 1, 0],
            isoDate: anchor,
            venueName: "TD Garden",
            homeTeamColor: "FFB81C",
            awayTeamColor: "00205B",
            homeRecord: "38-15-9",
            awayRecord: "36-18-8"
        )
    }

    // MARK: - Premier League: Man City vs Arsenal (upcoming in ~3 hours)

    static let soccerHomeTeam = Team(
        idTeam: "382",
        strTeam: "Manchester City",
        strTeamShort: "MCI",
        strAlternate: "Man City",
        strTeamBadge: nil
    )
    static let soccerAwayTeam = Team(
        idTeam: "359",
        strTeam: "Arsenal",
        strTeamShort: "ARS",
        strAlternate: "Arsenal",
        strTeamBadge: nil
    )

    static var soccerUpcoming: Game {
        Game(
            idLiveScore: "epl-mci-ars-001",
            idEvent: "epl-mci-ars-001",
            idLeague: "\(Leagues.English_Premier_League.rawValue)",
            idHomeTeam: soccerHomeTeam.idTeam,
            idAwayTeam: soccerAwayTeam.idTeam,
            strHomeTeam: soccerHomeTeam.strTeam ?? "",
            strAwayTeam: soccerAwayTeam.strTeam ?? "",
            strHomeTeamBadge: soccerHomeTeam.strTeamBadge,
            strAwayTeamBadge: soccerAwayTeam.strTeamBadge,
            strStatus: "NS",
            strTimestamp: iso(anchor.addingTimeInterval(3 * 60 * 60)),
            isoDate: anchor.addingTimeInterval(3 * 60 * 60),
            venueName: "Etihad Stadium",
            homeTeamColor: "6CABDD",
            awayTeamColor: "EF0107",
            homeRecord: "22-4-3",
            awayRecord: "20-5-4"
        )
    }

    // MARK: - Masters: Scottie Scheffler leads (live, Round 3)

    static var mastersLive: Game {
        let board = """
        Scottie Scheffler|-14
        Rory McIlroy|-12
        Xander Schauffele|-10
        Ludvig Åberg|-9
        Collin Morikawa|-8
        """
        return Game(
            idLiveScore: "pga-masters-2025",
            idEvent: "pga-masters-2025",
            idLeague: "\(Leagues.pga.rawValue)",
            idHomeTeam: nil,
            idAwayTeam: nil,
            strHomeTeam: "The Masters",
            strAwayTeam: "Scottie Scheffler",
            strStatus: "in",
            strProgress: "Round 3 • 12th",
            strTimestamp: iso(anchor),
            lastPlay: board,
            isoDate: anchor,
            leaderboardEntries: [
                LeaderboardEntry(name: "Scottie Scheffler", score: "-14", position: 1, thruHole: "12", rounds: ["68", "66", "69"]),
                LeaderboardEntry(name: "Rory McIlroy", score: "-12", position: 2, thruHole: "12", rounds: ["71", "65", "68"]),
                LeaderboardEntry(name: "Xander Schauffele", score: "-10", position: 3, thruHole: "11", rounds: ["70", "67", "69"]),
                LeaderboardEntry(name: "Ludvig Åberg", score: "-9", position: 4, thruHole: "13", rounds: ["69", "68", "70"]),
                LeaderboardEntry(name: "Collin Morikawa", score: "-8", position: 5, thruHole: "12", rounds: ["72", "66", "70"]),
                LeaderboardEntry(name: "Jon Rahm", score: "-7", position: 6, thruHole: "10", rounds: ["70", "68", "71"]),
                LeaderboardEntry(name: "Viktor Hovland", score: "-6", position: 7, thruHole: "11", rounds: ["71", "69", "70"]),
                LeaderboardEntry(name: "Patrick Cantlay", score: "-5", position: 8, thruHole: "12", rounds: ["72", "68", "71"])
            ],
            venueName: "Augusta National Golf Club",
            tournamentName: "The Masters"
        )
    }

    // MARK: - US Open Tennis: Alcaraz vs Sinner (live)

    static var usOpenTennisLive: Game {
        Game(
            idLiveScore: "atp-usopen-alcaraz-sinner",
            idEvent: "atp-usopen-alcaraz-sinner",
            idLeague: "\(Leagues.atp.rawValue)",
            idHomeTeam: nil,
            idAwayTeam: nil,
            strHomeTeam: "Carlos Alcaraz",
            strAwayTeam: "Jannik Sinner",
            intHomeScore: "2",
            intAwayScore: "1",
            strStatus: "in",
            strProgress: "Semifinal • Set 4",
            strTimestamp: iso(anchor),
            homeLinescores: [6, 4, 7, 3],
            awayLinescores: [4, 6, 5, 4],
            isoDate: anchor,
            venueName: "Arthur Ashe Stadium",
            tournamentName: "US Open"
        )
    }

    // MARK: - F1 Monaco GP (live, lap 42/78)

    static var monacoLive: Game {
        let board = """
        Max Verstappen|1|Leader|Red Bull Racing
        Lando Norris|2|+2.341|McLaren
        Charles Leclerc|3|+5.872|Ferrari
        Oscar Piastri|4|+9.104|McLaren
        Carlos Sainz|5|+12.488|Ferrari
        Lewis Hamilton|6|+15.902|Mercedes
        """
        return Game(
            idLiveScore: "f1-monaco-2025",
            idEvent: "f1-monaco-2025",
            idLeague: "\(Leagues.formula1.rawValue)",
            idHomeTeam: nil,
            idAwayTeam: nil,
            strHomeTeam: "Monaco Grand Prix",
            strAwayTeam: "Max Verstappen",
            strStatus: "in",
            strProgress: "Lap 42 / 78",
            strTimestamp: iso(anchor),
            lastPlay: board,
            isoDate: anchor,
            sessions: [
                EventSession(sessionType: "Practice 1", sessionName: "FP1", status: "post", progress: "Final", date: nil),
                EventSession(sessionType: "Practice 2", sessionName: "FP2", status: "post", progress: "Final", date: nil),
                EventSession(sessionType: "Practice 3", sessionName: "FP3", status: "post", progress: "Final", date: nil),
                EventSession(sessionType: "Qualifying", sessionName: "Qualifying", status: "post", progress: "Pole: M. Verstappen — 1:10.270", date: nil),
                EventSession(sessionType: "Race", sessionName: "Race", status: "in", progress: "Lap 42 / 78", date: iso(anchor))
            ],
            venueName: "Circuit de Monaco",
            circuitInfo: F1CircuitInfo(
                circuitName: "Circuit de Monaco",
                locality: "Monte Carlo",
                country: "Monaco",
                circuitImageURL: nil
            )
        )
    }

    static var f1Standings: F1Standings {
        F1Standings(
            driverStandings: [
                F1DriverStanding(position: 1, driverName: "Max Verstappen", constructorName: "Red Bull Racing", points: 437, wins: 14, nationality: "NED"),
                F1DriverStanding(position: 2, driverName: "Lando Norris", constructorName: "McLaren", points: 374, wins: 4, nationality: "GBR"),
                F1DriverStanding(position: 3, driverName: "Charles Leclerc", constructorName: "Ferrari", points: 356, wins: 3, nationality: "MON"),
                F1DriverStanding(position: 4, driverName: "Oscar Piastri", constructorName: "McLaren", points: 292, wins: 2, nationality: "AUS"),
                F1DriverStanding(position: 5, driverName: "Carlos Sainz", constructorName: "Ferrari", points: 290, wins: 1, nationality: "ESP")
            ],
            constructorStandings: [
                F1ConstructorStanding(position: 1, constructorName: "McLaren", points: 666, wins: 6, nationality: "GBR"),
                F1ConstructorStanding(position: 2, constructorName: "Ferrari", points: 652, wins: 4, nationality: "ITA"),
                F1ConstructorStanding(position: 3, constructorName: "Red Bull Racing", points: 589, wins: 9, nationality: "AUT"),
                F1ConstructorStanding(position: 4, constructorName: "Mercedes", points: 418, wins: 4, nationality: "GER")
            ]
        )
    }

    // MARK: - Day roster & viewModel

    /// The full set of games shown on a populated "game day".
    static var gameDayGames: [Game] {
        [nbaLive, nflFinal, mlbLive, nhlLive, soccerUpcoming, mastersLive, usOpenTennisLive, monacoLive]
    }

    /// Teams referenced by the games — used by GameViewModel to resolve team lookups.
    static var allTeams: [Team] {
        [nbaHomeTeam, nbaAwayTeam, nflHomeTeam, nflAwayTeam, mlbHomeTeam, mlbAwayTeam,
         nhlHomeTeam, nhlAwayTeam, soccerHomeTeam, soccerAwayTeam]
    }

    /// (home, away) pair matching a given realistic game.
    static func teams(for game: Game) -> (home: Team, away: Team) {
        switch game.idEvent {
        case nbaLive.idEvent: return (nbaHomeTeam, nbaAwayTeam)
        case nflFinal.idEvent: return (nflHomeTeam, nflAwayTeam)
        case mlbLive.idEvent: return (mlbHomeTeam, mlbAwayTeam)
        case nhlLive.idEvent: return (nhlHomeTeam, nhlAwayTeam)
        case soccerUpcoming.idEvent: return (soccerHomeTeam, soccerAwayTeam)
        default:
            let fallback = DebugGameFactory.fakeTeams(for: game)
            return fallback
        }
    }

    @MainActor
    static func populatedViewModel() -> GameViewModel {
        let games = gameDayGames
        let liveEvents = games.filter { $0.strStatus == "in" }

        let storage = UserDefaultStorage()
        storage.shouldShowNBA = true
        storage.shouldShowNFL = true
        storage.shouldShowNHL = true
        storage.shouldShowSoccer = true
        storage.shouldShowMLB = true
        storage.shouldShowGolf = true
        storage.shouldShowTennis = true
        storage.shouldShowRacing = true

        let favorites = Favorites()
        GameViewModel.isSnapshotTesting = true
        let vm = GameViewModel(appStorage: storage, favorites: favorites)
        vm.applySnapshotFixtures(
            games: games,
            liveEvents: liveEvents,
            teams: allTeams,
            f1Standings: f1Standings
        )
        return vm
    }
}
