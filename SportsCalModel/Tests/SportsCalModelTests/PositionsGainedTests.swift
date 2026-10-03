import XCTest
@testable import SportsCalModel

final class PositionsGainedTests: XCTestCase {
    private func entry(_ name: String, _ position: Int) -> LeaderboardEntry {
        LeaderboardEntry(name: name, score: "P\(position)", position: position)
    }

    func testRaceComparesAgainstQualifying() {
        let quali = EventSession(sessionType: "Qual", sessionName: "Qualifying", status: "post",
                                 leaderboard: [entry("A", 1), entry("B", 2), entry("C", 3)])
        let race = EventSession(sessionType: "Race", sessionName: "Race", status: "in",
                                leaderboard: [entry("C", 1), entry("A", 2), entry("B", 3)])
        let gained = [quali, race].positionsGainedVsQualifying(in: race)
        XCTAssertEqual(gained, ["C": 2, "A": -1, "B": -1])
    }

    func testSprintUsesSprintQualifyingNotQualifying() {
        let ss = EventSession(sessionType: "SS", sessionName: "SS", status: "post",
                              leaderboard: [entry("A", 2), entry("B", 1)])
        let quali = EventSession(sessionType: "Qual", sessionName: "Qualifying", status: "post",
                                 leaderboard: [entry("A", 1), entry("B", 2)])
        let sprint = EventSession(sessionType: "SR", sessionName: "SR", status: "post",
                                  leaderboard: [entry("A", 1), entry("B", 2)])
        XCTAssertEqual([ss, sprint, quali].positionsGainedVsQualifying(in: sprint), ["A": 1, "B": -1])
    }

    func testEmptyUntilQualifyingFinishes() {
        let quali = EventSession(sessionType: "Qual", sessionName: "Qualifying", status: "in",
                                 leaderboard: [entry("A", 1)])
        let race = EventSession(sessionType: "Race", sessionName: "Race", status: "pre", leaderboard: [entry("A", 1)])
        XCTAssertTrue([quali, race].positionsGainedVsQualifying(in: race).isEmpty)
    }

    func testPracticeHasNoGridSession() {
        let fp1 = EventSession(sessionType: "FP1", sessionName: "Free Practice 1", status: "post")
        XCTAssertNil([fp1].gridSession(for: fp1))
    }
}
