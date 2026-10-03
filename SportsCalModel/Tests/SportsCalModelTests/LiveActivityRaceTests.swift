import XCTest
@testable import SportsCalModel

final class LiveActivityRaceTests: XCTestCase {
    private func entry(_ name: String, _ position: Int, gap: String?, team: String = "McLaren") -> LeaderboardEntry {
        LeaderboardEntry(name: name, score: "", position: position, constructor: team, gap: gap)
    }

    func testUsesLiveSessionTopThreeWithCodesAndColours() throws {
        let game = Game(strHomeTeam: "Singapore GP", strAwayTeam: "", isoDate: nil, sessions: [
            EventSession(sessionType: "Qual", sessionName: "Qualifying", status: "post", leaderboard: [entry("Lando Norris", 1, gap: nil)]),
            EventSession(sessionType: "Race", sessionName: "Race", status: "in", leaderboard: [
                entry("Nico Hülkenberg", 4, gap: "+9.1", team: "Audi"),
                entry("Oscar Piastri", 1, gap: "1:02:11.004"),
                entry("Lando Norris", 2, gap: "+1.204"),
                entry("George Russell", 3, gap: "+3.900", team: "Mercedes"),
            ]),
        ])
        let standings = F1Standings(teamColors: ["McLaren": "F47600"], driverCodes: ["oscar piastri": "PIA"])
        let race = try XCTUnwrap(LiveActivityRace(game: game, standings: standings))
        XCTAssertEqual(race.session, "Race")
        XCTAssertEqual(race.leaders.map(\.code), ["PIA", "NOR", "RUS"])
        XCTAssertEqual(race.leaders.map(\.gap), [nil, "+1.204", "+3.900"])
        XCTAssertEqual(race.leaders.first?.teamColor, "F47600")
        XCTAssertNil(race.leaders.last?.teamColor)
    }

    func testFallsBackToLatestFinishedSessionAndFoldsCodes() throws {
        let game = Game(strHomeTeam: "GP", strAwayTeam: "", isoDate: nil, sessions: [
            EventSession(sessionType: "SS", sessionName: "SS", status: "post", leaderboard: [entry("Nico Hülkenberg", 1, gap: nil)]),
            EventSession(sessionType: "Race", sessionName: "Race", status: "pre"),
        ])
        let race = try XCTUnwrap(LiveActivityRace(game: game, standings: nil))
        XCTAssertEqual(race.session, "Sprint Q")
        XCTAssertEqual(race.leaders.map(\.code), ["HUL"])
    }

    func testNilWithoutClassification() {
        let game = Game(strHomeTeam: "GP", strAwayTeam: "", isoDate: nil, sessions: [
            EventSession(sessionType: "FP1", sessionName: "Free Practice 1", status: "pre"),
        ])
        XCTAssertNil(LiveActivityRace(game: game, standings: nil))
    }

    func testLiveSessionWithoutTimingStillRaceState() throws {
        let game = Game(strHomeTeam: "GP", strAwayTeam: "", isoDate: nil, sessions: [
            EventSession(sessionType: "Race", sessionName: "Race", status: "in"),
        ])
        let race = try XCTUnwrap(LiveActivityRace(game: game, standings: nil))
        XCTAssertEqual(race.session, "Race")
        XCTAssertTrue(race.leaders.isEmpty)
    }
}
