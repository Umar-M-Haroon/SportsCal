import XCTest
import SportsCalModel
@testable import Scoreline

/// Tests that GameViewModel filtering logic correctly shows/hides games
/// based on sport preferences and hidden competitions.
@MainActor
final class ScheduleFilterTests: XCTestCase {

    private var appStorage: UserDefaultStorage!
    private var favorites: Favorites!
    private var viewModel: GameViewModel!

    /// Keys to reset in tearDown to avoid test pollution
    private let sportKeys = [
        "shouldShowNBA", "shouldShowNFL", "shouldShowNHL",
        "shouldShowSoccer", "shouldShowMLB", "shouldShowGolf",
        "shouldShowTennis", "shouldShowRacing", "hiddenCompetitions",
        "favoritesOnlyNBA", "favoritesOnlyNFL", "favoritesOnlyNHL",
        "favoritesOnlySoccer", "favoritesOnlyMLB", "favoritesOnlyGolf",
        "favoritesOnlyTennis", "favoritesOnlyRacing",
        "Favorites", "FavoritePlayers"
    ]

    override func setUp() {
        super.setUp()
        // Clear stores before constructing UserDefaultStorage / Favorites so they
        // initialize from a clean state.
        let appGroup = UserDefaults(suiteName: "group.Komodo.SportsCal")
        for key in sportKeys {
            UserDefaults.standard.removeObject(forKey: key)
            appGroup?.removeObject(forKey: key)
        }

        appStorage = UserDefaultStorage()
        favorites = Favorites()
        viewModel = GameViewModel(appStorage: appStorage, favorites: favorites)

        // Build mock games with known counts per league
        let mockGames = buildMockGames()
        viewModel.totalGames = mockGames

        // Build gamesDict from totalGames (mirrors what setGames does)
        let validGames = mockGames.filter { game in
            guard let leagueString = game.idLeague,
                  let intLeague = Int(leagueString),
                  let _ = Leagues(rawValue: intLeague) else { return false }
            return true
        }
        viewModel.gamesDict = Dictionary(grouping: validGames) { game in
            SportType(league: Leagues(rawValue: Int(game.idLeague!)!)!)
        }
    }

    override func tearDown() {
        let appGroup = UserDefaults(suiteName: "group.Komodo.SportsCal")
        for key in sportKeys {
            UserDefaults.standard.removeObject(forKey: key)
            appGroup?.removeObject(forKey: key)
        }
        super.tearDown()
    }

    // MARK: - Mock Data Builder

    /// Creates a small set of games across multiple sports with future timestamps
    private func buildMockGames() -> [Game] {
        let futureDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400))
        var games: [Game] = []

        // 5 NBA games
        for i in 0..<5 {
            games.append(Game(
                idEvent: "nba-\(i)", idLeague: "\(Leagues.nba.rawValue)",
                strHomeTeam: "Home NBA \(i)", strAwayTeam: "Away NBA \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }

        // 3 NFL games
        for i in 0..<3 {
            games.append(Game(
                idEvent: "nfl-\(i)", idLeague: "\(Leagues.nfl.rawValue)",
                strHomeTeam: "Home NFL \(i)", strAwayTeam: "Away NFL \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }

        // 4 NHL games
        for i in 0..<4 {
            games.append(Game(
                idEvent: "nhl-\(i)", idLeague: "\(Leagues.nhl.rawValue)",
                strHomeTeam: "Home NHL \(i)", strAwayTeam: "Away NHL \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }

        // 2 MLB games
        for i in 0..<2 {
            games.append(Game(
                idEvent: "mlb-\(i)", idLeague: "\(Leagues.mlb.rawValue)",
                strHomeTeam: "Home MLB \(i)", strAwayTeam: "Away MLB \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }

        // 6 Soccer: 3 EPL + 2 La Liga + 1 UCL
        for i in 0..<3 {
            games.append(Game(
                idEvent: "epl-\(i)", idLeague: "\(Leagues.English_Premier_League.rawValue)",
                strHomeTeam: "Home EPL \(i)", strAwayTeam: "Away EPL \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }
        for i in 0..<2 {
            games.append(Game(
                idEvent: "laliga-\(i)", idLeague: "\(Leagues.La_Liga.rawValue)",
                strHomeTeam: "Home LaLiga \(i)", strAwayTeam: "Away LaLiga \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }
        games.append(Game(
            idEvent: "ucl-0", idLeague: "\(Leagues.UEFA_Champions_League.rawValue)",
            strHomeTeam: "Home UCL", strAwayTeam: "Away UCL",
            strTimestamp: futureDate, isoDate: nil
        ))

        // 2 Golf (PGA)
        for i in 0..<2 {
            games.append(Game(
                idEvent: "pga-\(i)", idLeague: "\(Leagues.pga.rawValue)",
                strHomeTeam: "PGA Tournament \(i)", strAwayTeam: "Leader \(i)",
                strTimestamp: futureDate, isoDate: nil
            ))
        }

        // 2 Tennis (1 ATP + 1 WTA)
        games.append(Game(
            idEvent: "atp-0", idLeague: "\(Leagues.atp.rawValue)",
            strHomeTeam: "ATP Event", strAwayTeam: "ATP Leader",
            strTimestamp: futureDate, isoDate: nil
        ))
        games.append(Game(
            idEvent: "wta-0", idLeague: "\(Leagues.wta.rawValue)",
            strHomeTeam: "WTA Event", strAwayTeam: "WTA Leader",
            strTimestamp: futureDate, isoDate: nil
        ))

        // 1 Racing (F1)
        games.append(Game(
            idEvent: "f1-0", idLeague: "\(Leagues.formula1.rawValue)",
            strHomeTeam: "Grand Prix", strAwayTeam: "Leader",
            strTimestamp: futureDate, isoDate: nil
        ))

        return games
    }

    // MARK: - Tests

    func testFilterShowsOnlyEnabledSports() {
        appStorage.shouldShowNBA = true
        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(filtered.count, 5, "Only 5 NBA games should show")
        XCTAssertTrue(filtered.allSatisfy { $0.idLeague == "\(Leagues.nba.rawValue)" })
    }

    func testFilterShowsAllSportsWhenAllEnabled() {
        appStorage.shouldShowNBA = true
        appStorage.shouldShowNFL = true
        appStorage.shouldShowNHL = true
        appStorage.shouldShowMLB = true
        appStorage.shouldShowSoccer = true
        appStorage.shouldShowGolf = true
        appStorage.shouldShowTennis = true
        appStorage.shouldShowRacing = true

        let filtered = viewModel.getGamesFromUserPreferences()
        // 5 NBA + 3 NFL + 4 NHL + 2 MLB + 6 Soccer + 2 Golf + 2 Tennis + 1 Racing = 25
        XCTAssertEqual(filtered.count, 25, "All 25 mock games should show when all sports enabled")
    }

    func testFilterShowsNoSportsWhenAllDisabled() {
        // All sports disabled by default from setUp
        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(filtered.count, 0, "No games should show when all sports disabled")
    }

    func testSoccerFilterRespectsHiddenCompetitions() {
        appStorage.shouldShowSoccer = true

        // First verify all soccer shows
        let allSoccer = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(allSoccer.count, 6, "All 6 soccer games should show initially")

        // Hide La Liga
        appStorage.hiddenCompetitions = ["La Liga"]
        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(filtered.count, 4, "Should exclude 2 La Liga games, leaving 4")
        XCTAssertFalse(filtered.contains { $0.idLeague == "\(Leagues.La_Liga.rawValue)" })
    }

    func testFilteredGamesHaveValidLeagueIDs() {
        appStorage.shouldShowNBA = true
        appStorage.shouldShowSoccer = true
        appStorage.shouldShowGolf = true

        let filtered = viewModel.getGamesFromUserPreferences()
        let validLeagueIDs = Set(Leagues.allCases.map { "\($0.rawValue)" })

        for game in filtered {
            XCTAssertNotNil(game.idLeague, "Filtered game should have idLeague")
            XCTAssertTrue(
                validLeagueIDs.contains(game.idLeague ?? ""),
                "Game has invalid idLeague: \(game.idLeague ?? "nil")"
            )
        }
    }

    func testMultipleSportsFilter() {
        appStorage.shouldShowNBA = true
        appStorage.shouldShowNHL = true

        let filtered = viewModel.getGamesFromUserPreferences()
        // 5 NBA + 4 NHL = 9
        XCTAssertEqual(filtered.count, 9, "Should show 5 NBA + 4 NHL = 9 games")

        let sports = Set(filtered.compactMap { $0.strSport })
        XCTAssertEqual(sports, ["basketball", "hockey"])
    }

    // MARK: - Favorites-Only Tests

    func testFavoritesOnlyMLBShowsOnlyFavoritedTeamGames() {
        appStorage.shouldShowMLB = true
        appStorage.favoritesOnlyMLB = true
        favorites.add("Home MLB 0") // one of 2 mock MLB teams

        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(filtered.count, 1, "Only 1 MLB game should match the favorited team")
        XCTAssertEqual(filtered.first?.strHomeTeam, "Home MLB 0")
    }

    func testFavoritesOnlyMLBWithNoFavoritesReturnsEmpty() {
        appStorage.shouldShowMLB = true
        appStorage.favoritesOnlyMLB = true
        // No favorites added

        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(filtered.count, 0, "No games should show when favorites-only is on but no favorites exist")
    }

    func testFavoritesOnlyGolfMatchesOnFavoritedPlayer() {
        appStorage.shouldShowGolf = true
        appStorage.favoritesOnlyGolf = true
        favorites.addPlayer("Scottie Scheffler")

        // Inject a leaderboard containing the favorited player into the first golf game.
        guard var pga0 = viewModel.totalGames?.first(where: { $0.idEvent == "pga-0" }) else {
            return XCTFail("Mock PGA game missing")
        }
        pga0 = Game(
            idEvent: pga0.idEvent, idLeague: pga0.idLeague,
            strHomeTeam: pga0.strHomeTeam, strAwayTeam: pga0.strAwayTeam,
            strTimestamp: pga0.strTimestamp, isoDate: nil,
            leaderboardEntries: [
                LeaderboardEntry(name: "Scottie Scheffler", score: "-12", position: 1),
                LeaderboardEntry(name: "Rory McIlroy", score: "-10", position: 2)
            ]
        )
        var updated = viewModel.totalGames ?? []
        if let idx = updated.firstIndex(where: { $0.idEvent == "pga-0" }) { updated[idx] = pga0 }
        viewModel.totalGames = updated
        viewModel.gamesDict[.golf] = updated.filter { $0.idLeague == "\(Leagues.pga.rawValue)" }

        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertEqual(filtered.count, 1, "Only the tournament with Scheffler should remain")
        XCTAssertEqual(filtered.first?.idEvent, "pga-0")
    }

    func testSportToggleOffSuppressesFavoritesOnly() {
        appStorage.shouldShowMLB = false
        appStorage.favoritesOnlyMLB = true
        favorites.add("Home MLB 0")

        let filtered = viewModel.getGamesFromUserPreferences()
        XCTAssertTrue(filtered.isEmpty, "Sport disabled should trump favorites-only")
    }

    func testHidingMultipleSoccerCompetitions() {
        appStorage.shouldShowSoccer = true
        appStorage.hiddenCompetitions = [
            Leagues.La_Liga.leagueName,
            Leagues.UEFA_Champions_League.leagueName
        ]

        let filtered = viewModel.getGamesFromUserPreferences()
        // Only EPL (3 games) should remain
        XCTAssertEqual(filtered.count, 3, "Should only show 3 EPL games after hiding La Liga + UCL")
        XCTAssertTrue(filtered.allSatisfy {
            $0.idLeague == "\(Leagues.English_Premier_League.rawValue)"
        })
    }
}
