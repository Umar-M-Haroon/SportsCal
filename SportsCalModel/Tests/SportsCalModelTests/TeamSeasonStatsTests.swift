import XCTest
@testable import SportsCalModel

/// Team rank card. Fixtures are real ESPN core-API team statistics for the 2026
/// regular season (pulled October 2026), trimmed to name/value/rank fields:
/// NBA team 2 (Celtics), NHL team 1 (Bruins), MLB team 10 (Yankees), NFL team 23 (Steelers).
final class TeamSeasonStatsTests: XCTestCase {

    private func stats(_ name: String, league: Leagues) throws -> TeamSeasonStats {
        let decoded = try JSONLoader.load(file: "CoreTeamStats-\(name)", type: ESPNCoreTeamStatistics.self)
        let espn = try XCTUnwrap(decoded as? ESPNCoreTeamStatistics)
        return try XCTUnwrap(TeamSeasonStats(espn: espn, league: league, season: "2026", isPreviousSeason: false))
    }

    func testBasketballPerGameIsComputedNotRounded() throws {
        let nba = try stats("nba", league: .nba)
        let points = try XCTUnwrap(nba.stats.first { $0.name == "offensive.points" })
        // 9,418 points over 82 games. ESPN's own per-game figure says "114".
        XCTAssertEqual(points.value, "114.9")
        XCTAssertEqual(points.rank, 3)
        XCTAssertEqual(points.rankDisplay, "3rd")
        XCTAssertEqual(nba.stats.first { $0.name == "defensive.blocks" }?.value, "5.0")
        XCTAssertEqual(nba.stats.first { $0.name == "offensive.fieldGoalPct" }?.value, "46.7", "percentages stay as-is")
    }

    func testHockeyUsesGoalsAgainstAverageNotTotal() throws {
        // ESPN ranks total goals-against with the leakiest team 1st; the average ranks
        // the stingiest 1st. Only the average belongs on a card that reads ranks as praise.
        let nhl = try stats("nhl", league: .nhl)
        XCTAssertNil(nhl.stats.first { $0.name == "defensive.goalsAgainst" })
        let gaa = try XCTUnwrap(nhl.stats.first { $0.name == "defensive.avgGoalsAgainst" })
        XCTAssertEqual(gaa.value, "3.01")
        XCTAssertEqual(gaa.rankDisplay, "14th")
    }

    func testBaseballAndFootballCards() throws {
        let mlb = try stats("mlb", league: .mlb)
        XCTAssertEqual(mlb.stats.first { $0.name == "pitching.ERA" }?.rank, 1)
        XCTAssertEqual(mlb.stats.count, TeamSeasonStats.specs(for: .mlb).count, "every curated MLB stat is present")

        let nfl = try stats("nfl", league: .nfl)
        XCTAssertEqual(nfl.stats.first?.label, "Points / Game")
        XCTAssertEqual(nfl.stats.first?.value, "19.3")
        XCTAssertEqual(nfl.stats.count, TeamSeasonStats.specs(for: .nfl).count, "every curated NFL stat is present")
    }

    func testUnsupportedLeagueOrEmptySeasonIsNil() throws {
        let decoded = try JSONLoader.load(file: "CoreTeamStats-nba", type: ESPNCoreTeamStatistics.self)
        let espn = try XCTUnwrap(decoded as? ESPNCoreTeamStatistics)
        XCTAssertNil(TeamSeasonStats(espn: espn, league: .English_Premier_League, season: "2026", isPreviousSeason: false))
        let empty = try JSONDecoder().decode(ESPNCoreTeamStatistics.self, from: Data(#"{"splits":{"categories":[]}}"#.utf8))
        XCTAssertNil(TeamSeasonStats(espn: empty, league: .nba, season: "2027", isPreviousSeason: false))
    }
}
