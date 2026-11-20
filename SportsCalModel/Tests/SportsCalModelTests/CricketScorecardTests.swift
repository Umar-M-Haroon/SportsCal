import XCTest
@testable import SportsCalModel

final class CricketScorecardTests: XCTestCase {
    private func card() throws -> CricketScorecard {
        let summary = try JSONDecoder().decode(ESPNCricketSummary.self, from: Data(cricketSummaryFixture.utf8))
        return try XCTUnwrap(summary.scorecard(eventID: "1539442"))
    }

    func testInningsInOrderWithTheRightSides() throws {
        let card = try card()
        XCTAssertEqual(card.innings.map(\.number), [1, 2])
        XCTAssertEqual(card.innings.map(\.battingSide), [.home, .away])
        XCTAssertEqual(card.innings.map(\.battingTeam), ["New Zealand", "India"])
        XCTAssertEqual(card.innings.map(\.total), ["368", "159/1"])
    }

    func testBattersInBattingOrder() throws {
        let first = try card().innings[0]
        XCTAssertEqual(first.batters.count, 11)
        XCTAssertEqual(first.batters.first?.name, "Tom Latham")
        let nicholls = try XCTUnwrap(first.batters.first { $0.name == "Henry Nicholls" })
        XCTAssertEqual(nicholls.runs, 175)
        XCTAssertEqual(nicholls.balls, 335)
        XCTAssertEqual(nicholls.fours, 21)
        XCTAssertEqual(first.batters.first?.dismissal, "b Bumrah")
        XCTAssertEqual(first.batters[1].dismissal, "c †Pant b Kamboj")
    }

    func testBowlersFromTheOtherSide() throws {
        let first = try card().innings[0]
        let bumrah = try XCTUnwrap(first.bowlers.first { $0.name == "Jasprit Bumrah" })
        XCTAssertEqual(bumrah.figures, "4-92")
        XCTAssertEqual(bumrah.overs, 29)
        XCTAssertEqual(bumrah.maidens, 8)
        XCTAssertFalse(first.bowlers.contains { $0.name == "Henry Nicholls" })
    }

    func testLiveInningsHasNotOutsAndYetToBat() throws {
        let second = try card().innings[1]
        XCTAssertEqual(second.batters.map(\.name), ["Yashasvi Jaiswal", "KL Rahul", "Devdutt Padikkal"])
        XCTAssertEqual(second.batters[1].dismissal, "not out")
        XCTAssertFalse(second.batters[1].isOut)
        XCTAssertEqual(second.extras, "(nb 6)")
        XCTAssertEqual(second.yetToBat.count, 8)
        XCTAssertTrue(second.yetToBat.contains("Shubman Gill"))
    }

    func testRoundTrip() throws {
        let card = try card()
        let back = try JSONDecoder().decode(CricketScorecard.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(back, card)
    }
}
