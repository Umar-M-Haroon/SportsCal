import XCTest
@testable import SportsCalModel

final class SoccerFormationLayoutTests: XCTestCase {
    /// Starters as ESPN sends them: (formation place, position code).
    private func lineup(_ formation: String, _ slots: [(Int, String)]) -> SoccerLineup {
        SoccerLineup(
            teamName: "Test",
            formation: formation,
            players: slots.map { slot, position in
                SoccerLineupPlayer(name: "P\(slot)", position: position, starter: true, formationPlace: slot)
            } + [SoccerLineupPlayer(name: "Sub", position: "F", starter: false)]
        )
    }

    private func lines(_ placements: [SoccerFormationLayout.Placement]) -> [[String]] {
        let grouped = Dictionary(grouping: placements, by: \.line)
        return grouped.keys.sorted().map { line in
            grouped[line]!.sorted { $0.across < $1.across }.map(\.player.name)
        }
    }

    // Liverpool at Bournemouth, 20 Sep 2026.
    func testPlacesA4231WithHoldingPairOnTheirOwnLine() throws {
        let placements = try XCTUnwrap(SoccerFormationLayout.place(lineup("4-2-3-1", [
            (1, "G"), (2, "RB"), (3, "LB"), (4, "LM"), (5, "CD-R"), (6, "CD-L"),
            (7, "AM-R"), (8, "RM"), (9, "F"), (10, "AM"), (11, "AM-L"),
        ])))
        XCTAssertEqual(lines(placements), [
            ["P1"],
            ["P2", "P5", "P6", "P3"],   // RB, CD-R, CD-L, LB
            ["P8", "P4"],               // the "RM"/"LM" holding pair
            ["P7", "P10", "P11"],
            ["P9"],
        ])
        XCTAssertEqual(placements.count, 11, "substitutes stay off the pitch")
    }

    func testOrdersBackThreeByPositionCodeNotSlot() throws {
        // 3-1-4-2 numbers its centre-backs differently from 3-5-2; the codes still read right to left.
        let placements = try XCTUnwrap(SoccerFormationLayout.place(lineup("3-1-4-2", [
            (1, "G"), (2, "RM"), (3, "LM"), (4, "CD"), (5, "CD-R"), (6, "CD-L"),
            (7, "CM-R"), (8, "SW"), (9, "CF-R"), (10, "CF-L"), (11, "CM-L"),
        ])))
        XCTAssertEqual(lines(placements), [
            ["P1"], ["P5", "P4", "P6"], ["P8"], ["P2", "P7", "P11", "P3"], ["P9", "P10"],
        ])
    }

    func testFallsBackForUnmappedFormation() throws {
        let placements = try XCTUnwrap(SoccerFormationLayout.place(lineup("4-2-4", [
            (1, "G"), (2, "RB"), (3, "LB"), (4, "CM-R"), (5, "CD-R"), (6, "CD-L"),
            (7, "RW"), (8, "CM-L"), (9, "CF-R"), (10, "CF-L"), (11, "LW"),
        ])))
        XCTAssertEqual(placements.count, 11)
        XCTAssertEqual(Set(placements.map(\.line)).count, 4)
        // Keeper deepest, attack highest.
        let depths = placements.sorted { $0.line < $1.line }.map(\.depth)
        XCTAssertEqual(depths, depths.sorted())
    }

    func testNilWithoutAFullXI() {
        XCTAssertNil(SoccerFormationLayout.place(lineup("4-4-2", [(1, "G"), (2, "RB")])))
        XCTAssertNil(SoccerFormationLayout.place(SoccerLineup(teamName: "No formation")))
    }
}
