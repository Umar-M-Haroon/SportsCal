//
//  SoccerFormationLayout.swift
//  SportsCalModel
//
//  Places a lineup's starters on a pitch from ESPN's formation string and each
//  starter's `formationPlace`.
//
//  ESPN's formation places are Opta's: a fixed slot number per role that is NOT
//  numbered line by line (in a 4-2-3-1 the two holding midfielders are 4 and 8),
//  and its position codes are relative to the line ("LM" is the left of those two
//  holding midfielders). So line membership comes from Opta's per-formation slot
//  table, and left-to-right order within a line from the L/R in the position code.
//  Formations missing from the table fall back to ordering by slot number, which
//  is roughly defence-to-attack.
//

import Foundation

public enum SoccerFormationLayout {
    public struct Placement: Equatable {
        public var player: SoccerLineupPlayer
        /// 0 is the goalkeeper's line, rising toward the attack.
        public var line: Int
        public var lineCount: Int
        /// 0…1 across the pitch from the team's right touchline to its left.
        public var across: Double
        /// 0…1 up the pitch from the team's own goal line to halfway.
        public var depth: Double
    }

    /// Lines (defence → attack, excluding the keeper) of formation places per formation,
    /// each listed from the team's right to its left. From Opta's formation diagrams.
    static let slotLines: [String: [[Int]]] = [
        "4-4-2": [[2, 5, 6, 3], [7, 4, 8, 11], [10, 9]],
        "4-1-2-1-2": [[2, 5, 6, 3], [4], [7, 11], [8], [10, 9]],
        "4-3-3": [[2, 5, 6, 3], [7, 4, 8], [10, 9, 11]],
        "4-5-1": [[2, 5, 6, 3], [7, 4, 10, 8, 11], [9]],
        "4-4-1-1": [[2, 5, 6, 3], [7, 4, 8, 11], [10], [9]],
        "4-1-4-1": [[2, 5, 6, 3], [4], [7, 8, 10, 11], [9]],
        "4-2-3-1": [[2, 5, 6, 3], [8, 4], [7, 10, 11], [9]],
        "4-3-2-1": [[2, 5, 6, 3], [7, 4, 8], [10, 11], [9]],
        "4-2-2-2": [[2, 5, 6, 3], [8, 4], [7, 11], [10, 9]],
        "4-3-1-2": [[2, 5, 6, 3], [7, 4, 11], [8], [10, 9]],
        "4-1-3-2": [[2, 5, 6, 3], [4], [7, 8, 11], [10, 9]],
        "5-3-2": [[2, 6, 5, 4, 3], [7, 8, 11], [10, 9]],
        "5-4-1": [[2, 6, 5, 4, 3], [7, 8, 10, 11], [9]],
        "3-5-2": [[6, 5, 4], [2, 7, 11, 8, 3], [10, 9]],
        "3-4-3": [[6, 5, 4], [2, 7, 8, 3], [10, 9, 11]],
        "3-4-2-1": [[6, 5, 4], [2, 7, 8, 3], [10, 11], [9]],
        "3-4-1-2": [[6, 5, 4], [2, 7, 8, 3], [11], [10, 9]],
        "3-1-4-2": [[5, 4, 6], [8], [2, 7, 11, 3], [9, 10]],
        "3-5-1-1": [[6, 5, 4], [2, 7, 11, 8, 3], [10], [9]],
    ]

    /// Nil unless the lineup has a formation and exactly eleven placed starters.
    public static func place(_ lineup: SoccerLineup) -> [Placement]? {
        guard let formation = lineup.formation?.trimmingCharacters(in: .whitespaces) else { return nil }
        let counts = formation.split(separator: "-").compactMap { Int($0) }
        let starters = lineup.starters.filter { $0.formationPlace != nil }
        guard counts.reduce(0, +) == 10, starters.count == 11 else { return nil }
        let bySlot = Dictionary(starters.map { ($0.formationPlace!, $0) }, uniquingKeysWith: { first, _ in first })
        guard let keeper = bySlot[1] else { return nil }

        let outfieldLines: [[SoccerLineupPlayer]]
        if let table = slotLines[formation],
           Set(table.joined()) == Set(bySlot.keys).subtracting([1]) {
            outfieldLines = table.map { line in line.compactMap { bySlot[$0] } }
        } else {
            // Unmapped formation: chunk the outfield by slot number.
            var remaining = starters.filter { $0.formationPlace != 1 }.sorted { $0.formationPlace! < $1.formationPlace! }
            var lines: [[SoccerLineupPlayer]] = []
            for count in counts {
                lines.append(Array(remaining.prefix(count)))
                remaining.removeFirst(min(count, remaining.count))
            }
            outfieldLines = lines
        }

        let lines = [[keeper]] + outfieldLines.map(orderedRightToLeft)
        let lineCount = lines.count
        var placements: [Placement] = []
        for (lineIndex, players) in lines.enumerated() {
            // The keeper sits far enough off the goal line for its name label; outfield
            // lines spread up to a clear gap short of halfway, so the two front lines
            // don't touch.
            let depth = lineIndex == 0 ? 0.13 : 0.32 + 0.52 * Double(lineIndex - 1) / Double(max(lineCount - 2, 1))
            for (i, player) in players.enumerated() {
                let across = (Double(i) + 0.5) / Double(players.count)
                placements.append(Placement(player: player, line: lineIndex, lineCount: lineCount, across: across, depth: depth))
            }
        }
        return placements
    }

    /// Stable sort by the side in the position code: right, centre, left. The slot
    /// table's own order breaks ties.
    static func orderedRightToLeft(_ players: [SoccerLineupPlayer]) -> [SoccerLineupPlayer] {
        players.enumerated().sorted { lhs, rhs in
            let l = lateralRank(lhs.element.position), r = lateralRank(rhs.element.position)
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// 0 right, 1 centre, 2 left — from codes like "RB", "CD-R", "LM", "CF-L", "AM".
    static func lateralRank(_ position: String?) -> Int {
        guard let code = position?.uppercased(), !code.isEmpty else { return 1 }
        if code.hasSuffix("-R") { return 0 }
        if code.hasSuffix("-L") { return 2 }
        if ["RB", "RWB", "RM", "RW", "RF"].contains(code) { return 0 }
        if ["LB", "LWB", "LM", "LW", "LF"].contains(code) { return 2 }
        return 1
    }
}
