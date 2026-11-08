import XCTest
@testable import SportsCalModel

final class CollegeBasketballPeriodTests: XCTestCase {
    private func game(league: Leagues) -> Game {
        // strSport derives from idLeague, so the league alone picks the sport.
        Game(idEvent: "g-1", idLeague: String(league.rawValue), strHomeTeam: "Duke Blue Devils",
             strAwayTeam: "Coastal Carolina Chanticleers", isoDate: nil)
    }

    func testMensCollegeBasketballUsesHalves() {
        XCTAssertEqual(game(league: .ncaaMBBTournament).periodLabels(count: 4), ["H1", "H2", "OT", "2OT"])
        XCTAssertEqual(Leagues.ncaaMBBTournament.periodName(2), "H2")
        XCTAssertEqual(Leagues.ncaaMBBTournament.periodName(3), "OT")
    }

    func testNBAStillUsesQuarters() {
        XCTAssertEqual(game(league: .nba).periodLabels(count: 5), ["Q1", "Q2", "Q3", "Q4", "OT"])
    }

    func testCollegeBasketballIsNotLabelledMarchMadnessAllSeason() {
        XCTAssertEqual(Leagues.ncaaMBBTournament.leagueName, "College Basketball")
    }
}
