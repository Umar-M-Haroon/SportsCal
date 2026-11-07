import XCTest
@testable import App
import SportsCalModel

/// statsapi status text in ESPN's format, and doubleheaders that share a teams+day
/// match key in the live merge.
final class MLBDoubleheaderTests: XCTestCase {

    private func mlb(_ id: String, home: String, away: String, status: String, start: String) -> Game {
        TestGameFactory.make(
            idEvent: id, idLeague: "4424",
            strHomeTeam: "Kansas City Royals", strAwayTeam: "Cleveland Guardians",
            intHomeScore: home, intAwayScore: away, strStatus: status,
            strTimestamp: start, isoDate: nil
        )
    }

    // MARK: Doubleheader merge

    func testDoubleheaderGameTwoTakesItsOwnScore() {
        // Game 1 is over; game 2 is live. statsapi lists both, game 1 last.
        let cached = TestGameFactory.liveScore(mlb: [
            mlb("espn-g1", home: "4", away: "3", status: "post", start: "2025-07-26T18:40:00Z"),
            mlb("espn-g2", home: "0", away: "1", status: "in", start: "2025-07-26T23:15:00Z"),
        ])
        let fresh = [
            mlb("mlb-2", home: "2", away: "1", status: "in", start: "2025-07-26T23:15:00Z"),
            mlb("mlb-1", home: "4", away: "3", status: "post", start: "2025-07-26T18:40:00Z"),
        ]
        let result = LiveMerge.overlay(cached: cached, sport: .mlb, fresh: fresh, strategy: .teamsAndDay)
        let gameTwo = result.liveScore.mlb!.events[1]
        XCTAssertEqual(gameTwo.strStatus, "in")
        XCTAssertEqual(gameTwo.intHomeScore, "2")
    }

    func testDoubleheaderMatchesByGameNumberFirst() {
        var snapshot = mlb("espn-g2", home: "0", away: "0", status: "in", start: "2025-07-26T18:40:00Z")
        snapshot.scoreboardExtras = ScoreboardExtras(homeHits: 5, doubleheaderGame: 2)
        var one = mlb("mlb-1", home: "9", away: "9", status: "post", start: "2025-07-26T18:40:00Z")
        one.scoreboardExtras = ScoreboardExtras(doubleheaderGame: 1)
        var two = mlb("mlb-2", home: "1", away: "0", status: "in", start: "2025-07-26T18:40:00Z")
        two.scoreboardExtras = ScoreboardExtras(doubleheaderGame: 2)
        let picked = LiveMerge.bestMatch(for: snapshot, among: [two, one])
        XCTAssertEqual(picked?.idEvent, "mlb-2")

        // A partial source's extras never replace ESPN's R/H/E.
        let result = LiveMerge.overlay(cached: TestGameFactory.liveScore(mlb: [snapshot]), sport: .mlb,
                                       fresh: [one, two], strategy: .teamsAndDay)
        XCTAssertEqual(result.liveScore.mlb!.events[0].homeHits, 5)
        XCTAssertEqual(result.liveScore.mlb!.events[0].intHomeScore, "1")
    }

    // MARK: statsapi status

    func testInningTextMatchesESPN() {
        XCTAssertEqual(MLBGame.inningText(inning: 9, state: "Bottom", ordinal: "9th"), "Bot 9th")
        XCTAssertEqual(MLBGame.inningText(inning: 3, state: "Middle", ordinal: nil), "Mid 3rd")
        XCTAssertEqual(MLBGame.inningText(inning: 11, state: "Top", ordinal: nil), "Top 11th")
        XCTAssertEqual(MLBGame.inningText(inning: 2, state: "End", ordinal: nil), "End 2nd")
    }

    func testDelaysAndSuspensions() {
        let delay = MLBGame.espnStyleStatus(abstract: "Live", detailed: "Delayed: Rain", inning: 5, inningState: "Top", inningOrdinal: "5th")
        XCTAssertEqual(delay, .init(strStatus: "in", progress: "Rain Delay", completed: false))
        let suspended = MLBGame.espnStyleStatus(abstract: "Final", detailed: "Suspended: Rain", inning: 6, inningState: "Top", inningOrdinal: nil)
        XCTAssertEqual(suspended?.completed, false)
        XCTAssertEqual(suspended?.progress, "Suspended")
        let final = MLBGame.espnStyleStatus(abstract: "Final", detailed: "Final", inning: 9, inningState: "End", inningOrdinal: nil)
        XCTAssertEqual(final, .init(strStatus: "post", progress: nil, completed: true))
        XCTAssertNil(MLBGame.espnStyleStatus(abstract: "Preview", detailed: "Delayed Start: Rain", inning: nil, inningState: nil, inningOrdinal: nil))
    }
}
