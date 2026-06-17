import XCTest
import Foundation
@testable import App
import SportsCalModel

final class WorldCupBoxScoreBuilderTests: XCTestCase {
    private func loadSummary() throws -> SoccerSummaryResponse {
        // Fixture sits at Tests/AppTests/Fixtures/wc_summary_sample.json,
        // two directories up from this file (Unit/ -> AppTests/).
        let here = URL(fileURLWithPath: #filePath)
        let fixture = here
            .deletingLastPathComponent()      // Unit
            .deletingLastPathComponent()      // AppTests
            .appendingPathComponent("Fixtures/wc_summary_sample.json")
        let data = try Data(contentsOf: fixture)
        return try JSONDecoder().decode(SoccerSummaryResponse.self, from: data)
    }

    func testBuildsBoxScoreFromRealESPNSummary() throws {
        let summary = try loadSummary()
        let box = try XCTUnwrap(WorldCupBoxScoreBuilder.build(from: summary, eventID: "760432"))

        // Teams resolved with names + lineups.
        XCTAssertEqual(box.home.teamName, "France")
        XCTAssertEqual(box.away.teamName, "Senegal")
        XCTAssertFalse(box.home.players.isEmpty)
        XCTAssertFalse(box.away.players.isEmpty)
        XCTAssertEqual(box.home.formation, "4-2-3-1")

        // Starters sort before subs.
        let firstNonStarter = box.home.players.firstIndex { !$0.starter }
        let lastStarter = box.home.players.lastIndex { $0.starter }
        if let f = firstNonStarter, let l = lastStarter { XCTAssertLessThan(l, f) }

        // Team stat comparison includes possession (formatted with %) and shots.
        let possession = box.teamStats.first { $0.name == "possessionPct" }
        XCTAssertNotNil(possession)
        XCTAssertTrue(possession?.homeDisplay.contains("%") ?? false)
        XCTAssertNotNil(box.teamStats.first { $0.name == "totalShots" })

        // Timeline keeps goals/cards/subs and drops kickoff/halftime.
        XCTAssertFalse(box.events.isEmpty)
        XCTAssertTrue(box.events.allSatisfy { $0.type != .other || !$0.typeText.isEmpty })
        let goals = box.events.filter { $0.type == .goal || $0.type == .penaltyGoal || $0.type == .ownGoal }
        XCTAssertFalse(goals.isEmpty, "expected at least one goal event")
        // Mbappé's goal: side resolved + scorer captured.
        let mbappe = goals.first { $0.playerNames.first?.contains("Mbapp") ?? false }
        XCTAssertEqual(mbappe?.side, .home)

        // A scorer's per-player line carries goals.
        let scorer = box.home.players.first { p in
            p.stats.contains { $0.name == "totalGoals" && ($0.value ?? 0) > 0 }
        }
        XCTAssertNotNil(scorer, "expected a France player with a goal stat")
    }
}
