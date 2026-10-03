import XCTest
@testable import SportsCalModel

final class F1DriverSeasonTests: XCTestCase {
    private func entry(_ name: String, _ position: Int) -> LeaderboardEntry {
        LeaderboardEntry(name: name, score: "P\(position)", position: position, constructor: "Mercedes")
    }

    private func weekend(_ id: String, day: Int, sessions: [EventSession]) -> Game {
        Game(idEvent: id, strHomeTeam: "GP \(id)", strAwayTeam: "",
             isoDate: Date(timeIntervalSince1970: Double(day) * 86_400), sessions: sessions)
    }

    func testPointsTables() {
        XCTAssertEqual(F1DriverSeason.racePoints(1), 25)
        XCTAssertEqual(F1DriverSeason.racePoints(10), 1)
        XCTAssertEqual(F1DriverSeason.racePoints(11), 0)
        XCTAssertEqual(F1DriverSeason.sprintPoints(1), 8)
        XCTAssertEqual(F1DriverSeason.sprintPoints(8), 1)
        XCTAssertEqual(F1DriverSeason.sprintPoints(9), 0)
    }

    func testBuildsRoundsInDateOrderWithCumulativePoints() {
        let sprintWeekend = weekend("B", day: 20, sessions: [
            EventSession(sessionType: "Qual", sessionName: "Qualifying", status: "post", leaderboard: [entry("Kimi Antonelli", 3)]),
            EventSession(sessionType: "SR", sessionName: "SR", status: "post", leaderboard: [entry("Kimi Antonelli", 2)]),
            EventSession(sessionType: "Race", sessionName: "Race", status: "post", leaderboard: [entry("Kimi Antonelli", 1)]),
        ])
        let normal = weekend("A", day: 10, sessions: [
            // ESPN writes the full name; standings use "Kimi Antonelli" → surname fallback.
            EventSession(sessionType: "Race", sessionName: "Race", status: "post", leaderboard: [entry("Andrea Kimi Antonelli", 4)]),
        ])
        let upcoming = weekend("C", day: 30, sessions: [
            EventSession(sessionType: "Race", sessionName: "Race", status: "pre"),
        ])

        let season = F1DriverSeason(driverName: "Kimi Antonelli", weekends: [sprintWeekend, upcoming, normal])
        XCTAssertEqual(season.rounds.map(\.gameID), ["A", "B"])
        XCTAssertEqual(season.rounds.map(\.points), [12, 25 + 7])
        XCTAssertEqual(season.rounds.map(\.cumulativePoints), [12, 44])
        XCTAssertEqual(season.rounds[1].qualifying, 3)
        XCTAssertEqual(season.rounds[1].sprint, 2)
        XCTAssertEqual(season.wins, 1)
        XCTAssertEqual(season.podiums, 1)
        XCTAssertEqual(season.bestFinish, 1)
        XCTAssertEqual(try XCTUnwrap(season.averageFinish), 2.5, accuracy: 0.001)
    }

    func testSkipsWeekendsWithoutTheDriver() {
        let other = weekend("A", day: 10, sessions: [
            EventSession(sessionType: "Race", sessionName: "Race", status: "post", leaderboard: [entry("George Russell", 1)]),
        ])
        XCTAssertTrue(F1DriverSeason(driverName: "Kimi Antonelli", weekends: [other]).rounds.isEmpty)
    }

    func testAmbiguousSurnameDoesNotMatch() {
        let race = weekend("A", day: 10, sessions: [
            EventSession(sessionType: "Race", sessionName: "Race", status: "post",
                         leaderboard: [entry("Max Verstappen", 1), entry("Jos Verstappen", 2)]),
        ])
        XCTAssertTrue(F1DriverSeason(driverName: "M. Verstappen", weekends: [race]).rounds.isEmpty)
    }
}
