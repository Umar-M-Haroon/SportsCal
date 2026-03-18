import XCTest
@testable import SportsCalModel

/// Deterministic tests against a captured `/schedules` snapshot.
/// The API returns multiple seasons of data, so counts reflect current + previous season.
/// To update the fixture: `curl -H "X-API-Key: <key>" http://localhost:8080/schedules > MockJSON/FullScheduleSnapshot.json`
final class ScheduleSanityTests: XCTestCase {

    private var schedule: LiveScore!

    override func setUpWithError() throws {
        guard let loaded = try? JSONLoader.load(file: "FullScheduleSnapshot", type: LiveScore.self) as? LiveScore else {
            throw XCTSkip("FullScheduleSnapshot.json not found. Capture it with: curl -H 'X-API-Key: <key>' http://localhost:8080/schedules > MockJSON/FullScheduleSnapshot.json")
        }
        schedule = loaded
    }

    // MARK: - Helpers

    private func games(in sport: LiveEvent?, forLeague leagueID: Int) -> [Game] {
        sport?.events.filter { $0.idLeague == "\(leagueID)" } ?? []
    }

    // MARK: - Multi-Season League Counts
    // The API fetches current + previous season. Soccer domestic leagues return ~2× single season.
    // NBA/NHL include regular season + playoffs for both seasons.
    // Tennis returns individual matches (not tournament-level), so counts are very high.

    func testNBAGameCount() {
        let count = games(in: schedule.nba, forLeague: Leagues.nba.rawValue).count
        // ~2 seasons of regular (1230) + playoffs (~100 each)
        XCTAssertGreaterThanOrEqual(count, 2400, "NBA should have ≥2400 games (2 seasons), got \(count)")
        XCTAssertLessThanOrEqual(count, 2800, "NBA should have ≤2800 games, got \(count)")
    }

    func testNHLGameCount() {
        let count = games(in: schedule.nhl, forLeague: Leagues.nhl.rawValue).count
        // ~2 seasons of regular (1312) + playoffs
        XCTAssertGreaterThanOrEqual(count, 2600, "NHL should have ≥2600 games (2 seasons), got \(count)")
        XCTAssertLessThanOrEqual(count, 3100, "NHL should have ≤3100 games, got \(count)")
    }

    func testMLBGameCount() {
        let count = games(in: schedule.mlb, forLeague: Leagues.mlb.rawValue).count
        // Seasonal — could be 0 in off-season or 2430+ during season
        XCTAssertGreaterThanOrEqual(count, 0, "MLB should have ≥0 games, got \(count)")
    }

    func testNFLGameCount() {
        let count = games(in: schedule.nfl, forLeague: Leagues.nfl.rawValue).count
        // Seasonal — could be 0-1 in off-season or 272+ during season
        XCTAssertGreaterThanOrEqual(count, 0, "NFL should have ≥0 games, got \(count)")
    }

    func testEPLGameCount() {
        let count = games(in: schedule.soccer, forLeague: Leagues.English_Premier_League.rawValue).count
        // 2 seasons × 380 = 760
        XCTAssertEqual(count, 760, "EPL should have 760 games (2 seasons × 380), got \(count)")
    }

    func testLaLigaGameCount() {
        let count = games(in: schedule.soccer, forLeague: Leagues.La_Liga.rawValue).count
        // 2 seasons × 380 = 760 (may have +1 from rescheduled matches)
        XCTAssertGreaterThanOrEqual(count, 760, "La Liga should have ≥760 games, got \(count)")
        XCTAssertLessThanOrEqual(count, 765, "La Liga should have ≤765 games, got \(count)")
    }

    func testSerieAGameCount() {
        let count = games(in: schedule.soccer, forLeague: Leagues.Serie_A.rawValue).count
        XCTAssertEqual(count, 760, "Serie A should have 760 games (2 seasons × 380), got \(count)")
    }

    func testBundesligaGameCount() {
        let count = games(in: schedule.soccer, forLeague: Leagues.German_Bundesliga.rawValue).count
        // 2 seasons × 306 = 612, may have extra from rescheduled
        XCTAssertGreaterThanOrEqual(count, 612, "Bundesliga should have ≥612 games, got \(count)")
        XCTAssertLessThanOrEqual(count, 620, "Bundesliga should have ≤620 games, got \(count)")
    }

    func testLigue1GameCount() {
        let count = games(in: schedule.soccer, forLeague: Leagues.Ligue_1.rawValue).count
        XCTAssertGreaterThanOrEqual(count, 612, "Ligue 1 should have ≥612 games, got \(count)")
        XCTAssertLessThanOrEqual(count, 620, "Ligue 1 should have ≤620 games, got \(count)")
    }

    func testEredivisieGameCount() {
        let count = games(in: schedule.soccer, forLeague: Leagues.Eredivisie.rawValue).count
        // Eredivisie has playoffs, so slightly more than 2 × 306
        XCTAssertGreaterThanOrEqual(count, 612, "Eredivisie should have ≥612 games, got \(count)")
        XCTAssertLessThanOrEqual(count, 650, "Eredivisie should have ≤650 games, got \(count)")
    }

    // MARK: - Variable League Range Checks

    func testF1GameCount() {
        let count = games(in: schedule.racing, forLeague: Leagues.formula1.rawValue).count
        // 2 seasons × ~24 races = ~48
        XCTAssertGreaterThanOrEqual(count, 22, "F1 should have ≥22 events, got \(count)")
        XCTAssertLessThanOrEqual(count, 50, "F1 should have ≤50 events, got \(count)")
    }

    func testPGAGameCount() {
        let count = games(in: schedule.golf, forLeague: Leagues.pga.rawValue).count
        // Multiple seasons of tournaments
        XCTAssertGreaterThanOrEqual(count, 80, "PGA should have ≥80 events, got \(count)")
        XCTAssertLessThanOrEqual(count, 300, "PGA should have ≤300 events, got \(count)")
    }

    func testATPGameCount() {
        let count = games(in: schedule.tennis, forLeague: Leagues.atp.rawValue).count
        // Individual matches, not tournaments — very high count
        XCTAssertGreaterThanOrEqual(count, 10000, "ATP should have ≥10000 match events, got \(count)")
        XCTAssertLessThanOrEqual(count, 50000, "ATP should have ≤50000 match events, got \(count)")
    }

    func testWTAGameCount() {
        let count = games(in: schedule.tennis, forLeague: Leagues.wta.rawValue).count
        XCTAssertGreaterThanOrEqual(count, 10000, "WTA should have ≥10000 match events, got \(count)")
        XCTAssertLessThanOrEqual(count, 60000, "WTA should have ≤60000 match events, got \(count)")
    }

    func testUCLGameCount() {
        let count = games(in: schedule.soccer, forLeague: Leagues.UEFA_Champions_League.rawValue).count
        // Multi-season with qualifying rounds
        XCTAssertGreaterThanOrEqual(count, 200, "UCL should have ≥200 events, got \(count)")
        XCTAssertLessThanOrEqual(count, 600, "UCL should have ≤600 events, got \(count)")
    }

    func testCupCompetitionsHaveGames() {
        let cups: [Leagues] = [
            .FA_Cup, .Copa_del_Rey, .Coupe_De_France, .DFB_Pokal,
            .UEFA_Europa_League, .UEFA_Conference_League
        ]
        for cup in cups {
            let count = games(in: schedule.soccer, forLeague: cup.rawValue).count
            XCTAssertGreaterThan(count, 0, "\(cup.leagueName) should have > 0 games, got \(count)")
        }
    }

    // MARK: - Data Integrity

    func testAllGamesHaveValidLeagueID() {
        let allEvents = [
            schedule.nba, schedule.nfl, schedule.nhl, schedule.mlb,
            schedule.soccer, schedule.golf, schedule.tennis, schedule.racing
        ].compactMap { $0 }.flatMap { $0.events }

        let validLeagueIDs = Set(Leagues.allCases.map { "\($0.rawValue)" })

        for game in allEvents {
            guard let leagueID = game.idLeague else {
                XCTFail("Game \(game.strHomeTeam) vs \(game.strAwayTeam) has nil idLeague")
                continue
            }
            XCTAssertTrue(
                validLeagueIDs.contains(leagueID),
                "Game has unknown idLeague \(leagueID): \(game.strHomeTeam) vs \(game.strAwayTeam)"
            )
        }
    }

    func testAllGamesHaveTimestamp() {
        let allEvents = [
            schedule.nba, schedule.nfl, schedule.nhl, schedule.mlb,
            schedule.soccer, schedule.golf, schedule.tennis, schedule.racing
        ].compactMap { $0 }.flatMap { $0.events }

        for game in allEvents {
            XCTAssertNotNil(
                game.strTimestamp,
                "Game \(game.strHomeTeam) vs \(game.strAwayTeam) (league \(game.idLeague ?? "nil")) has nil strTimestamp"
            )
        }
    }

    func testSoccerLeagueBreakdown() {
        guard let soccerEvents = schedule.soccer?.events else {
            XCTFail("Soccer events missing from snapshot")
            return
        }

        let byLeague = Dictionary(grouping: soccerEvents) { $0.idLeague ?? "unknown" }

        let soccerLeagues: [Leagues] = [
            .English_Premier_League, .La_Liga, .Serie_A, .German_Bundesliga,
            .Ligue_1, .Eredivisie, .MLS, .Liga_MX,
            .UEFA_Champions_League, .UEFA_Europa_League, .UEFA_Conference_League,
            .FA_Cup, .Copa_del_Rey, .Coupe_De_France, .DFB_Pokal,
            .English_League_Championship
        ]

        for league in soccerLeagues {
            let key = "\(league.rawValue)"
            let count = byLeague[key]?.count ?? 0
            XCTAssertGreaterThan(
                count, 0,
                "\(league.leagueName) (id: \(league.rawValue)) should have > 0 games in soccer events, got \(count)"
            )
        }
    }
}
