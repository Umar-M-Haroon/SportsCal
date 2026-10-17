import XCTest
@testable import SportsCalModel

/// The live feed (ESPN ids) and the schedule (TheSportsDB ids) carry the same game under
/// different ids; lists must still recognise the schedule copy as live.
final class LiveFixtureIndexTests: XCTestCase {

    private func game(id: String, league: String = "4387", home: String = "Golden State Warriors",
                      away: String = "Portland Trail Blazers", at timestamp: String) -> Game {
        Game(idEvent: id, idLeague: league, strHomeTeam: home, strAwayTeam: away,
             strTimestamp: timestamp, isoDate: nil)
    }

    func testMatchesScheduleCopyUnderAnotherID() {
        let index = LiveFixtureIndex(live: [game(id: "401898409", at: "2026-10-17T02:00Z")])
        XCTAssertTrue(index.contains(game(id: "2548865", at: "2026-10-17T02:00:00")))
    }

    func testMatchesByID() {
        let index = LiveFixtureIndex(live: [game(id: "1", at: "2026-10-17T02:00Z")])
        XCTAssertTrue(index.contains(game(id: "1", home: "Other", at: "2026-10-20T02:00:00")))
    }

    func testIgnoresTheSameTeamsOnAnotherDay() {
        let index = LiveFixtureIndex(live: [game(id: "401898409", at: "2026-10-17T02:00Z")])
        XCTAssertFalse(index.contains(game(id: "2548999", at: "2026-10-19T02:00:00")))
    }

    func testIgnoresOtherLeaguesAndTeams() {
        let index = LiveFixtureIndex(live: [game(id: "401898409", at: "2026-10-17T02:00Z")])
        XCTAssertFalse(index.contains(game(id: "2", league: "4380", at: "2026-10-17T02:00:00")))
        XCTAssertFalse(index.contains(game(id: "3", home: "Los Angeles Lakers", at: "2026-10-17T02:00:00")))
    }
}
