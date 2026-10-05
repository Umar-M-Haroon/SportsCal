import XCTest
@testable import SportsCalModel

final class ScheduleSliceModelTests: XCTestCase {
    private func game(_ id: String, _ league: String) -> Game {
        Game(idEvent: id, idLeague: league, strHomeTeam: "H\(id)", strAwayTeam: "A\(id)", isoDate: nil)
    }

    private var schedule: LiveScore {
        LiveScore(nba: LiveEvent(events: [game("b", "4387")]),
                  nfl: LiveEvent(events: [game("n", "4391"), game("c", "102")]),
                  racing: LiveEvent(events: [game("f", "4370"), game("nascar-1", "4393")]))
    }

    func testSlicesPartitionTheSchedule() {
        let ids = LiveScore.WireKey.allCases.flatMap { schedule.slice($0).allGamesBySport.flatMap { $0.games.compactMap(\.idEvent) } }
        XCTAssertEqual(ids.sorted(), ["b", "c", "f", "n", "nascar-1"], "every game in exactly one slice")
        XCTAssertEqual(schedule.slice(.ncaaf).nfl?.events.compactMap(\.idEvent), ["c"])
        XCTAssertEqual(schedule.slice(.motorsport).racing?.events.compactMap(\.idEvent), ["nascar-1"])
    }

    func testCombiningRebuildsTheSchedule() {
        let combined = LiveScore.combining(LiveScore.WireKey.allCases.map { schedule.slice($0) })
        XCTAssertEqual(Set(combined.nfl?.events.compactMap(\.idEvent) ?? []), ["n", "c"])
        XCTAssertEqual(Set(combined.racing?.events.compactMap(\.idEvent) ?? []), ["f", "nascar-1"])
    }

    func testWireKeysPerSport() {
        XCTAssertEqual(LiveScore.wireKeys(for: .nfl, college: false, motorsport: false), [.nfl])
        XCTAssertEqual(LiveScore.wireKeys(for: .nfl, college: true, motorsport: false), [.nfl, .ncaaf])
        XCTAssertEqual(LiveScore.wireKeys(for: .racing, college: false, motorsport: true), [.racing, .motorsport])
        XCTAssertEqual(LiveScore.wireKeys(for: .hockey, college: true, motorsport: true), [.nhl])
    }
}
