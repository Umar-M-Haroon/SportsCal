import XCTest
@testable import App
import SportsCalModel

final class ScheduleWindowTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-23T18:00:00Z")!

    private func game(_ id: String, _ timestamp: String?, status: String = "post", league: String = "4387",
                      home: String = "Home", homeID: String? = nil, endDate: String? = nil) -> Game {
        Game(idEvent: id, idLeague: league, idHomeTeam: homeID, strHomeTeam: home, strAwayTeam: "Away",
             strStatus: status, strTimestamp: timestamp, isoDate: nil, endDate: endDate)
    }

    // MARK: - Hot window

    func testHotKeepsTheLastTwoWeeksAndEverythingAhead() throws {
        let schedule = LiveScore(nba: LiveEvent(events: [
            game("old", "2026-11-01T01:00:00Z"),
            game("edge", "2026-11-09T01:00:00Z"),          // UTC midnight -14d is Nov 9
            game("recent", "2026-11-20T01:00:00Z"),
            game("next-year", "2027-04-01T01:00:00Z", status: "pre"),
            game("live-old", "2026-10-01T01:00:00Z", status: "in"),
            game("undated", nil, status: "pre"),
        ]))
        let json = String(decoding: try JSONEncoder().encode(schedule), as: UTF8.self)
        let hot = try JSONDecoder().decode(LiveScore.self, from: Data(ScheduleWindow.hotBody(for: .nba, in: json, now: now).utf8))
        XCTAssertEqual(Set(hot.nba?.events.compactMap(\.idEvent) ?? []), ["edge", "recent", "next-year", "live-old", "undated"])
    }

    func testAMultiDayEventIsHotUntilItsLastDay() {
        let start = ScheduleWindow.hotStart(now: now)
        let golf = game("golf", "2026-11-05T12:00:00Z", league: "4425", endDate: "2026-11-09T22:00:00Z")
        XCTAssertTrue(ScheduleWindow.isHot(golf, start: start))
        let ended = game("golf2", "2026-11-01T12:00:00Z", league: "4425", endDate: "2026-11-04T22:00:00Z")
        XCTAssertFalse(ScheduleWindow.isHot(ended, start: start))
    }

    func testNonGameMembersPassThroughUntouched() throws {
        let json = #"{"f1Standings":{"season":"2026","drivers":[]},"worldCup":{"topScorers":[]}}"#
        XCTAssertEqual(ScheduleWindow.hotBody(for: .meta, in: json, now: now), json)
    }

    // MARK: - History query

    func testQueryParsesAndBounds() throws {
        XCTAssertNil(ScheduleHistoryQuery(key: "nope", from: nil, to: nil, team: nil, league: nil, event: nil))
        XCTAssertNil(ScheduleHistoryQuery(key: "nba", from: "2026-11-01", to: nil, team: nil, league: nil, event: nil))
        XCTAssertNil(ScheduleHistoryQuery(key: "nba", from: "20261110", to: "20261101", team: nil, league: nil, event: nil))
        XCTAssertNil(ScheduleHistoryQuery(key: "nba", from: nil, to: nil, team: "a b", league: nil, event: nil))
        XCTAssertNil(ScheduleHistoryQuery(key: "nba", from: nil, to: nil, team: nil, name: String(repeating: "x", count: 81), league: nil, event: nil))
        XCTAssertNotNil(ScheduleHistoryQuery(key: "nba", from: "20261101", to: "20261101", team: "134885",
                                             name: "Brighton & Hove Albion", league: "4387", event: nil))
    }

    func testToIsInclusiveAndTeamMatchesByIDOrName() throws {
        let day = try XCTUnwrap(ScheduleHistoryQuery(key: "nba", from: "20261103", to: "20261103", team: nil, league: nil, event: nil))
        XCTAssertTrue(day.admits(game("a", "2026-11-03T23:30:00Z")))
        XCTAssertFalse(day.admits(game("b", "2026-11-04T00:30:00Z")))
        XCTAssertFalse(day.admits(game("c", "2026-11-02T23:30:00Z")))
        XCTAssertFalse(day.admits(game("undated", nil)))

        let team = try XCTUnwrap(ScheduleHistoryQuery(key: "nba", from: nil, to: nil, team: "134885",
                                                      name: "Denver Nuggets", league: nil, event: nil))
        XCTAssertTrue(team.admits(game("id", "2026-11-03T01:00:00Z", homeID: "134885")))
        XCTAssertTrue(team.admits(game("name", "2026-11-03T01:00:00Z", home: "Denver Nuggets", homeID: "espn-7")))
        XCTAssertFalse(team.admits(game("other", "2026-11-03T01:00:00Z", home: "Utah Jazz", homeID: "134888")))
    }

    func testHistoryBodyFiltersAndCachesPerStamp() async throws {
        let schedule = LiveScore(nba: LiveEvent(events: [game("1", "2026-10-01T01:00:00Z"), game("2", "2026-10-05T01:00:00Z")]))
        let json = String(decoding: try JSONEncoder().encode(schedule), as: UTF8.self)
        let query = try XCTUnwrap(ScheduleHistoryQuery(key: "nba", from: "20261004", to: nil, team: nil, league: nil, event: nil))
        let index = ScheduleHistoryIndex()
        let body = await index.body(for: query, source: json, stamp: "v1")
        let decoded = try JSONDecoder().decode(LiveScore.self, from: Data(body.utf8))
        XCTAssertEqual(decoded.nba?.events.compactMap(\.idEvent), ["2"])

        // Same stamp: the decoded copy is reused even if the blob changed (live ticks).
        let changed = String(decoding: try JSONEncoder().encode(LiveScore(nba: LiveEvent(events: []))), as: UTF8.self)
        let cached = await index.body(for: query, source: changed, stamp: "v1")
        XCTAssertEqual(cached, body)
        // A new stamp rebuilds.
        let rebuilt = try JSONDecoder().decode(LiveScore.self, from: Data(await index.body(for: query, source: changed, stamp: "v2").utf8))
        XCTAssertEqual(rebuilt.nba?.events.count, 0)
    }
}
