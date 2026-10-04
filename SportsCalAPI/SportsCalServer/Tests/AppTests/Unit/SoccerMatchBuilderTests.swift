import XCTest
import Foundation
@testable import App
import SportsCalModel

final class SoccerMatchBuilderTests: XCTestCase {
    /// Fixtures sit in Tests/AppTests/Fixtures/, two directories up from this file.
    private func loadSummary(_ name: String) throws -> SoccerSummaryResponse {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Unit
            .deletingLastPathComponent()      // AppTests
            .appendingPathComponent("Fixtures/\(name)")
        let data = try Data(contentsOf: fixture)
        return try JSONDecoder().decode(SoccerSummaryResponse.self, from: data)
    }

    // MARK: World Cup (France 3–1 Senegal)

    func testBuildsWorldCupMatchFromRealESPNSummary() throws {
        let summary = try loadSummary("wc_summary_sample.json")
        let match = try XCTUnwrap(SoccerMatchBuilder.build(from: summary, eventID: "760432"))

        // Teams resolved with names + lineups.
        XCTAssertEqual(match.home.teamName, "France")
        XCTAssertEqual(match.away.teamName, "Senegal")
        XCTAssertFalse(match.home.players.isEmpty)
        XCTAssertFalse(match.away.players.isEmpty)
        XCTAssertEqual(match.home.formation, "4-2-3-1")

        // Starters sort before subs.
        let firstNonStarter = match.home.players.firstIndex { !$0.starter }
        let lastStarter = match.home.players.lastIndex { $0.starter }
        if let f = firstNonStarter, let l = lastStarter { XCTAssertLessThan(l, f) }

        // Team stat comparison includes possession (formatted with %) and shots.
        let possession = match.teamStats.first { $0.name == "possessionPct" }
        XCTAssertNotNil(possession)
        XCTAssertTrue(possession?.homeDisplay.contains("%") ?? false)
        XCTAssertNotNil(match.teamStats.first { $0.name == "totalShots" })

        // Timeline keeps goals/cards/subs and drops kickoff/halftime.
        XCTAssertFalse(match.events.isEmpty)
        let goals = match.events.filter { $0.type == .goal || $0.type == .penaltyGoal || $0.type == .ownGoal }
        XCTAssertFalse(goals.isEmpty, "expected at least one goal event")
        // Mbappé's goal: side resolved + scorer captured.
        let mbappe = goals.first { $0.playerNames.first?.contains("Mbapp") ?? false }
        XCTAssertEqual(mbappe?.side, .home)

        // A scorer's per-player line carries goals.
        let scorer = match.home.players.first { $0.stat("totalGoals") > 0 }
        XCTAssertNotNil(scorer, "expected a France player with a goal stat")

        // Internationals carry head-to-head in `headToHeadGames`, not `seasonseries`.
        XCTAssertFalse(match.headToHead?.matches.isEmpty ?? true)
    }

    // MARK: Premier League (Bournemouth 0–1 Liverpool, 20 Sep 2026)

    func testBuildsLeagueMatchWithShotsFormAndHeadToHead() throws {
        let summary = try loadSummary("epl_summary_sample.json")
        let match = try XCTUnwrap(SoccerMatchBuilder.build(from: summary, eventID: "401879276"))

        XCTAssertEqual(match.home.teamName, "AFC Bournemouth")
        XCTAssertEqual(match.away.teamName, "Liverpool")
        XCTAssertEqual(match.away.formation, "4-2-3-1")

        // Every starter has a formation slot, 1 (the keeper) through 11; subs have none.
        let slots = match.away.starters.compactMap(\.formationPlace).sorted()
        XCTAssertEqual(slots, Array(1...11))
        XCTAssertTrue(match.away.substitutes.allSatisfy { $0.formationPlace == nil })
        XCTAssertEqual(match.away.starters.first?.position, "G")

        // 21 located shots; the one goal is Isak's, for the away side.
        XCTAssertEqual(match.shots.count, 21)
        let goals = match.shots.filter { $0.outcome == .goal }
        XCTAssertEqual(goals.count, 1)
        XCTAssertEqual(goals.first?.side, .away)
        XCTAssertEqual(goals.first?.playerName, "Alexander Isak")
        XCTAssertEqual(goals.first?.bodyPart, .rightFoot)
        XCTAssertTrue(match.shots.allSatisfy { (0...100).contains($0.x) && $0.xG > 0 && $0.xG < 1 })
        // Szoboszlai's 10th-minute free kick.
        XCTAssertEqual(match.shots.first?.situation, .directFreeKick)
        // Liverpool out-shot Bournemouth 12–9 from better spots.
        XCTAssertGreaterThan(match.expectedGoals(.away), match.expectedGoals(.home))

        // Momentum runs through both halves (full time, so each reaches its end) and
        // is normalised to ±1.
        let halves = Dictionary(grouping: match.momentum, by: \.period)
        XCTAssertEqual(halves.keys.sorted(), [1, 2])
        XCTAssertEqual(halves[1]?.first?.minute, 0)
        XCTAssertGreaterThanOrEqual(halves[1]?.last?.minute ?? 0, 45)
        XCTAssertEqual(halves[2]?.first?.minute, 45)
        XCTAssertGreaterThanOrEqual(halves[2]?.last?.minute ?? 0, 90)
        XCTAssertEqual(match.momentum.map { abs($0.value) }.max(), 1)
        XCTAssertTrue(match.shots.allSatisfy { $0.period == 1 || $0.period == 2 })

        // Commentary keeps every line, with goals and subs classified.
        XCTAssertGreaterThan(match.commentary.count, 90)
        XCTAssertEqual(match.commentary.filter { $0.kind == .goal }.count, 1)
        XCTAssertEqual(match.commentary.filter { $0.kind == .substitution }.count, 9)

        // Five recent results a side, from that side's point of view.
        XCTAssertEqual(match.home.form.count, 5)
        XCTAssertEqual(match.away.form.count, 5)
        let draw = try XCTUnwrap(match.home.form.first { $0.eventID == "401879296" })
        XCTAssertEqual(draw.result, .draw)
        XCTAssertEqual(draw.opponentName, "Everton")
        XCTAssertTrue(draw.isHome)

        XCTAssertEqual(match.headToHead?.summary, "LIV leads series 4-1")
        XCTAssertEqual(match.headToHead?.matches.count, 5)

        // Pass accuracy arrives as a fraction and is shown as a percentage.
        let passPct = try XCTUnwrap(match.teamStats.first { $0.name == "passPct" })
        XCTAssertTrue(passPct.homeDisplay.hasSuffix("%"))
        XCTAssertGreaterThan(passPct.homeValue ?? 0, 1)
    }

    func testRoundTripsThroughJSON() throws {
        let summary = try loadSummary("epl_summary_sample.json")
        let match = try XCTUnwrap(SoccerMatchBuilder.build(from: summary, eventID: "401879276"))
        let data = try JSONEncoder().encode(match)
        XCTAssertEqual(try JSONDecoder().decode(SoccerMatchDetail.self, from: data), match)
        // Comfortably slimmer than the ~420 KB ESPN summary it came from.
        XCTAssertLessThan(data.count, 120_000)
    }

    // MARK: Event id resolution

    func testRecognisesESPNSoccerIDs() {
        XCTAssertTrue(SoccerMatchService.isLikelyESPNID("401879276"))
        XCTAssertTrue(SoccerMatchService.isLikelyESPNID("760432"))
        XCTAssertFalse(SoccerMatchService.isLikelyESPNID("2278410"), "seven digits is a TheSportsDB id")
        XCTAssertFalse(SoccerMatchService.isLikelyESPNID("40187927a"))
    }

    func testCacheLifetimeFollowsMatchState() {
        XCTAssertEqual(SoccerMatchService.cacheSeconds(state: "in"), 30)
        XCTAssertEqual(SoccerMatchService.cacheSeconds(state: "pre"), 120)
        XCTAssertEqual(SoccerMatchService.cacheSeconds(state: "post"), 86_400)
    }
}
