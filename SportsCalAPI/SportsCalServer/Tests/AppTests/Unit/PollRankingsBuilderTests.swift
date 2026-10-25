import XCTest
import Foundation
@testable import App
import SportsCalModel

/// College football polls: the site API's Week 8 of 2026 (AP + Coaches, trimmed), and
/// the core API's AP poll for Week 5, whose teams are `$ref`s.
final class PollRankingsBuilderTests: XCTestCase {
    private func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Unit
            .deletingLastPathComponent()      // AppTests
            .appendingPathComponent("Fixtures/\(name)")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: fixture))
    }

    private func latest() throws -> PollRankings {
        let response = try load("cfb_rankings_sample.json", as: ESPNRankingsResponse.self)
        return try XCTUnwrap(PollRankingsBuilder.latest(league: .ncaaf, response: response))
    }

    // MARK: Latest week

    func testLatestWeekAndWeekList() throws {
        let rankings = try latest()
        XCTAssertEqual(rankings.league, Leagues.ncaaf.rawValue)
        XCTAssertEqual(rankings.season, 2026)
        XCTAssertEqual(rankings.week, PollRankings.Week(seasonType: 2, number: 8, label: "Week 8"))
        XCTAssertEqual(rankings.weeks.first, PollRankings.Week(seasonType: 1, number: 1, label: "Preseason"))
        XCTAssertEqual(rankings.weeks.count, 9)
        XCTAssertEqual(rankings.polls.map(\.name), ["AP Top 25", "AFCA Coaches Poll"])
    }

    func testRankedEntries() throws {
        let ap = try XCTUnwrap(try latest().polls.first)
        XCTAssertEqual(ap.id, "1")
        XCTAssertEqual(ap.shortName, "AP Poll")
        XCTAssertEqual(ap.ranks.map(\.rank), (1...25).map { $0 })

        let leader = try XCTUnwrap(ap.ranks.first)
        XCTAssertEqual(leader.team.location, "Miami")
        XCTAssertEqual(leader.team.displayName, "Miami Hurricanes")
        XCTAssertEqual(leader.team.conference, "ACC")
        XCTAssertEqual(leader.team.logo, "https://a.espncdn.com/i/teamlogos/ncaa/500/2390.png")
        XCTAssertEqual(leader.team.darkLogo, "https://a.espncdn.com/i/teamlogos/ncaa/500-dark/2390.png")
        XCTAssertEqual(leader.record, "6-0")
        XCTAssertEqual(leader.firstPlaceVotes, 40)
        XCTAssertEqual(leader.movement, 2)
        XCTAssertFalse(leader.isNew)
    }

    func testNewlyRankedTeamHasNoPreviousRank() throws {
        let ap = try XCTUnwrap(try latest().polls.first)
        let arizona = try XCTUnwrap(ap.ranks.first { $0.team.location == "Arizona" })
        XCTAssertNil(arizona.previous, "ESPN sends 0 for unranked last week")
        XCTAssertTrue(arizona.isNew)
        XCTAssertNil(arizona.movement)
    }

    func testUnrankedTeamsCarryNoRankOrBogusRecord() throws {
        let ap = try XCTUnwrap(try latest().polls.first)
        XCTAssertEqual(ap.others.count, 7)
        XCTAssertTrue(ap.others.allSatisfy { $0.rank == nil && $0.record == nil })
        XCTAssertEqual(ap.others.compactMap(\.points), ap.others.compactMap(\.points).sorted(by: >))

        XCTAssertEqual(ap.droppedOut.map(\.team.location), ["Mississippi State", "Oklahoma State"])
        XCTAssertEqual(ap.droppedOut.map(\.previous), [16, 18])
        XCTAssertTrue(ap.droppedOut.allSatisfy { $0.movement == nil })
    }

    // MARK: Earlier week (core API)

    func testEarlierWeekResolvesTeamRefsFromTheDirectory() throws {
        let latest = try latest()
        let poll = try load("cfb_core_poll_week5_sample.json", as: ESPNPoll.self)
        var directory = PollRankingsBuilder.directory(from: latest)
        directory["251"] = PollRankings.Team(id: "251", location: "Texas", name: "Longhorns", abbreviation: "TEX",
                                             color: nil, logo: nil, darkLogo: nil, conference: nil)
        directory["213"] = PollRankings.Team(id: "213", location: "Penn State", name: "Nittany Lions", abbreviation: "PSU",
                                             color: nil, logo: nil, darkLogo: nil, conference: nil)
        let week5 = PollRankings.Week(seasonType: 2, number: 5, label: "Week 5")

        let rankings = PollRankingsBuilder.week(week5, latest: latest, polls: [poll], directory: directory)
        XCTAssertEqual(rankings.week, week5)
        XCTAssertEqual(rankings.weeks, latest.weeks, "the week picker always lists the whole season")

        let ap = try XCTUnwrap(rankings.polls.first)
        let leader = try XCTUnwrap(ap.ranks.first)
        XCTAssertEqual(leader.team.displayName, "Texas Longhorns")
        XCTAssertEqual(leader.record, "4-0", "core sends the record as an object")
        XCTAssertEqual(leader.firstPlaceVotes, 62)
        XCTAssertEqual(leader.movement, 0)
        XCTAssertEqual(ap.droppedOut.first?.team.location, "Penn State")
    }

    func testTeamsMissingFromTheDirectoryAreSkippedNotFatal() throws {
        let poll = try load("cfb_core_poll_week5_sample.json", as: ESPNPoll.self)
        XCTAssertNil(PollRankingsBuilder.poll(poll, directory: [:]), "a poll with no resolvable teams is dropped")

        let texas = PollRankings.Team(id: "251", location: "Texas", name: "Longhorns", abbreviation: nil,
                                      color: nil, logo: nil, darkLogo: nil, conference: nil)
        let built = try XCTUnwrap(PollRankingsBuilder.poll(poll, directory: ["251": texas]))
        XCTAssertEqual(built.ranks.map(\.team.location), ["Texas"])
    }

    func testCoreRefIDParsing() {
        let team = ESPNPoll.Team(id: nil, location: nil, name: nil, abbreviation: nil, color: nil, logos: nil, groups: nil,
                                 ref: "http://sports.core.api.espn.com/v2/sports/football/leagues/college-football/seasons/2026/teams/251?lang=en&region=us")
        XCTAssertEqual(team.resolvedID, "251")
    }
}
