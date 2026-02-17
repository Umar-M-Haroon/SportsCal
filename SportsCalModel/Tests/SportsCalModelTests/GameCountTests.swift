import XCTest
@testable import SportsCalModel

/// Tests to verify that mock JSON files contain expected game counts.
/// These tests ensure data parsing integrity and serve as baseline validation.
final class GameCountTests: XCTestCase {

    // MARK: - ESPN Scoreboard Tests (API2 format)

    func testNBAScoreboardGameCount() throws {
        let scoreboard = try XCTUnwrap(
            JSONLoader.load(file: "BasketballScoreboard", type: Scoreboard.self) as? Scoreboard
        )
        XCTAssertEqual(scoreboard.events.count, 9, "BasketballScoreboard.json should contain 9 events")
    }

    func testNFLScoreboardGameCount() throws {
        let scoreboard = try XCTUnwrap(
            JSONLoader.load(file: "NFLScoreboard", type: Scoreboard.self) as? Scoreboard
        )
        XCTAssertEqual(scoreboard.events.count, 1, "NFLScoreboard.json should contain 1 event")
    }

    func testNHLScoreboardGameCount() throws {
        let scoreboard = try XCTUnwrap(
            JSONLoader.load(file: "NHLScoreboard", type: Scoreboard.self) as? Scoreboard
        )
        XCTAssertEqual(scoreboard.events.count, 2, "NHLScoreboard.json should contain 2 events")
    }

    func testMLBScoreboardGameCount() throws {
        let scoreboard = try XCTUnwrap(
            JSONLoader.load(file: "MLBScoreboard", type: Scoreboard.self) as? Scoreboard
        )
        XCTAssertEqual(scoreboard.events.count, 2, "MLBScoreboard.json should contain 2 events")
    }

    func testSoccerScoreboardGameCount() throws {
        let scoreboard = try XCTUnwrap(
            JSONLoader.load(file: "SoccerScoreboard", type: Scoreboard.self) as? Scoreboard
        )
        XCTAssertEqual(scoreboard.events.count, 2, "SoccerScoreboard.json should contain 2 events")
    }

    func testPremierLeagueScoreboardGameCount() throws {
        let scoreboard = try XCTUnwrap(
            JSONLoader.load(file: "Premier-League-Scoreboard", type: Scoreboard.self) as? Scoreboard
        )
        XCTAssertEqual(scoreboard.events.count, 12, "Premier-League-Scoreboard.json should contain 12 events")
    }

    // MARK: - TSDB LiveScore Tests (MainAPI format)

    func testLiveScoreEventCounts() throws {
        let liveScore = try XCTUnwrap(
            JSONLoader.load(file: "TSDBLive", type: LiveScore.self) as? LiveScore
        )

        // NBA should have 7 events
        XCTAssertEqual(liveScore.nba?.events.count, 7, "TSDBLive.json NBA should contain 7 events")

        // NFL should have 0 events (off-season in mock data)
        XCTAssertEqual(liveScore.nfl?.events.count, 0, "TSDBLive.json NFL should contain 0 events")

        // NHL should have 8 events
        XCTAssertEqual(liveScore.nhl?.events.count, 8, "TSDBLive.json NHL should contain 8 events")

        // Soccer should have 0 events in this snapshot
        XCTAssertEqual(liveScore.soccer?.events.count, 0, "TSDBLive.json soccer should contain 0 events")

        // MLB should have 0 events (off-season in mock data)
        XCTAssertEqual(liveScore.mlb?.events.count, 0, "TSDBLive.json MLB should contain 0 events")
    }

    // MARK: - Additional Scoreboard Variations

    func testBasketballScoreboardCurrentlyPlayingGameCount() throws {
        let scoreboard = try XCTUnwrap(
            JSONLoader.load(file: "BasketballScoreboardCurrentlyPlaying", type: Scoreboard.self) as? Scoreboard
        )
        XCTAssertEqual(scoreboard.events.count, 10, "BasketballScoreboardCurrentlyPlaying.json should contain 10 events")
    }

    func testBasketballScoreboardMultipleDatesGameCount() throws {
        let scoreboard = try XCTUnwrap(
            JSONLoader.load(file: "BasketballScoreboardMultipleDates", type: Scoreboard.self) as? Scoreboard
        )
        XCTAssertEqual(scoreboard.events.count, 32, "BasketballScoreboardMultipleDates.json should contain 32 events")
    }

    func testNBAScoreboardWithCompletedGamesCount() throws {
        let scoreboard = try XCTUnwrap(
            JSONLoader.load(file: "NBAScoreboardWithCompletedGames", type: Scoreboard.self) as? Scoreboard
        )
        XCTAssertEqual(scoreboard.events.count, 8, "NBAScoreboardWithCompletedGames.json should contain 8 events")
    }
}
