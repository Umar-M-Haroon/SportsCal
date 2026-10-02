import XCTest
@testable import SportsCalModel

final class F1TitleFightTests: XCTestCase {
    /// Real 2026 standings after round 15 (8 GPs + 1 sprint left).
    private let round15: [(name: String, points: Double)] = [
        ("Kimi Antonelli", 302), ("George Russell", 236), ("Lewis Hamilton", 199), ("Lando Norris", 186),
        ("Oscar Piastri", 120),
    ]

    func testPointsAvailable_countsRacesAndSprints() throws {
        let fight = try XCTUnwrap(F1TitleFight(kind: .drivers, standings: round15, remainingRaces: 8, remainingSprints: 1, nextRoundHasSprint: false))
        XCTAssertEqual(fight.pointsAvailable, 8 * 25 + 8)
    }

    func testContenders_dropsDriversWhoCannotCatchTheLeader() throws {
        let fight = try XCTUnwrap(F1TitleFight(kind: .drivers, standings: round15, remainingRaces: 8, remainingSprints: 1, nextRoundHasSprint: false))
        // Piastri: 120 + 208 = 328 >= 302 → alive. Everyone listed is alive at this point.
        XCTAssertEqual(fight.contenders.map(\.name), round15.map(\.name))
        XCTAssertNil(fight.champion)
        // 66-point lead with 183 left after the weekend: no clinch yet.
        XCTAssertNil(fight.clinchNextRound)
    }

    func testRivalWhoCanOnlyTie_isStillAlive() throws {
        let fight = try XCTUnwrap(F1TitleFight(kind: .drivers, standings: [("A", 100), ("B", 75)], remainingRaces: 1, remainingSprints: 0, nextRoundHasSprint: false))
        XCTAssertEqual(fight.contenders.map(\.name), ["A", "B"])
    }

    func testChampion_whenLeadExceedsPointsAvailable() throws {
        let fight = try XCTUnwrap(F1TitleFight(kind: .drivers, standings: [("A", 100), ("B", 74)], remainingRaces: 1, remainingSprints: 0, nextRoundHasSprint: false))
        XCTAssertEqual(fight.champion, "A")
        XCTAssertEqual(fight.contenders.map(\.name), ["A"])
        XCTAssertNil(fight.clinchNextRound)
    }

    func testClinch_marginNeededOverEachRival() throws {
        // 2 races left (50 pts), next isn't a sprint → 25 left afterwards.
        // Lead 20 over B → needs a 6-point margin (lead 26 > 25). Lead 30 over C → C must
        // not outscore A by 5+ (margin -4). D, 51 back, can't gain enough in one weekend.
        let fight = try XCTUnwrap(F1TitleFight(kind: .drivers, standings: [("A", 100), ("B", 80), ("C", 70), ("D", 49)], remainingRaces: 2, remainingSprints: 0, nextRoundHasSprint: false))
        let clinch = try XCTUnwrap(fight.clinchNextRound)
        XCTAssertEqual(clinch.leader, "A")
        XCTAssertEqual(clinch.margins.map(\.rival), ["B", "C"])
        XCTAssertEqual(clinch.margins.map(\.points), [6, -4])
    }

    func testClinch_impossibleWhenMarginExceedsOneWeekend() throws {
        let fight = try XCTUnwrap(F1TitleFight(kind: .drivers, standings: [("A", 100), ("B", 99)], remainingRaces: 3, remainingSprints: 0, nextRoundHasSprint: false))
        XCTAssertNil(fight.clinchNextRound)
    }

    func testSprintWeekend_raisesWeekendHaul() throws {
        // Final round with a sprint: 33 available, 0 after. A leads by 10, so A clinches
        // unless B outscores A by 10+ (margin -9). B can still swing 33, so B stays listed.
        let fight = try XCTUnwrap(F1TitleFight(kind: .drivers, standings: [("A", 100), ("B", 90)], remainingRaces: 1, remainingSprints: 1, nextRoundHasSprint: true))
        XCTAssertEqual(fight.pointsAvailable, 33)
        XCTAssertEqual(try XCTUnwrap(fight.clinchNextRound).margins.map(\.points), [-9])
    }

    func testConstructors_canScoreOneTwo() throws {
        let fight = try XCTUnwrap(F1TitleFight(kind: .constructors, standings: [("McLaren", 500), ("Ferrari", 400)], remainingRaces: 2, remainingSprints: 1, nextRoundHasSprint: false))
        XCTAssertEqual(fight.pointsAvailable, 2 * 43 + 15)
    }

    func testStandingsTitleFight_needsCalendar() {
        let standings = F1Standings(driverStandings: [
            F1DriverStanding(position: 1, driverName: "A", constructorName: "X", points: 10, wins: 0),
            F1DriverStanding(position: 2, driverName: "B", constructorName: "Y", points: 5, wins: 0),
        ])
        XCTAssertNil(standings.titleFight(.drivers))
    }

    func testTeamColorLookup_normalizesSourceNames() {
        let standings = F1Standings(teamColors: ["Red Bull Racing": "4781D7", "Haas F1 Team": "9C9FA2", "Racing Bulls": "6C98FF"])
        XCTAssertEqual(standings.teamColorHex(for: "Red Bull"), "4781D7")
        XCTAssertEqual(standings.teamColorHex(for: "Haas"), "9C9FA2")
        XCTAssertEqual(standings.teamColorHex(for: "Racing Bulls"), "6C98FF")
        XCTAssertNil(standings.teamColorHex(for: "Brawn"))
    }

    func testDriverCode_foldsDiacriticsAndFallsBackToSurname() {
        let standings = F1Standings(driverCodes: ["nico hulkenberg": "HUL", "kimi antonelli": "ANT"])
        XCTAssertEqual(standings.driverCode(for: "Nico Hülkenberg"), "HUL")
        XCTAssertEqual(standings.driverCode(for: "Andrea Kimi Antonelli"), "ANT")
        XCTAssertNil(standings.driverCode(for: "Unknown Driver"))
    }
}
