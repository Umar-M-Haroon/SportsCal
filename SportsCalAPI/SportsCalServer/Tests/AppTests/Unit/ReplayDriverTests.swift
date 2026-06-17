@testable import App
import XCTest
import SportsCalModel

/// `ReplayDriver.snapshots` is the pure core of the developer "replay a game as live"
/// feature — it turns recorded play-by-play into the `LiveScore` frames the `/replay`
/// WebSocket streams. Pin its invariants: one frame per play, scores climb monotonically,
/// the timeline ends in `post`, and every frame has a non-empty progress label.
final class ReplayDriverTests: XCTestCase {

    private func nbaShell() -> Game {
        Game(
            idEvent: "evt-1",
            idLeague: String(Leagues.nba.rawValue),
            idHomeTeam: "h", idAwayTeam: "a",
            strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            intHomeScore: "0", intAwayScore: "0",
            strStatus: "pre",
            isoDate: nil
        )
    }

    private func play(_ id: String, home: Int?, away: Int?, period: Int?, clock: String?, text: String?) -> Play {
        Play(
            id: id, text: text, scoringPlay: nil,
            awayScore: away, homeScore: home,
            clock: clock.map { Play.PlayClock(displayValue: $0) },
            period: period.map { Play.PlayPeriod(number: $0) },
            type: nil
        )
    }

    func test_snapshots_oneFramePerPlay() {
        let plays = [
            play("1", home: 2, away: 0, period: 1, clock: "11:30", text: "Home bucket"),
            play("2", home: 2, away: 3, period: 1, clock: "10:50", text: "Away three"),
            play("3", home: 4, away: 3, period: 1, clock: "10:10", text: "Home layup"),
        ]
        let frames = ReplayDriver.snapshots(shell: nbaShell(), plays: plays, slot: .nba)
        XCTAssertEqual(frames.count, plays.count)
    }

    func test_snapshots_scoresAreMonotonicAndCarryForward() {
        let plays = [
            play("1", home: 2, away: 0, period: 1, clock: "11:30", text: "Home bucket"),
            play("2", home: nil, away: nil, period: 1, clock: "11:00", text: "Turnover"), // no score change
            play("3", home: 5, away: 3, period: 1, clock: "10:10", text: "And-one"),
        ]
        let frames = ReplayDriver.snapshots(shell: nbaShell(), plays: plays, slot: .nba)
        let homeScores = frames.compactMap { Int($0.nba?.events.first?.intHomeScore ?? "") }
        let awayScores = frames.compactMap { Int($0.nba?.events.first?.intAwayScore ?? "") }
        XCTAssertEqual(homeScores, [2, 2, 5]) // missing score carried forward
        XCTAssertEqual(awayScores, [0, 0, 3])
        // Monotonic non-decreasing.
        XCTAssertEqual(homeScores, homeScores.sorted())
        XCTAssertEqual(awayScores, awayScores.sorted())
    }

    func test_snapshots_lastFrameIsFinal() {
        let plays = [
            play("1", home: 2, away: 0, period: 4, clock: "0:30", text: "Bucket"),
            play("2", home: 2, away: 0, period: 4, clock: "0:00", text: "End of game"),
        ]
        let frames = ReplayDriver.snapshots(shell: nbaShell(), plays: plays, slot: .nba)
        let last = frames.last?.nba?.events.first
        XCTAssertEqual(last?.strStatus, "post")
        XCTAssertEqual(last?.isCompleted, true)
        XCTAssertEqual(last?.strProgress, "Final")
        // Non-final frames are "in".
        XCTAssertEqual(frames.first?.nba?.events.first?.strStatus, "in")
    }

    func test_snapshots_everyFrameHasProgressAndLastPlay() {
        let plays = [
            play("1", home: 2, away: 0, period: 2, clock: "6:43", text: "Jumper"),
            play("2", home: 4, away: 0, period: 2, clock: "0:00", text: "Buzzer beater"),
        ]
        let frames = ReplayDriver.snapshots(shell: nbaShell(), plays: plays, slot: .nba)
        XCTAssertEqual(frames.first?.nba?.events.first?.strProgress, "Q2 6:43")
        XCTAssertEqual(frames.first?.nba?.events.first?.lastPlay, "Jumper")
        for frame in frames {
            let game = frame.nba?.events.first
            XCTAssertFalse((game?.strProgress ?? "").isEmpty)
        }
    }

    func test_snapshots_emptyPlaysYieldsNoFrames() {
        XCTAssertTrue(ReplayDriver.snapshots(shell: nbaShell(), plays: [], slot: .nba).isEmpty)
    }

    func test_slotAndEspnMapping_perSport() {
        XCTAssertEqual(ReplayDriver.slot(for: nbaShell()), .nba)
        XCTAssertEqual(ReplayDriver.espnSportLeague(for: nbaShell())?.sport, "basketball")
        XCTAssertEqual(ReplayDriver.espnSportLeague(for: nbaShell())?.league, "nba")

        let golf = Game(idLeague: String(Leagues.pga.rawValue),
                        strHomeTeam: "x", strAwayTeam: "y", isoDate: nil)
        XCTAssertNil(ReplayDriver.slot(for: golf)) // unsupported sport
    }
}
