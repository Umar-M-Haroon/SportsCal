import XCTest
@testable import SportsCalModel

/// Pins TheSportsDB season-label formats per league. MLB ("2026") and NFL
/// ("2025") are single-year on TheSportsDB even though they are team sports —
/// requesting a split-year season for them returns an empty schedule (the
/// prod "MLB 0 games" gap of June 2026).
final class SeasonFormatTests: XCTestCase {

    func testSportsDBSingleYearLeagues() {
        for league in [Leagues.mlb, .nfl, .atp, .wta, .pga, .formula1] {
            XCTAssertTrue(league.sportsDBSingleYearSeason,
                          "\(league) uses single-year season labels on TheSportsDB")
        }
    }

    func testSportsDBSplitYearLeagues() {
        for league in [Leagues.nba, .nhl, .English_Premier_League] {
            XCTAssertFalse(league.sportsDBSingleYearSeason,
                           "\(league) uses split-year season labels on TheSportsDB")
        }
    }

    func testESPNWholeYearFetchFlagUnchanged() {
        // usesSingleYearSeason also gates whole-year ESPN scoreboard fetches —
        // MLB/NFL must stay OFF there (their ESPN enrichment fetches today's
        // scoreboard, not a 12MB season dump).
        XCTAssertFalse(Leagues.mlb.usesSingleYearSeason)
        XCTAssertFalse(Leagues.nfl.usesSingleYearSeason)
        XCTAssertTrue(Leagues.pga.usesSingleYearSeason)
    }
}
