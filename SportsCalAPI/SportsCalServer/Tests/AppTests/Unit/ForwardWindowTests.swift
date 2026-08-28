import XCTest
@testable import App
import SportsCalModel

/// Covers the seams the Aug-2026 reliability sweep added around the ESPN forward
/// schedule window — the pieces that are pure and therefore cheap to pin.
final class ForwardWindowTests: XCTestCase {

    private func game(_ id: String, home: String = "A", away: String = "B") -> Game {
        TestGameFactory.make(idEvent: id, strHomeTeam: home, strAwayTeam: away)
    }

    // MARK: - Cross-source dedup

    /// `LiveScore.merging` is a plain concatenation, so the live board and the forward
    /// window can each carry the same fixture. Without this dedup a game TheSportsDB
    /// hasn't published yet gets appended to the schedule twice.
    func testDedupCollapsesSameEventAcrossBuckets() {
        let score = LiveScore(
            nba: LiveEvent(events: [game("401"), game("402"), game("401")]),
            mlb: LiveEvent(events: [game("500"), game("500"), game("500")])
        )
        let deduped = ESPNFetchJob.dedupedByEventID(score)
        XCTAssertEqual(deduped.nba?.events.map(\.idEvent), ["401", "402"])
        XCTAssertEqual(deduped.mlb?.events.count, 1)
    }

    /// Distinct events must survive — dedup keys on id, never on teams, because the same
    /// two teams legitimately meet twice on one day (doubleheaders).
    func testDedupKeepsDistinctEventsWithSameTeams() {
        let score = LiveScore(mlb: LiveEvent(events: [
            game("401", home: "Yankees", away: "Red Sox"),
            game("402", home: "Yankees", away: "Red Sox")
        ]))
        XCTAssertEqual(ESPNFetchJob.dedupedByEventID(score).mlb?.events.count, 2)
    }

    func testDedupPreservesEmptyAndNilBuckets() {
        let deduped = ESPNFetchJob.dedupedByEventID(LiveScore(nba: LiveEvent(events: [])))
        XCTAssertEqual(deduped.nba?.events.count, 0)
        XCTAssertNil(deduped.mlb)
    }

    // MARK: - Concurrency bound

    /// A regression to an unbounded fan-out would fire `daysAhead` requests at ESPN at
    /// once and trip its global 429 breaker, which halts ALL ESPN traffic.
    func testForwardWindowConcurrencyStaysBounded() {
        XCTAssertGreaterThan(ESPNFetchJob.forwardWindowConcurrency, 0)
        XCTAssertLessThanOrEqual(ESPNFetchJob.forwardWindowConcurrency, 8,
                                 "raising this materially increases the burst rate against ESPN")
    }

    // MARK: - Tennis day keys

    /// ESPN keys boards to US Eastern. Formatting in UTC meant that between 00:00Z and
    /// ~05:00Z (evening ET) we asked for ESPN's *tomorrow* — blanking live tennis during
    /// US prime time, which is exactly when US Open night sessions run.
    func testTennisDayKeysUseEasternNotUTC() {
        // 2026-08-28T02:30Z is still 2026-08-27 in New York.
        let formatter = ISO8601DateFormatter()
        let instant = formatter.date(from: "2026-08-28T02:30:00Z")!
        let keys = ESPNTennisJob.dayKeys(now: instant)
        XCTAssertEqual(keys.first, 20260827, "UTC would have given 20260828 and missed the night session")
    }

    /// Today plus tomorrow, so a match running past ET midnight stays covered.
    func testTennisDayKeysCoverTheDayBoundary() {
        let formatter = ISO8601DateFormatter()
        let instant = formatter.date(from: "2026-08-28T02:30:00Z")!
        XCTAssertEqual(ESPNTennisJob.dayKeys(now: instant), [20260827, 20260828])
    }
}
