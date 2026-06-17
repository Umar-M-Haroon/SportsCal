@testable import App
import XCTest
import SportsCalModel

/// `mergeWorldCupEvents` overlays the fresher "today" scoreboard onto the
/// full-season fixture list so a live World Cup match reflects ESPN's current
/// clock/score/FT status instead of the season query's laggy copy — while still
/// keeping every fixture the season query carries.
final class ESPNSoccerJobMergeTests: XCTestCase {

    private func event(_ id: String, _ name: String) -> Event {
        Event(id: id, uid: "uid-\(id)", date: "2026-06-15T00:00Z", name: name)
    }

    func test_prefersTodayCopyForSharedEvent() {
        let season = [event("1", "season-1"), event("2", "season-2")]
        let today = [event("2", "today-2")]

        let merged = ESPNSoccerJob.mergeWorldCupEvents(season: season, today: today)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.id == "2" }?.name, "today-2", "today's fresher live copy must win")
        XCTAssertEqual(merged.first { $0.id == "1" }?.name, "season-1", "season-only fixture must be preserved")
    }

    func test_appendsTodayOnlyEvents() {
        let season = [event("1", "season-1")]
        let today = [event("9", "today-9")]

        let merged = ESPNSoccerJob.mergeWorldCupEvents(season: season, today: today)

        XCTAssertEqual(merged.map(\.id), ["1", "9"], "a fixture only in today's board is appended")
    }

    func test_emptyToday_returnsSeasonUnchanged() {
        let season = [event("1", "season-1"), event("2", "season-2")]

        let merged = ESPNSoccerJob.mergeWorldCupEvents(season: season, today: [])

        XCTAssertEqual(merged.map(\.id), ["1", "2"])
        XCTAssertEqual(merged.map(\.name), ["season-1", "season-2"])
    }

    func test_preservesSeasonOrder() {
        let season = [event("a", "s-a"), event("b", "s-b"), event("c", "s-c")]
        let today = [event("b", "t-b")]

        let merged = ESPNSoccerJob.mergeWorldCupEvents(season: season, today: today)

        XCTAssertEqual(merged.map(\.id), ["a", "b", "c"], "season order is preserved")
        XCTAssertEqual(merged.first { $0.id == "b" }?.name, "t-b")
    }
}
