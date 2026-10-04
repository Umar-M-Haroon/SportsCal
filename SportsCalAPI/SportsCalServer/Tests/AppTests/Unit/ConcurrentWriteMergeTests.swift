@testable import App
import XCTest
import SportsCalModel

/// A slow job (ESPNFetchJob / ESPNSoccerJob) must not roll back scores the fast
/// LiveTicker published while it was running.
final class ConcurrentWriteMergeTests: XCTestCase {

    private func soccer(_ id: String, _ home: String, _ away: String, status: String = "in", progress: String? = nil) -> Game {
        TestGameFactory.make(
            idEvent: id, idLeague: "4328", strHomeTeam: "H\(id)", strAwayTeam: "A\(id)",
            intHomeScore: home, intAwayScore: away, strStatus: status, strProgress: progress
        )
    }

    func test_tickerGoalDuringRebuild_isKept() {
        let baseline = LiveScore(soccer: LiveEvent(events: [soccer("1", "0", "0")]))
        // Ticker saw the goal after we read the baseline.
        let current = LiveScore(soccer: LiveEvent(events: [soccer("1", "1", "0", progress: "34'")]))
        // Our rebuild came from the stale soccer cache.
        let ours = LiveScore(soccer: LiveEvent(events: [soccer("1", "0", "0", progress: "30'")]))

        let r = LiveMerge.preservingConcurrentUpdates(ours: ours, baseline: baseline, current: current)

        XCTAssertEqual(r.liveScore.soccer?.events.first?.intHomeScore, "1")
        XCTAssertEqual(r.liveScore.soccer?.events.first?.strProgress, "34'")
        XCTAssertEqual(r.preserved, ["1"])
    }

    func test_oursFurtherAlong_wins() {
        let baseline = LiveScore(soccer: LiveEvent(events: [soccer("1", "0", "0")]))
        let current = LiveScore(soccer: LiveEvent(events: [soccer("1", "1", "0")]))
        let ours = LiveScore(soccer: LiveEvent(events: [soccer("1", "2", "0")]))

        let r = LiveMerge.preservingConcurrentUpdates(ours: ours, baseline: baseline, current: current)

        XCTAssertEqual(r.liveScore.soccer?.events.first?.intHomeScore, "2")
        XCTAssertTrue(r.preserved.isEmpty)
    }

    func test_oursFinal_beatsConcurrentInProgress() {
        let baseline = LiveScore(soccer: LiveEvent(events: [soccer("1", "0", "0")]))
        let current = LiveScore(soccer: LiveEvent(events: [soccer("1", "1", "1")]))
        let ours = LiveScore(soccer: LiveEvent(events: [soccer("1", "1", "1", status: "post")]))

        let r = LiveMerge.preservingConcurrentUpdates(ours: ours, baseline: baseline, current: current)

        XCTAssertEqual(r.liveScore.soccer?.events.first?.strStatus, "post")
    }

    func test_untouchedGames_andNewGames_areOurs() {
        let baseline = LiveScore(soccer: LiveEvent(events: [soccer("1", "0", "0")]))
        let current = baseline // nobody wrote
        let ours = LiveScore(
            nba: LiveEvent(events: [TestGameFactory.make(idEvent: "9", strHomeTeam: "X", strAwayTeam: "Y")]),
            soccer: LiveEvent(events: [soccer("1", "0", "0", progress: "40'")])
        )

        let r = LiveMerge.preservingConcurrentUpdates(ours: ours, baseline: baseline, current: current)

        XCTAssertEqual(r.liveScore, ours)
        XCTAssertTrue(r.preserved.isEmpty)
    }

    func test_noCurrent_returnsOurs() {
        let ours = LiveScore(soccer: LiveEvent(events: [soccer("1", "0", "0")]))
        XCTAssertEqual(LiveMerge.preservingConcurrentUpdates(ours: ours, baseline: nil, current: nil).liveScore, ours)
    }

    // MARK: - ESPNSoccerJob board merge

    private func event(_ id: String, state: String, home: String, away: String) -> Event {
        let status = Status(clock: nil, displayClock: nil, period: nil, type: StatusType(id: "1", state: state, completed: state == "post"))
        let competition = Competition(
            id: id, uid: id, date: "2026-10-04T00:00Z",
            competitors: [
                Competitor(id: "h", uid: "h", type: "team", homeAway: "home", score: home),
                Competitor(id: "a", uid: "a", type: "team", homeAway: "away", score: away),
            ],
            status: status
        )
        return Event(id: id, uid: id, date: "2026-10-04T00:00Z", name: "e\(id)", competitions: [competition], status: status)
    }

    private func board(_ events: [Event]) -> Scoreboard {
        Scoreboard(leagues: [], day: Day(date: "2026-10-04"), events: events)
    }

    private func score(_ boards: [Leagues: Scoreboard], _ league: Leagues, _ id: String) -> String? {
        boards[league]?.events.first { $0.id == id }?.competitions?.first?.competitors?.first?.score
    }

    func test_soccerBoards_unfetchedLeague_keepsCurrent() {
        let current: [Leagues: Scoreboard] = [
            .La_Liga: board([event("L1", state: "in", home: "2", away: "0")]),
        ]
        let fetched: [Leagues: Scoreboard] = [
            .English_Premier_League: board([event("E1", state: "in", home: "0", away: "0")]),
        ]
        let merged = ESPNSoccerJob.mergeFetchedBoards(fetched: fetched, current: current)
        XCTAssertEqual(score(merged, .La_Liga, "L1"), "2", "the ticker's copy of a league we didn't fetch survives")
        XCTAssertNotNil(merged[.English_Premier_League])
    }

    func test_soccerBoards_cachedEventFurtherAlong_isKept() {
        let current: [Leagues: Scoreboard] = [
            .English_Premier_League: board([
                event("E1", state: "in", home: "1", away: "0"),
                event("E2", state: "in", home: "0", away: "0"),
            ]),
        ]
        let fetched: [Leagues: Scoreboard] = [
            .English_Premier_League: board([
                event("E1", state: "in", home: "0", away: "0"),  // older than the ticker's
                event("E2", state: "in", home: "0", away: "1"),  // newer
            ]),
        ]
        let merged = ESPNSoccerJob.mergeFetchedBoards(fetched: fetched, current: current)
        XCTAssertEqual(score(merged, .English_Premier_League, "E1"), "1", "scores never go backwards")
        XCTAssertEqual(merged[.English_Premier_League]?.events.first { $0.id == "E2" }?.competitions?.first?.competitors?.last?.score, "1")
    }
}
