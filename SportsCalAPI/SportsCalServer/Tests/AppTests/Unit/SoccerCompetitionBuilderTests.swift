import XCTest
import Foundation
@testable import App
import SportsCalModel

/// Premier League, 4 Oct 2026 (five rounds played), and Erling Haaland's player page.
final class SoccerCompetitionBuilderTests: XCTestCase {
    private func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Unit
            .deletingLastPathComponent()      // AppTests
            .appendingPathComponent("Fixtures/\(name)")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: fixture))
    }

    private struct SeasonBoard: Decodable { let events: [Event] }

    private func hub() throws -> SoccerCompetitionHub {
        SoccerCompetitionBuilder.build(
            leagueID: Leagues.English_Premier_League.rawValue,
            standings: try load("epl_standings_sample.json", as: StandingsResponse.self),
            season: try load("epl_season_sample.json", as: SeasonBoard.self).events,
            statistics: try load("epl_statistics_sample.json", as: LeagueStatisticsResponse.self)
        )
    }

    // MARK: Table

    func testBuildsTheLeagueTable() throws {
        let hub = try hub()
        XCTAssertEqual(hub.groups.count, 1)
        XCTAssertNil(hub.groups.first?.name, "a single league table needs no heading")
        let rows = try XCTUnwrap(hub.groups.first?.rows)
        XCTAssertEqual(rows.count, 20)
        XCTAssertEqual(rows.map(\.rank), Array(1...20))

        let leader = try XCTUnwrap(rows.first)
        XCTAssertEqual(leader.teamName, "Manchester City")
        XCTAssertEqual(leader.points, 15)
        XCTAssertEqual(leader.won, 5)
        XCTAssertEqual(leader.goalDifference, 8)
        XCTAssertEqual(leader.zone?.description, "Champions League")
        XCTAssertNotNil(leader.badge)
        // Every row adds up.
        for row in rows {
            XCTAssertEqual(row.won + row.drawn + row.lost, row.played, row.teamName)
            XCTAssertEqual(row.won * 3 + row.drawn, row.points, row.teamName)
        }
        XCTAssertTrue(hub.zones.contains { $0.description.localizedCaseInsensitiveContains("relegation") })
    }

    func testFormComesFromThisSeasonOnly() throws {
        let rows = try XCTUnwrap(try hub().groups.first?.rows)
        for row in rows {
            // Last season's January–May results sit on the same calendar-year board;
            // counting them would give every side five results already.
            XCTAssertEqual(row.form.count, min(row.played, 5), row.teamName)
            XCTAssertEqual(row.form.filter { $0 == .win }.count <= row.won, true, row.teamName)
        }
        XCTAssertEqual(rows.first?.form, [.win, .win, .win, .win, .win], "City are 5-0-0")
    }

    // MARK: Leaders

    func testBuildsScorersAndAssisters() throws {
        let hub = try hub()
        XCTAssertEqual(hub.scorers.count, SoccerCompetitionBuilder.leaderCount)
        XCTAssertEqual(hub.scorers.first?.name, "Erling Haaland")
        XCTAssertEqual(hub.scorers.first?.goals, 5)
        XCTAssertEqual(hub.scorers.first?.athleteID, "253989")
        XCTAssertEqual(hub.scorers.first?.teamName, "Manchester City")
        XCTAssertEqual(hub.scorers.map(\.rank), Array(1...SoccerCompetitionBuilder.leaderCount))
        XCTAssertTrue(hub.scorers.allSatisfy { $0.appearances > 0 })
        XCTAssertEqual(hub.assisters.first?.assists, 3)
    }

    func testCupWithoutATableStillHasLeaders() throws {
        let hub = SoccerCompetitionBuilder.build(
            leagueID: 1, standings: nil, season: [],
            statistics: try load("epl_statistics_sample.json", as: LeagueStatisticsResponse.self)
        )
        XCTAssertTrue(hub.groups.isEmpty)
        XCTAssertFalse(hub.isEmpty)
    }

    // MARK: Player page

    func testBuildsAPlayerProfile() throws {
        let profile = try XCTUnwrap(SoccerPlayerBuilder.build(
            athleteID: "253989",
            bio: try load("player_bio_sample.json", as: SoccerAthleteResponse.self),
            overview: try load("player_overview_sample.json", as: SoccerAthleteOverview.self)
        ))
        XCTAssertEqual(profile.name, "Erling Haaland")
        XCTAssertEqual(profile.position, "Forward")
        XCTAssertEqual(profile.teamName, "Manchester City")
        XCTAssertEqual(profile.nationality, "Norway")
        XCTAssertNotNil(profile.flagURL)

        // A season line per competition, stats zipped back to their names.
        XCTAssertFalse(profile.seasons.isEmpty)
        let premierLeague = try XCTUnwrap(profile.seasons.first { $0.leagueSlug == "eng.1" })
        XCTAssertEqual(premierLeague.stats.first { $0.name == "totalGoals" }?.value, 5)
        XCTAssertGreaterThanOrEqual(profile.total("totalGoals"), 5)

        // The last five, newest first, each from Haaland's side's view. ESPN sent
        // two of the three Nations League matches twice; each appears once.
        XCTAssertEqual(profile.recentMatches.map(\.eventID), ["401861100", "401861073", "401861046"])
        let dates = profile.recentMatches.compactMap(\.date)
        XCTAssertEqual(dates, dates.sorted(by: >))
        for match in profile.recentMatches {
            XCTAssertNotNil(match.result)
            XCTAssertNotNil(match.appearance, "Started / Substitute")
            XCTAssertNil(match.stats.first { $0.name == "appearances" })
            if let result = match.result, let gf = match.goalsFor, let ga = match.goalsAgainst {
                XCTAssertEqual(result, gf > ga ? .win : gf < ga ? .loss : .draw, match.opponentName)
            }
        }
        XCTAssertNotNil(profile.nextMatch)
    }

    func testNoProfileWithoutABio() {
        XCTAssertNil(SoccerPlayerBuilder.build(athleteID: "1", bio: nil, overview: nil))
    }
}
