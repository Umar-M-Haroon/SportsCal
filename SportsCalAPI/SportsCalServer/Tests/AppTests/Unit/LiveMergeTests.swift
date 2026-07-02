import XCTest
@testable import App
import SportsCalModel

/// Pins LiveMerge.overlaySoccerInProgress — the fast-path surgical merge used by
/// LiveTicker. Invariants: it overlays fresh scores onto in-progress soccer games
/// matched by idEvent, preserves identity, never adds/removes games, never touches
/// other buckets or upcoming games, and reports exactly which events changed.
final class LiveMergeTests: XCTestCase {

    // EPL idLeague = 4328 (isSoccer true).
    private func soccerGame(
        idEvent: String,
        idHomeTeam: String? = "TSDB-H",
        idAwayTeam: String? = "TSDB-A",
        home: String = "Arsenal",
        away: String = "Chelsea",
        homeScore: String?,
        awayScore: String?,
        status: String,
        progress: String? = nil
    ) -> Game {
        TestGameFactory.make(
            idEvent: idEvent, idLeague: "4328",
            idHomeTeam: idHomeTeam, idAwayTeam: idAwayTeam,
            strHomeTeam: home, strAwayTeam: away,
            intHomeScore: homeScore, intAwayScore: awayScore,
            strStatus: status, strProgress: progress,
            strTimestamp: "2026-06-27T18:00:00", isoDate: nil
        )
    }

    // MARK: - Happy path

    func testOverlaysFreshScoreOntoInProgressGameAndReportsChange() {
        let cached = TestGameFactory.liveScore(soccer: [
            soccerGame(idEvent: "E1", homeScore: "0", awayScore: "0", status: "in", progress: "44'")
        ])
        // Same idEvent, fresh ESPN copy with a goal + advanced clock. ESPN team IDs differ
        // (untranslated) — the overlay must keep the cached TSDB team IDs.
        let fresh = soccerGame(
            idEvent: "E1", idHomeTeam: "ESPN-359", idAwayTeam: "ESPN-363",
            homeScore: "1", awayScore: "0", status: "in", progress: "46'"
        )

        let result = LiveMerge.overlaySoccerInProgress(cached: cached, fresh: [fresh])

        XCTAssertEqual(result.changedEventIDs, ["E1"])
        let game = result.liveScore.soccer!.events[0]
        // Fresh dynamic fields applied
        XCTAssertEqual(game.intHomeScore, "1")
        XCTAssertEqual(game.intAwayScore, "0")
        XCTAssertEqual(game.strProgress, "46'")
        // Cached identity preserved (team IDs NOT replaced by the ESPN copy's)
        XCTAssertEqual(game.idEvent, "E1")
        XCTAssertEqual(game.idHomeTeam, "TSDB-H")
        XCTAssertEqual(game.idAwayTeam, "TSDB-A")
    }

    func testStatusTransitionInToPostCountsAsChange() {
        let cached = TestGameFactory.liveScore(soccer: [
            soccerGame(idEvent: "E1", homeScore: "2", awayScore: "1", status: "in", progress: "90'")
        ])
        let fresh = soccerGame(idEvent: "E1", homeScore: "2", awayScore: "1", status: "post")

        let result = LiveMerge.overlaySoccerInProgress(cached: cached, fresh: [fresh])

        XCTAssertEqual(result.changedEventIDs, ["E1"])
        XCTAssertEqual(result.liveScore.soccer!.events[0].strStatus, "post")
    }

    // MARK: - No-op cases

    func testNoScoreChangeReportsNothingChanged() {
        let cached = TestGameFactory.liveScore(soccer: [
            soccerGame(idEvent: "E1", homeScore: "1", awayScore: "1", status: "in", progress: "70'")
        ])
        let fresh = soccerGame(idEvent: "E1", homeScore: "1", awayScore: "1", status: "in", progress: "71'")

        let result = LiveMerge.overlaySoccerInProgress(cached: cached, fresh: [fresh])

        XCTAssertTrue(result.changedEventIDs.isEmpty)
    }

    func testUpcomingGameIsNeverOverlaid() {
        // A "pre" game must not be touched even if a fresh copy with the same idEvent exists.
        let cached = TestGameFactory.liveScore(soccer: [
            soccerGame(idEvent: "E1", homeScore: "0", awayScore: "0", status: "pre")
        ])
        let fresh = soccerGame(idEvent: "E1", homeScore: "3", awayScore: "0", status: "in")

        let result = LiveMerge.overlaySoccerInProgress(cached: cached, fresh: [fresh])

        XCTAssertTrue(result.changedEventIDs.isEmpty)
        let game = result.liveScore.soccer!.events[0]
        XCTAssertEqual(game.intHomeScore, "0")
        XCTAssertEqual(game.strStatus, "pre")
    }

    func testFreshGameWithNoCachedMatchIsNotAdded() {
        let cached = TestGameFactory.liveScore(soccer: [
            soccerGame(idEvent: "E1", homeScore: "0", awayScore: "0", status: "in")
        ])
        // Fresh game ESPN knows about but the snapshot doesn't — must not be appended.
        let fresh = soccerGame(idEvent: "E2", homeScore: "1", awayScore: "1", status: "in")

        let result = LiveMerge.overlaySoccerInProgress(cached: cached, fresh: [fresh])

        XCTAssertEqual(result.liveScore.soccer!.events.count, 1)
        XCTAssertEqual(result.liveScore.soccer!.events[0].idEvent, "E1")
        XCTAssertTrue(result.changedEventIDs.isEmpty)
    }

    func testNilSoccerBucketIsNoOp() {
        let cached = TestGameFactory.liveScore(nba: [
            TestGameFactory.make(idEvent: "N1", strHomeTeam: "Lakers", strAwayTeam: "Celtics", strStatus: "in")
        ])
        let fresh = soccerGame(idEvent: "E1", homeScore: "1", awayScore: "0", status: "in")

        let result = LiveMerge.overlaySoccerInProgress(cached: cached, fresh: [fresh])

        XCTAssertTrue(result.changedEventIDs.isEmpty)
        XCTAssertNil(result.liveScore.soccer)
    }

    // MARK: - Isolation of other buckets

    // MARK: - Cross-source overlay (teamsAndDay, e.g. FIFA → ESPN snapshot)

    private func wcGame(idEvent: String, home: String, away: String,
                        homeScore: String?, awayScore: String?, status: String) -> Game {
        TestGameFactory.make(
            idEvent: idEvent, idLeague: "4429",
            strHomeTeam: home, strAwayTeam: away,
            intHomeScore: homeScore, intAwayScore: awayScore,
            strStatus: status, strTimestamp: "2026-06-28T02:00:00", isoDate: nil
        )
    }

    func testTeamsAndDayOverlayMatchesAcrossSources() {
        // Snapshot game from ESPN (idEvent "760484"); fresh game from FIFA (idEvent "fifa-…").
        // They share no id namespace — must still match by team + day.
        let cached = TestGameFactory.liveScore(soccer: [
            wcGame(idEvent: "760484", home: "Algeria", away: "Austria",
                   homeScore: "1", awayScore: "1", status: "in")
        ])
        let fresh = wcGame(idEvent: "fifa-400021497", home: "Algeria", away: "Austria",
                           homeScore: "2", awayScore: "1", status: "in")

        let result = LiveMerge.overlaySoccer(cached: cached, fresh: [fresh], strategy: .teamsAndDay)

        XCTAssertEqual(result.changedEventIDs, ["760484"]) // reports the SNAPSHOT id, not FIFA's
        let game = result.liveScore.soccer!.events[0]
        XCTAssertEqual(game.intHomeScore, "2")
        XCTAssertEqual(game.idEvent, "760484") // snapshot identity preserved
    }

    func testTeamsAndDayCountryAliasMatches() {
        // ESPN "USA" vs FIFA "United States" must reconcile via the alias map.
        let cached = TestGameFactory.liveScore(soccer: [
            wcGame(idEvent: "S1", home: "USA", away: "Wales", homeScore: "0", awayScore: "0", status: "in")
        ])
        let fresh = wcGame(idEvent: "fifa-1", home: "United States", away: "Wales",
                           homeScore: "1", awayScore: "0", status: "in")

        let result = LiveMerge.overlaySoccer(cached: cached, fresh: [fresh], strategy: .teamsAndDay)

        XCTAssertEqual(result.changedEventIDs, ["S1"])
        XCTAssertEqual(result.liveScore.soccer!.events[0].intHomeScore, "1")
    }

    func testTeamsAndDayDifferentDayDoesNotMatch() {
        let cached = TestGameFactory.liveScore(soccer: [
            wcGame(idEvent: "S1", home: "Algeria", away: "Austria", homeScore: "0", awayScore: "0", status: "in")
        ])
        // Same teams, different day — must NOT match (avoids cross-fixture bleed).
        let fresh = TestGameFactory.make(
            idEvent: "fifa-1", idLeague: "4429", strHomeTeam: "Algeria", strAwayTeam: "Austria",
            intHomeScore: "5", intAwayScore: "0", strStatus: "in",
            strTimestamp: "2026-07-01T02:00:00", isoDate: nil
        )

        let result = LiveMerge.overlaySoccer(cached: cached, fresh: [fresh], strategy: .teamsAndDay)

        XCTAssertTrue(result.changedEventIDs.isEmpty)
        XCTAssertEqual(result.liveScore.soccer!.events[0].intHomeScore, "0")
    }

    func testOtherSportBucketsPassThroughUntouched() {
        let nba = TestGameFactory.make(idEvent: "N1", strHomeTeam: "Lakers", strAwayTeam: "Celtics",
                                       intHomeScore: "88", intAwayScore: "84", strStatus: "in")
        let cached = TestGameFactory.liveScore(nba: [nba], soccer: [
            soccerGame(idEvent: "E1", homeScore: "0", awayScore: "0", status: "in")
        ])
        let fresh = soccerGame(idEvent: "E1", homeScore: "1", awayScore: "0", status: "in")

        let result = LiveMerge.overlaySoccerInProgress(cached: cached, fresh: [fresh])

        // NBA bucket identical to input.
        XCTAssertEqual(result.liveScore.nba?.events, cached.nba?.events)
    }

    // MARK: - Generic per-sport overlay (MLB bucket)

    func testOverlayMLBBucketByTeamsAndDay() {
        let cachedMLB = TestGameFactory.make(
            idEvent: "espn-401", idLeague: "4424",
            strHomeTeam: "Detroit Tigers", strAwayTeam: "Houston Astros",
            intHomeScore: "3", intAwayScore: "2", strStatus: "in",
            strTimestamp: "2026-06-27T17:10:00", isoDate: nil
        )
        let cached = TestGameFactory.liveScore(mlb: [cachedMLB])
        // Fresh from statsapi (idEvent "mlb-…", different namespace), score advanced.
        let fresh = TestGameFactory.make(
            idEvent: "mlb-824257", idLeague: "4424",
            strHomeTeam: "Detroit Tigers", strAwayTeam: "Houston Astros",
            intHomeScore: "6", intAwayScore: "8", strStatus: "in",
            strTimestamp: "2026-06-27T17:10:00", isoDate: nil
        )

        let result = LiveMerge.overlay(cached: cached, sport: .mlb, fresh: [fresh], strategy: .teamsAndDay)

        XCTAssertEqual(result.changedEventIDs, ["espn-401"]) // snapshot id, not statsapi's
        let g = result.liveScore.mlb!.events[0]
        XCTAssertEqual(g.intHomeScore, "6")
        XCTAssertEqual(g.intAwayScore, "8")
        XCTAssertEqual(g.idEvent, "espn-401") // identity preserved
    }
}
