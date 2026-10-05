import XCTest
@testable import App
import SportsCalModel

/// The `/schedules` ETag must ignore live ticks (the socket carries them) but change
/// whenever a cached copy would be wrong.
final class ScheduleCalendarVersionTests: XCTestCase {
    private func game(id: String = "1", league: String = "4391", status: String? = "pre", progress: String? = nil,
                      home: String? = nil, away: String? = nil, completed: Bool? = false,
                      lastPlay: String? = nil, timestamp: String = "2026-10-04T17:00:00Z",
                      situation: GameSituation? = nil) -> Game {
        var game = Game(idEvent: id, idLeague: league, strHomeTeam: "Lions", strAwayTeam: "Panthers",
                        intHomeScore: home, intAwayScore: away, strStatus: status, strProgress: progress,
                        strTimestamp: timestamp, lastPlay: lastPlay, isCompleted: completed, isoDate: nil)
        game.situation = situation
        return game
    }

    private func version(_ games: [Game]) -> String {
        ScheduleCalendarVersion.combined(ScheduleCalendarVersion.versions(of: LiveScore(nfl: LiveEvent(events: games))))
    }

    func testLiveTicksDoNotChangeTheVersion() {
        let kickoff = version([game(status: "pre")])
        let live1 = version([game(status: "in", progress: "1:34 - 4th", home: "17", away: "20", lastPlay: "Goff pass incomplete")])
        let live2 = version([game(status: "in", progress: "0:40 - 4th", home: "17", away: "23", lastPlay: "Young kneels")])
        XCTAssertEqual(kickoff, live1, "kickoff is on the socket")
        XCTAssertEqual(live1, live2, "clock, score and last play are on the socket")
    }

    func testFinalChangesTheVersion() {
        let live = version([game(status: "in", progress: "0:10 - 4th", home: "17", away: "23")])
        let final = version([game(status: "post", progress: "Final", home: "17", away: "23", completed: true)])
        XCTAssertNotEqual(live, final, "the live snapshot drops finished games, so the schedule must carry the result")
        let corrected = version([game(status: "post", progress: "Final", home: "17", away: "24", completed: true)])
        XCTAssertNotEqual(final, corrected, "a corrected final score must reach cached copies")
    }

    func testCalendarChangesTheVersion() {
        let base = version([game()])
        XCTAssertNotEqual(base, version([game(timestamp: "2026-10-04T20:25:00Z")]), "kickoff moved")
        XCTAssertNotEqual(base, version([game(), game(id: "2")]), "game added")
        XCTAssertNotEqual(base, version([game(status: "Postponed")]), "postponed")
    }

    func testVersionsArePerWireBucket() {
        let college = game(id: "c1", league: "102")
        let nfl = game(id: "n1")
        let before = ScheduleCalendarVersion.versions(of: LiveScore(nfl: LiveEvent(events: [nfl, college])))
        var finishedCollege = college
        finishedCollege = game(id: "c1", league: "102", status: "post", progress: "Final", home: "21", away: "14", completed: true)
        let after = ScheduleCalendarVersion.versions(of: LiveScore(nfl: LiveEvent(events: [nfl, finishedCollege])))
        XCTAssertEqual(before["nfl"], after["nfl"], "a college final leaves the NFL version alone")
        XCTAssertNotEqual(before["ncaaf"], after["ncaaf"])
    }

    func testStableAcrossCalls() {
        let games = [game(), game(id: "2", status: "post", progress: "Final", home: "1", away: "2", completed: true)]
        XCTAssertEqual(version(games), version(games))
        XCTAssertEqual(version(games).count, 32)
    }
}
