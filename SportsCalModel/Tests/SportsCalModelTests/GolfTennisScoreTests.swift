//
//  GolfTennisScoreTests.swift
//  SportsCalModelTests
//
//  Fixtures are trimmed copies of real ESPN boards (2026-11-07): the World Wide
//  Technology Championship suspended mid round 2, and WTA Hong Kong / Chennai / Luanda
//  with a live match, retirements and walkovers.
//

import XCTest
@testable import SportsCalModel

final class GolfTennisScoreTests: XCTestCase {
    private func golfGame(limit: Int? = LiveEvent.golfFieldLimit) throws -> Game {
        let board = try XCTUnwrap(JSONLoader.load(file: "PGAGolfSuspendedRound", type: Scoreboard.self) as? Scoreboard)
        return try XCTUnwrap(LiveEvent(events: board, league: .pga, golfFieldLimit: limit)?.events.first)
    }

    private func tennisGames() throws -> [Game] {
        let board = try XCTUnwrap(JSONLoader.load(file: "WTATennisLiveAndRetired", type: Scoreboard.self) as? Scoreboard)
        return try XCTUnwrap(LiveEvent(events: board, league: .wta)?.events)
    }

    // MARK: Golf

    func testRoundInProgressIsNotCountedAsFinished() throws {
        let game = try golfGame()
        let rozo = try XCTUnwrap(game.leaderboardEntries?.first { $0.name == "Marcelo Rozo" })
        // Through 17 of round 2 with 64 strokes: one finished round, the second is "today".
        XCTAssertEqual(rozo.rounds, ["69"])
        XCTAssertEqual(rozo.today, "-3")
        XCTAssertEqual(rozo.thruHole, "17")
        XCTAssertTrue(rozo.isOnCourse)

        let leader = try XCTUnwrap(game.leaderboardEntries?.first)
        XCTAssertEqual(leader.rounds, ["65", "64"])
        XCTAssertEqual(leader.thruHole, "F")
        XCTAssertEqual(leader.today, "-8")
        XCTAssertFalse(leader.isOnCourse)
        XCTAssertEqual(game.golfCourseInfo?.par, 72)
    }

    func testSuspensionAndRoundReadFromProgress() throws {
        let game = try golfGame()
        XCTAssertEqual(game.golfCurrentRound, 2)
        XCTAssertNotNil(game.golfStoppageText)
        XCTAssertEqual(game.golfScheduledRounds, 4)
    }

    func testFieldLimitOnlyAppliesToTheSchedule() throws {
        XCTAssertEqual(try golfGame(limit: 2).leaderboardEntries?.count, 2)
        XCTAssertEqual(try golfGame(limit: nil).leaderboardEntries?.count, 5)
    }

    func testTiedPositions() {
        let entries = [
            LeaderboardEntry(name: "A", score: "-10", position: 1),
            LeaderboardEntry(name: "B", score: "-8", position: 2),
            LeaderboardEntry(name: "C", score: "-8", position: 3),
            LeaderboardEntry(name: "D", score: "-7", position: 4),
            LeaderboardEntry(name: "E", score: "CUT", position: 5, isCut: true),
        ]
        XCTAssertEqual(entries.golfPositionLabels(), ["1", "T2", "T2", "4", "CUT"])
    }

    func testTeeTimeParsesESPNStatText() throws {
        let tee = try XCTUnwrap(GolfTeeTime(text: "Fri Nov 06 09:14:00 PST 2026"))
        XCTAssertEqual(tee.displayString, "9:14 AM")
        XCTAssertEqual(tee.isoString, "2026-11-06T17:14:00Z")
    }

    // MARK: Tennis

    func testInProgressSetIsNotWon() throws {
        let live = try XCTUnwrap(try tennisGames().first { $0.strStatus == "in" })
        // Liu leads Shubladze 7-5 5-4: one set to nil, not two.
        let won = live.tennisSetsWon
        XCTAssertEqual(won.home + won.away, 1)
        XCTAssertEqual(live.tennisSets.last?.isComplete, false)
        XCTAssertEqual(live.tennisServer, .home)
        XCTAssertNil(live.tennisMatchWinner)
        XCTAssertEqual(live.tennisCourt, "Centre Court")
    }

    func testRetirementAndWalkoverWinners() throws {
        let games = try tennisGames()
        let retired = try XCTUnwrap(games.first { $0.strAwayTeam == "Rada Zolotareva" })
        XCTAssertEqual(retired.tennisResultMarker, "ret.")
        XCTAssertEqual(retired.tennisMatchWinner, .away)
        XCTAssertEqual(retired.tennisSetsWon.away, 1)

        let walkover = try XCTUnwrap(games.first { $0.tennisResultMarker == "w/o" })
        XCTAssertEqual(walkover.tennisMatchWinner, .home)
        XCTAssertTrue(walkover.tennisSets.isEmpty)
    }

    func testTiebreakSuperscript() {
        let set = TennisSet(home: 7, away: 6, homeTiebreak: 7, awayTiebreak: 4, winner: .home, isComplete: true)
        XCTAssertEqual(set.text(for: .home), "7⁷")
        XCTAssertEqual(set.text(for: .away), "6⁴")
    }

    func testLegacyPayloadFallsBackToSetScores() {
        let game = Game(idLeague: "\(Leagues.atp.rawValue)", idHomeTeam: "1", idAwayTeam: "2",
                        strHomeTeam: "A", strAwayTeam: "B", strStatus: "in",
                        homeLinescores: [6, 3], awayLinescores: [4, 2], isoDate: nil)
        XCTAssertEqual(game.tennisSetsWon.home, 1)
        XCTAssertEqual(game.tennisSetsWon.away, 0)
    }
}
