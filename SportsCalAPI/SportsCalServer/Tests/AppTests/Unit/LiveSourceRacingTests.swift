import XCTest
@testable import App
import SportsCalModel

/// Pins the multi-source fast path: several sources race for one game, the furthest-along
/// copy wins (`LiveMerge.shouldAccept`), a lagging source never rolls a game back, an
/// admin pin overrides the race, and LiveSourceStats credits whoever saw a change first.
final class LiveSourceRacingTests: XCTestCase {

    // NBA idLeague = 4387 (countdown clock).
    private func nba(
        _ id: String = "E1",
        home: String = "2", away: String = "0",
        status: String = "in",
        period: Int? = 2, clock: Double? = 300
    ) -> Game {
        var game = TestGameFactory.make(
            idEvent: id, idLeague: "4387", strHomeTeam: "Knicks", strAwayTeam: "Celtics",
            intHomeScore: home, intAwayScore: away, strStatus: status
        )
        if let period { game.situation = GameSituation(period: period, clock: clock) }
        return game
    }

    private func race(_ source: String, forced: [String: String] = [:]) -> LiveMerge.RaceOptions {
        LiveMerge.RaceOptions(source: source, forcedSources: forced)
    }

    // MARK: - shouldAccept

    func testLaterClockWinsEvenWithLowerScore() {
        // A basket taken off the board 20s later is a correction, not staleness.
        XCTAssertTrue(LiveMerge.shouldAccept(nba(home: "0", clock: 280), over: nba(home: "2", clock: 300)))
    }

    func testEarlierClockLosesEvenWithHigherScore() {
        XCTAssertFalse(LiveMerge.shouldAccept(nba(home: "4", clock: 320), over: nba(home: "2", clock: 300)))
    }

    func testLaterPeriodWins() {
        XCTAssertTrue(LiveMerge.shouldAccept(nba(period: 3, clock: 720), over: nba(period: 2, clock: 1)))
    }

    func testSameMomentKeepsTheHigherScore() {
        XCTAssertFalse(LiveMerge.shouldAccept(nba(home: "2"), over: nba(home: "4")))
        XCTAssertTrue(LiveMerge.shouldAccept(nba(home: "4"), over: nba(home: "2")))
        XCTAssertTrue(LiveMerge.shouldAccept(nba(home: "2"), over: nba(home: "2")))
    }

    func testLaterStatusWinsAndEarlierLoses() {
        XCTAssertTrue(LiveMerge.shouldAccept(nba(status: "post", period: nil), over: nba()))
        XCTAssertFalse(LiveMerge.shouldAccept(nba(status: "in"), over: nba(status: "post", period: nil)))
    }

    func testUnknownClockDoesNotReadAsEndOfPeriod() {
        // The overlay clears a stale clock when a clockless source moves the score. That
        // copy must not then outrank a source that knows the clock.
        let snapshot = nba(home: "4", clock: nil)
        XCTAssertTrue(LiveMerge.shouldAccept(nba(home: "4", clock: 250), over: snapshot))
    }

    func testWithoutProgressOnlyAHigherScoreWins() {
        let withClock = nba(home: "2")
        XCTAssertFalse(LiveMerge.shouldAccept(nba(home: "2", period: nil), over: withClock))
        XCTAssertTrue(LiveMerge.shouldAccept(nba(home: "4", period: nil), over: withClock))
        // Nothing to protect: a game only a clockless source covers keeps updating.
        XCTAssertTrue(LiveMerge.shouldAccept(nba(home: "2", period: nil), over: nba(home: "2", period: nil)))
    }

    func testBaseballOrdersByHalfInningThenOuts() {
        func mlb(_ half: GameSituation.InningHalf, outs: Int, inning: Int = 5) -> Game {
            var game = TestGameFactory.make(idEvent: "M1", idLeague: "4424", strHomeTeam: "Mets", strAwayTeam: "Braves", strStatus: "in")
            game.situation = GameSituation(period: inning, inningHalf: half, outs: outs)
            return game
        }
        XCTAssertTrue(LiveMerge.shouldAccept(mlb(.bottom, outs: 0), over: mlb(.top, outs: 2)))
        XCTAssertTrue(LiveMerge.shouldAccept(mlb(.top, outs: 2), over: mlb(.top, outs: 1)))
        XCTAssertFalse(LiveMerge.shouldAccept(mlb(.top, outs: 2, inning: 6), over: mlb(.bottom, outs: 0, inning: 6)))
    }

    func testSoccerClockCountsUp() {
        func soccer(_ clock: Double) -> Game {
            var game = TestGameFactory.make(idEvent: "S1", idLeague: "4328", strHomeTeam: "Arsenal", strAwayTeam: "Chelsea", strStatus: "in")
            game.situation = GameSituation(period: 1, clock: clock)
            return game
        }
        XCTAssertTrue(LiveMerge.shouldAccept(soccer(2700), over: soccer(2600)))
        XCTAssertFalse(LiveMerge.shouldAccept(soccer(2600), over: soccer(2700)))
    }

    // MARK: - Racing overlay

    func testLaggingSourceDoesNotRollBackAFasterOne() {
        let cached = TestGameFactory.liveScore(nba: [nba(home: "2", clock: 300)])
        // ESPN gets the basket first…
        let fast = LiveMerge.overlay(cached: cached, sport: .basketball, fresh: [nba(home: "4", clock: 280)],
                                     strategy: .eventID, race: race("espn"))
        XCTAssertEqual(fast.changedEventIDs, ["E1"])
        // …then a slower source still shows the old score at an older clock.
        let slow = LiveMerge.overlay(cached: fast.liveScore, sport: .basketball, fresh: [nba(home: "2", clock: 300)],
                                     strategy: .eventID, race: race("nba-cdn"))
        XCTAssertEqual(slow.liveScore.nba?.events.first?.intHomeScore, "4")
        XCTAssertEqual(slow.behindEventIDs, ["E1"])
        XCTAssertTrue(slow.changedEventIDs.isEmpty)
        XCTAssertEqual(slow.observedScores, ["E1": "0-2"])
    }

    func testPinnedSourceWinsAndOthersAreIgnored() {
        let cached = TestGameFactory.liveScore(nba: [nba(home: "4", clock: 280)])
        let pinned = ["E1": "nba-cdn"]
        // ESPN is further along but the game is pinned elsewhere: ignored.
        let espn = LiveMerge.overlay(cached: cached, sport: .basketball, fresh: [nba(home: "6", clock: 200)],
                                     strategy: .eventID, race: race("espn", forced: pinned))
        XCTAssertEqual(espn.liveScore.nba?.events.first?.intHomeScore, "4")
        // The pinned source writes even though it's behind.
        let cdn = LiveMerge.overlay(cached: espn.liveScore, sport: .basketball, fresh: [nba(home: "2", clock: 300)],
                                    strategy: .eventID, race: race("nba-cdn", forced: pinned))
        XCTAssertEqual(cdn.liveScore.nba?.events.first?.intHomeScore, "2")
    }

    func testWithoutRaceOptionsTheOverlayIsUnchanged() {
        // Back-compat: no race options means the fresh copy always wins, as before.
        let cached = TestGameFactory.liveScore(nba: [nba(home: "4", clock: 280)])
        let r = LiveMerge.overlay(cached: cached, sport: .basketball, fresh: [nba(home: "2", clock: 300)], strategy: .eventID)
        XCTAssertEqual(r.liveScore.nba?.events.first?.intHomeScore, "2")
        XCTAssertTrue(r.observedScores.isEmpty)
    }

    // MARK: - Stats

    func testStatsCreditTheFirstSourceAndMeasureTheFollowersLag() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var stats = LiveSourceStats(since: t0)
        // Both sources see the game at 0-2 (first look: not a change).
        stats.record(source: "espn", observed: ["E1": "0-2"], behindCount: 0, now: t0)
        stats.record(source: "nba-cdn", observed: ["E1": "0-2"], behindCount: 0, now: t0)
        // The official feed has the basket 5s before ESPN.
        stats.record(source: "nba-cdn", observed: ["E1": "0-4"], behindCount: 0, now: t0 + 5)
        stats.record(source: "espn", observed: ["E1": "0-2"], behindCount: 1, now: t0 + 5)
        stats.record(source: "espn", observed: ["E1": "0-4"], behindCount: 0, now: t0 + 10)

        XCTAssertEqual(stats.sources["nba-cdn"]?.wins, 1)
        XCTAssertEqual(stats.sources["espn"]?.follows, 1)
        XCTAssertEqual(stats.sources["espn"]?.averageLagSeconds, 5)
        XCTAssertEqual(stats.sources["espn"]?.behind, 1)
        XCTAssertEqual(stats.recent.first?.first, "nba-cdn")
        XCTAssertEqual(stats.recent.first?.followers["espn"], 5)
    }

    func testUncontestedChangesAreNotWins() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var stats = LiveSourceStats(since: t0)
        stats.record(source: "espn", observed: ["E1": "0-0"], behindCount: 0, now: t0)
        stats.record(source: "espn", observed: ["E1": "0-2"], behindCount: 0, now: t0 + 5)
        XCTAssertEqual(stats.sources["espn"]?.wins ?? 0, 0)
        XCTAssertTrue(stats.recent.isEmpty)
    }

    // MARK: - Resolver

    func testEveryFastPathLeagueGetsESPNAndOnlyThose() {
        let resolver = LiveSourceResolver(espn: ESPNLiveSource(), overrides: [.mlb: MLBLiveSource()])
        XCTAssertEqual(resolver.sources(for: .nfl).map(\.name), ["espn"])
        XCTAssertEqual(resolver.sources(for: .mlb).map(\.name), ["espn", "mlb-statsapi"])
        XCTAssertTrue(resolver.sources(for: .pga).isEmpty)
        XCTAssertEqual(Leagues.ncaaf.liveBucket, .nfl)
        XCTAssertEqual(Leagues.wnba.liveBucket, .basketball)
        XCTAssertNil(Leagues.atp.liveBucket)
        // ESPN goes first so the extra sources race what it just wrote.
        XCTAssertEqual(resolver.groups(for: [.mlb, .nfl]).first?.source.name, "espn")
    }
}
