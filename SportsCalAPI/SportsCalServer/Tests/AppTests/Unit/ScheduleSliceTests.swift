import XCTest
@testable import App
import SportsCalModel

final class ScheduleSliceTests: XCTestCase {
    private func game(_ id: String, league: String, status: String = "pre", completed: Bool = false, entries: Int = 0) -> Game {
        var game = Game(idEvent: id, idLeague: league, strHomeTeam: "Home \(id)", strAwayTeam: "Away \(id)",
                        strStatus: status, isCompleted: completed, isoDate: nil)
        if entries > 0 {
            game.leaderboardEntries = (1...entries).map {
                LeaderboardEntry(name: "Player \($0)", score: "-\(20 - $0)", position: $0,
                                 roundDetails: [GolfRoundDetail(roundNumber: 1)])
            }
        }
        return game
    }

    private var schedule: LiveScore {
        LiveScore(
            nba: LiveEvent(events: [game("1", league: "4387")]),
            nfl: LiveEvent(events: [game("2", league: "4391"), game("3", league: "102")]),
            golf: LiveEvent(events: [game("4", league: "4425")]),
            racing: LiveEvent(events: [game("5", league: "4370"), game("nascar-6", league: "4393")])
        )
    }

    func testSlicesRecombineIntoTheSchedule() throws {
        let json = String(decoding: try JSONEncoder().encode(schedule), as: UTF8.self)
        let parts = try LiveScore.WireKey.allCases.map { key in
            try JSONDecoder().decode(LiveScore.self, from: Data(ScheduleSlice.body(for: key, in: json).utf8))
        }
        let combined = LiveScore.combining(parts)
        XCTAssertEqual(Set(combined.nfl?.events.compactMap(\.idEvent) ?? []), ["2", "3"])
        XCTAssertEqual(Set(combined.racing?.events.compactMap(\.idEvent) ?? []), ["5", "nascar-6"])
        XCTAssertEqual(combined.nba?.events.count, 1)
        XCTAssertEqual(combined.golf?.events.count, 1)
    }

    func testSliceCarriesOnlyItsMember() throws {
        let json = String(decoding: try JSONEncoder().encode(schedule), as: UTF8.self)
        let college = try JSONDecoder().decode(LiveScore.self, from: Data(ScheduleSlice.body(for: .ncaaf, in: json).utf8))
        XCTAssertEqual(college.nfl?.events.compactMap(\.idEvent), ["3"])
        XCTAssertNil(college.nba)
        XCTAssertEqual(ScheduleSlice.body(for: .tennis, in: json), "{}", "a sport with no games is an empty object")
    }

    func testModelSliceMatchesWireSlice() throws {
        let json = String(decoding: try JSONEncoder().encode(schedule), as: UTF8.self)
        for key in LiveScore.WireKey.allCases {
            let wire = try JSONDecoder().decode(LiveScore.self, from: Data(ScheduleSlice.body(for: key, in: json).utf8))
            let model = schedule.slice(key)
            XCTAssertEqual(LiveScore.combining([wire]).allGamesBySport.flatMap { $0.games.compactMap(\.idEvent) }.sorted(),
                           model.allGamesBySport.flatMap { $0.games.compactMap(\.idEvent) }.sorted(), "\(key)")
        }
    }

    func testFinishedGolfIsSlimmed() {
        let finished = game("10", league: "4425", status: "post", completed: true, entries: 30)
        let live = game("11", league: "4425", status: "in", entries: 30)
        let slim = ScheduleSlimming.slimmed(LiveScore(golf: LiveEvent(events: [finished, live])))
        let slimFinished = slim.golf?.events.first { $0.idEvent == "10" }
        XCTAssertEqual(slimFinished?.leaderboardEntries?.count, 5)
        XCTAssertTrue(slimFinished?.leaderboardEntries?.allSatisfy { $0.roundDetails == nil } ?? false, "no scorecards")
        XCTAssertEqual(slimFinished?.leaderboardEntries?.first?.name, "Player 1")
        XCTAssertEqual(slim.golf?.events.first { $0.idEvent == "11" }?.leaderboardEntries?.count, 30, "in progress keeps the field")
        XCTAssertEqual(ScheduleSlimming.slimmed(slim), slim, "idempotent, so re-merging doesn't rewrite the blob")
    }
}
