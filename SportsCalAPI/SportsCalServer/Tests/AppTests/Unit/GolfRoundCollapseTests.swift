import XCTest
@testable import App
import SportsCalModel

/// Pins `ScheduleUpdateJob.collapseGolfRounds`. TheSportsDB publishes a golf tournament as one
/// event per round, which put four rows on the board for one tournament and matched
/// nothing on the ESPN side (whose event has no round suffix), so the ESPN row was
/// appended on top of them.
final class GolfRoundCollapseTests: XCTestCase {

    private func round(_ id: String, _ name: String, _ timestamp: String) -> Game {
        var game = Game(idEvent: id, idLeague: "\(Leagues.pga.rawValue)",
                        strHomeTeam: name, strAwayTeam: "TBD",
                        strTimestamp: timestamp, isoDate: nil)
        game.isoDate = game.getDate()
        return game
    }

    /// The real shape, from the live payload: 4 rows, "Round 1…3" plus "Final Round".
    private var sentry: [Game] {
        [round("1", "The Sentry Round 1", "2026-01-02T00:00:00"),
         round("2", "The Sentry Round 2", "2026-01-03T00:00:00"),
         round("3", "The Sentry Round 3", "2026-01-04T00:00:00"),
         round("4", "The Sentry Final Round", "2026-01-05T00:00:00")]
    }

    func testRoundsBecomeOneTournamentSpanningThemAll() {
        let collapsed = ScheduleUpdateJob.collapseGolfRounds(sentry)
        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed[0].strHomeTeam, "The Sentry")
        XCTAssertEqual(collapsed[0].strTimestamp, "2026-01-02T00:00:00")
        XCTAssertEqual(collapsed[0].endDate, "2026-01-05T00:00:00")
        // The name now matches ESPN's own event name, which is how the merge finds it.
        XCTAssertEqual(collapsed[0].strHomeTeam.lowercased(), "the sentry")
    }

    /// "Final Round" has to sort last however many numbered rounds there were.
    func testFinalRoundSortsLastEvenWhenListedFirst() {
        let collapsed = ScheduleUpdateJob.collapseGolfRounds(sentry.reversed())
        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed[0].strTimestamp, "2026-01-02T00:00:00")
        XCTAssertEqual(collapsed[0].endDate, "2026-01-05T00:00:00")
    }

    func testSameTournamentInDifferentYearsStaysSeparate() {
        let twoSeasons = sentry + [
            round("5", "The Sentry Round 1", "2027-01-07T00:00:00"),
            round("6", "The Sentry Final Round", "2027-01-10T00:00:00"),
        ]
        let collapsed = ScheduleUpdateJob.collapseGolfRounds(twoSeasons)
        XCTAssertEqual(collapsed.count, 2)
        XCTAssertEqual(collapsed.map { $0.endDate }, ["2026-01-05T00:00:00", "2027-01-10T00:00:00"])
    }

    /// Rows with no round suffix are ordinary one-off events — left untouched, and in place.
    func testRowsWithoutRoundsArePreserved() {
        let mixed = [round("a", "Puerto Rico Open", "2026-03-05T00:00:00")]
            + sentry
            + [round("b", "Ryder Cup 2026 Day 1", "2026-09-25T00:00:00")]
        let collapsed = ScheduleUpdateJob.collapseGolfRounds(mixed)
        XCTAssertEqual(collapsed.map { $0.strHomeTeam },
                       ["Puerto Rico Open", "The Sentry", "Ryder Cup 2026 Day 1"])
        XCTAssertNil(collapsed[0].endDate)
    }

    func testEmptyInputIsEmpty() {
        XCTAssertTrue(ScheduleUpdateJob.collapseGolfRounds([]).isEmpty)
    }
}
