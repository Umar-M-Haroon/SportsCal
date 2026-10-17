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
        let row = game(id: "2548865", at: "2026-10-17T02:00:00")
        let index = LiveFixtureIndex(live: [game(id: "401898409", at: "2026-10-17T02:00Z")], schedule: [row])
        XCTAssertTrue(index.contains(row))
    }

    func testMatchesByID() {
        let row = game(id: "1", home: "Other", at: "2026-10-20T02:00:00")
        let index = LiveFixtureIndex(live: [game(id: "1", at: "2026-10-17T02:00Z")], schedule: [row])
        XCTAssertTrue(index.contains(row))
    }

    func testIgnoresTheSameTeamsOnAnotherDay() {
        let row = game(id: "2548999", at: "2026-10-19T02:00:00")
        let index = LiveFixtureIndex(live: [game(id: "401898409", at: "2026-10-17T02:00Z")], schedule: [row])
        XCTAssertFalse(index.contains(row))
    }

    func testIgnoresOtherLeaguesAndTeams() {
        let otherLeague = game(id: "2", league: "4380", at: "2026-10-17T02:00:00")
        let otherTeam = game(id: "3", home: "Los Angeles Lakers", at: "2026-10-17T02:00:00")
        let index = LiveFixtureIndex(live: [game(id: "401898409", at: "2026-10-17T02:00Z")],
                                     schedule: [otherLeague, otherTeam])
        XCTAssertFalse(index.contains(otherLeague))
        XCTAssertFalse(index.contains(otherTeam))
    }

    /// Game 1 of a doubleheader is live; game 2, three hours later, must stay listed.
    func testDoubleheaderClaimsOnlyTheNearestRow() {
        let first = game(id: "10", league: "4424", home: "Tampa Bay Rays", away: "Cleveland Guardians",
                         at: "2026-10-16T17:00:00")
        let second = game(id: "11", league: "4424", home: "Tampa Bay Rays", away: "Cleveland Guardians",
                          at: "2026-10-16T20:00:00")
        let live = game(id: "401", league: "4424", home: "Tampa Bay Rays", away: "Cleveland Guardians",
                        at: "2026-10-16T17:05Z")
        let index = LiveFixtureIndex(live: [live], schedule: [first, second])
        XCTAssertTrue(index.contains(first))
        XCTAssertFalse(index.contains(second))
    }
}
