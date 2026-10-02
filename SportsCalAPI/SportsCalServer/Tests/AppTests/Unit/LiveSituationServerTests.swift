import XCTest
@testable import App
import SportsCalModel

/// Server side of the live situation: the fast-path merge, statsapi's count and
/// runners, excitement reaching the schedule, and the team ID lookup behind the
/// team rank card.
final class LiveSituationServerTests: XCTestCase {

    private func mlb(_ id: String, home: String = "3", away: String = "2", status: String = "in", situation: GameSituation? = nil) -> Game {
        var game = TestGameFactory.make(
            idEvent: id, idLeague: "4424",
            strHomeTeam: "Detroit Tigers", strAwayTeam: "Houston Astros",
            intHomeScore: home, intAwayScore: away, strStatus: status,
            strTimestamp: "2026-06-27T17:10:00", isoDate: nil
        )
        game.situation = situation
        return game
    }

    // MARK: - LiveMerge

    func testOverlayTakesFresherSituationAndReportsItSeparately() {
        let cached = TestGameFactory.liveScore(mlb: [mlb("espn-1", situation: GameSituation(period: 5, outs: 0))])
        let fresh = mlb("mlb-9", situation: GameSituation(period: 5, outs: 2, onSecond: true))

        let result = LiveMerge.overlay(cached: cached, sport: .mlb, fresh: [fresh], strategy: .teamsAndDay)

        XCTAssertEqual(result.liveScore.mlb?.events.first?.situation?.outs, 2)
        XCTAssertEqual(result.changedEventIDs, [], "no score change → no push scan")
        XCTAssertEqual(result.situationChangedEventIDs, ["espn-1"], "but the snapshot republishes")
    }

    func testOverlayKeepsCachedSituationWhenSourceHasNone() {
        // NHL/NBA official feeds carry no situation: ESPN's (with win probability) stays.
        let espn = GameSituation(period: 4, clock: 90, homeWinProbability: 0.7)
        let cached = TestGameFactory.liveScore(mlb: [mlb("espn-1", situation: espn)])
        let result = LiveMerge.overlay(cached: cached, sport: .mlb, fresh: [mlb("x", home: "4")], strategy: .teamsAndDay)
        XCTAssertEqual(result.liveScore.mlb?.events.first?.situation, espn)
        XCTAssertEqual(result.situationChangedEventIDs, [])
    }

    func testOverlayClearsSituationWhenGameEnds() {
        let cached = TestGameFactory.liveScore(mlb: [mlb("espn-1", situation: GameSituation(period: 9, outs: 2))])
        let final = mlb("mlb-9", home: "3", away: "2", status: "post")
        let result = LiveMerge.overlay(cached: cached, sport: .mlb, fresh: [final], strategy: .teamsAndDay)
        XCTAssertNil(result.liveScore.mlb?.events.first?.situation)
    }

    // MARK: - statsapi

    func testStatsAPILinescoreBuildsSituation() throws {
        // Shape from statsapi.mlb.com /schedule?hydrate=linescore (captured 2026-09-27),
        // with the inning still open.
        let json = """
        {"currentInning": 9, "inningState": "Bottom", "isTopInning": false, "balls": 1, "strikes": 2, "outs": 1,
         "offense": {"batter": {"id": 701807, "fullName": "Carson Benge"}, "first": {"id": 666182, "fullName": "Bo Bichette"}},
         "defense": {"pitcher": {"id": 680899, "fullName": "Erik Tolman"}}}
        """
        let linescore = try JSONDecoder().decode(MLBLinescore.self, from: Data(json.utf8))
        let s = try XCTUnwrap(linescore.situation)
        XCTAssertEqual(s.inningHalf, .bottom)
        XCTAssertEqual(s.outs, 1)
        XCTAssertEqual(s.onFirst, true)
        XCTAssertEqual(s.onSecond, false)
        XCTAssertEqual(s.batter, "C. Benge")
        XCTAssertEqual(s.pitcher, "E. Tolman")
    }

    // MARK: - Excitement

    func testExcitementIsStampedByEventID() {
        let score = TestGameFactory.liveScore(nba: [
            TestGameFactory.make(idEvent: "a", strHomeTeam: "A", strAwayTeam: "B", strStatus: "post"),
            TestGameFactory.make(idEvent: "b", strHomeTeam: "C", strAwayTeam: "D", strStatus: "post"),
        ])
        let stamped = ESPNFetchJob.applyingExcitement(["a": 91], to: score)
        XCTAssertEqual(stamped.nba?.events.map(\.excitement), [91, nil])
    }

    // MARK: - Team ID lookup

    func testESPNTeamIDInvertsTheBucketedMap() {
        let map = ["nba:2": "134860", "nfl:2": "134918", "nba:20": "134860", "nhl:2": "999"]
        XCTAssertEqual(TeamSeasonStatsResolver.espnTeamID(for: "134860", bucket: "nba", in: map), "2",
                       "lowest of several ESPN IDs, numerically")
        XCTAssertEqual(TeamSeasonStatsResolver.espnTeamID(for: "134918", bucket: "nfl", in: map), "2")
        XCTAssertNil(TeamSeasonStatsResolver.espnTeamID(for: "134918", bucket: "nba", in: map), "never crosses sports")
    }
}
