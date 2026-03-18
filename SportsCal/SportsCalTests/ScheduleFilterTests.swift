import XCTest
import SportsCalModel
@testable import SportsCal

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
        "shouldShowTennis", "shouldShowRacing", "hiddenCompetitions"
    ]

    override func setUp() {
        super.setUp()
        appStorage = UserDefaultStorage()
        favorites = Favorites()
        viewModel = GameViewModel(appStorage: appStorage, favorites: favorites)

        // Disable all sports by default
        for key in sportKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

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
        for key in sportKeys {
            UserDefaults.standard.removeObject(forKey: key)
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
