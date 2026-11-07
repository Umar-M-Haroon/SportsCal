import XCTest
@testable import SportsCalModel

final class RaceWeekendScheduleTests: XCTestCase {
    private func sprintWeekend(raceStatus: String = "pre") -> Game {
        Game(idLeague: "4370", strHomeTeam: "Dutch Grand Prix", strAwayTeam: "Lando Norris",
             strTimestamp: "2026-08-21T10:30Z", isoDate: nil, sessions: [
                EventSession(sessionType: "FP1", sessionName: "Free Practice 1", status: "post", date: "2026-08-21T10:30Z",
                             leaderboard: [LeaderboardEntry(name: "Kimi Antonelli", score: "P1", position: 1)]),
                EventSession(sessionType: "SS", sessionName: "SS", status: "post", date: "2026-08-21T14:30Z",
                             leaderboard: [LeaderboardEntry(name: "George Russell", score: "P1", position: 1)]),
                EventSession(sessionType: "SR", sessionName: "SR", status: "pre", date: "2026-08-22T10:00Z"),
                EventSession(sessionType: "Qual", sessionName: "Qualifying", status: "pre", date: "2026-08-22T14:00Z"),
                EventSession(sessionType: "Race", sessionName: "Race", status: raceStatus, date: "2026-08-23T13:00Z"),
             ])
    }

    func testRaceWeekendTitlesAndTimesUseTheRace() throws {
        let game = sprintWeekend()
        XCTAssertEqual(game.eventTitle(), "Dutch Grand Prix — Race")
        let race = try XCTUnwrap(DateParsers.parse("2026-08-23T13:00Z"))
        XCTAssertEqual(game.eventStartDate(), race)
        XCTAssertEqual(game.eventDurationHours(), 3)

        let quali = try XCTUnwrap(game.sessions?[3])
        XCTAssertEqual(game.eventTitle(session: quali), "Dutch Grand Prix — Qualifying")
        XCTAssertEqual(game.eventDurationHours(session: quali), 1)
        XCTAssertEqual(game.eventTitle(session: game.sessions?[1]), "Dutch Grand Prix — Sprint Qualifying")
    }

    func testOtherSportsKeepTheirTitles() {
        let match = Game(idLeague: "4387", strHomeTeam: "Lakers", strAwayTeam: "Celtics", isoDate: nil)
        XCTAssertEqual(match.eventTitle(), "Celtics @ Lakers")
        let golf = Game(idLeague: "4425", strHomeTeam: "The Masters", strAwayTeam: "TBD", isoDate: nil)
        XCTAssertEqual(golf.eventTitle(), "The Masters")
    }

    func testFeaturedSessionPrefersSprintQualiOverPractice() {
        XCTAssertEqual(sprintWeekend().featuredSession?.sessionType, "SS")
    }

    func testUpcomingAndNextSessions() throws {
        let game = sprintWeekend()
        let now = try XCTUnwrap(DateParsers.parse("2026-08-22T11:00Z"))
        XCTAssertEqual(game.upcomingSessions(after: now).map(\.sessionType), ["Qual", "Race"])
        XCTAssertEqual(game.nextSession(after: now)?.sessionType, "Qual")
    }

    func testLeaderTitle() {
        XCTAssertEqual(EventSession(sessionType: "Race", sessionName: "Race", status: "post").leaderTitle, "Winner")
        XCTAssertEqual(EventSession(sessionType: "Race", sessionName: "Race", status: "in").leaderTitle, "Leader")
        XCTAssertEqual(EventSession(sessionType: "FP2", sessionName: "FP2", status: "post").leaderTitle, "Fastest")
    }

    func testLiveActivitySeriesCodeAndEnduranceCarNumbers() throws {
        XCTAssertEqual(LiveActivityRace.seriesCode(for: Game(idLeague: "4373", strHomeTeam: "", strAwayTeam: "", isoDate: nil)), "INDY")
        XCTAssertEqual(LiveActivityRace.seriesCode(for: Game(idLeague: "4413", strHomeTeam: "", strAwayTeam: "", isoDate: nil)), "WEC")
        XCTAssertEqual(LiveActivityRace.seriesCode(for: Game(idLeague: "4370", strHomeTeam: "", strAwayTeam: "", isoDate: nil)), "F1")

        let car = LeaderboardEntry(name: "Cameron / Nasr / Tandy", score: "1", position: 1,
                                   stockCar: StockCarDetail(carNumber: "7"))
        let imsa = Game(idLeague: "4488", strHomeTeam: "Petit Le Mans", strAwayTeam: "", isoDate: nil, sessions: [
            EventSession(sessionType: "race", sessionName: "Race", status: "in", leaderboard: [car]),
        ])
        let race = try XCTUnwrap(LiveActivityRace(game: imsa, standings: nil))
        XCTAssertEqual(race.leaders.map(\.code), ["#7"])
    }
}
