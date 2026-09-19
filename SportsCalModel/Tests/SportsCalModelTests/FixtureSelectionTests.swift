import XCTest
@testable import SportsCalModel

final class FixtureSelectionTests: XCTestCase {
    private struct Fixture {
        let name: String
        let kickoff: Date?
        var completed = false
    }

    private let hour: TimeInterval = 60 * 60
    private let length: TimeInterval = 2 * 60 * 60
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 2026-09-18 15:00 UTC — leaves room for same-day games on either side.
    private let now = Date(timeIntervalSince1970: 1_789_743_600)

    private func pick(_ games: [Fixture]) -> (name: String, phase: FixturePhase)? {
        FixtureSelection.pick(
            from: games,
            at: now,
            calendar: calendar,
            kickoff: \.kickoff,
            isCompleted: \.completed,
            length: { _ in self.length }
        ).map { ($0.game.name, $0.phase) }
    }

    func testPhaseFollowsTheClock() {
        let kickoff = now
        XCTAssertEqual(FixtureSelection.phase(kickoff: kickoff, isCompleted: false, length: length, at: now - 1), .upcoming)
        XCTAssertEqual(FixtureSelection.phase(kickoff: kickoff, isCompleted: false, length: length, at: now), .likelyLive)
        XCTAssertEqual(FixtureSelection.phase(kickoff: kickoff, isCompleted: false, length: length, at: now + length - 1), .likelyLive)
        XCTAssertEqual(FixtureSelection.phase(kickoff: kickoff, isCompleted: false, length: length, at: now + length), .ended)
    }

    func testCompletedGameEndsEvenInsideTheWindow() {
        XCTAssertEqual(FixtureSelection.phase(kickoff: now - hour, isCompleted: true, length: length, at: now), .ended)
    }

    func testLikelyLiveBeatsUpcoming() {
        let result = pick([
            Fixture(name: "next", kickoff: now + 3 * 24 * hour),
            Fixture(name: "live", kickoff: now - hour),
        ])
        XCTAssertEqual(result?.name, "live")
        XCTAssertEqual(result?.phase, .likelyLive)
    }

    func testUpcomingBeatsTodaysResult() {
        let result = pick([
            Fixture(name: "earlier", kickoff: now - 4 * hour, completed: true),
            Fixture(name: "next", kickoff: now + 3 * 24 * hour),
        ])
        XCTAssertEqual(result?.name, "next")
        XCTAssertEqual(result?.phase, .upcoming)
    }

    func testPicksTheSoonestUpcoming() {
        let result = pick([
            Fixture(name: "later", kickoff: now + 48 * hour),
            Fixture(name: "sooner", kickoff: now + 24 * hour),
        ])
        XCTAssertEqual(result?.name, "sooner")
    }

    func testFallsBackToAGameThatEndedToday() {
        let result = pick([Fixture(name: "earlier", kickoff: now - 4 * hour)])
        XCTAssertEqual(result?.name, "earlier")
        XCTAssertEqual(result?.phase, .ended)
    }

    func testIgnoresResultsFromPreviousDays() {
        XCTAssertNil(pick([Fixture(name: "yesterday", kickoff: now - 24 * hour, completed: true)]))
    }

    func testIgnoresGamesWithoutAKickoff() {
        XCTAssertNil(pick([Fixture(name: "tbd", kickoff: nil)]))
    }

    func testTransitionsOnlyIncludeFutureMoments() {
        XCTAssertEqual(FixtureSelection.transitions(kickoff: now + hour, length: length, after: now),
                       [now + hour, now + hour + length])
        XCTAssertEqual(FixtureSelection.transitions(kickoff: now - hour, length: length, after: now),
                       [now - hour + length])
        XCTAssertEqual(FixtureSelection.transitions(kickoff: now - 3 * hour, length: length, after: now), [])
    }
}
