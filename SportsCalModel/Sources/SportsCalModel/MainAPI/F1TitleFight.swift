//
//  F1TitleFight.swift
//  SportsCalModel
//

import Foundation

/// Championship arithmetic: who can still win, and what the leader needs at the next
/// round to clinch. Pure and source-agnostic so it can be unit tested.
///
/// Points: race 25-18-15-12-10-8-6-4-2-1, sprint 8-7-6-5-4-3-2-1, no fastest-lap point
/// (dropped from 2025). Ties on points go to countback, so a tie never counts as a clinch
/// and a rival who can only tie is still alive.
public struct F1TitleFight: Equatable {
    public enum Kind: Equatable {
        case drivers
        case constructors

        /// Most points one entrant can take from a race / sprint: a constructor
        /// can score 1st and 2nd.
        var raceMax: Int { self == .drivers ? 25 : 25 + 18 }
        var sprintMax: Int { self == .drivers ? 8 : 8 + 7 }
    }

    public struct Contender: Equatable {
        public let name: String
        public let points: Double
        /// Points behind the leader (0 for the leader).
        public let gap: Double
        /// Points total if this entrant wins everything remaining.
        public let maxPossible: Double
        public let isAlive: Bool
    }

    public struct Clinch: Equatable {
        public let leader: String
        /// Points the leader must outscore each rival by at the next round. Zero or
        /// negative means the leader can afford to be outscored by up to
        /// `-points` (i.e. clinches unless the rival outscores them by `1 - points`).
        /// Rivals who can't gain enough in one weekend are omitted. Largest first;
        /// empty means the title is settled at the next round whatever happens.
        public let margins: [(rival: String, points: Int)]

        public static func == (lhs: Clinch, rhs: Clinch) -> Bool {
            lhs.leader == rhs.leader && lhs.margins.map(\.rival) == rhs.margins.map(\.rival)
                && lhs.margins.map(\.points) == rhs.margins.map(\.points)
        }
    }

    public let kind: Kind
    public let pointsAvailable: Int
    public let remainingRaces: Int
    public let remainingSprints: Int
    /// Everyone still mathematically in it, leader first.
    public let contenders: [Contender]
    /// Set when the leader can wrap it up at the next round.
    public let clinchNextRound: Clinch?
    /// Leader's name once nobody can catch them.
    public let champion: String?

    /// - Parameters:
    ///   - standings: entrants in championship order (name, points).
    ///   - nextRoundHasSprint: whether the very next round is a sprint weekend.
    public init?(kind: Kind, standings: [(name: String, points: Double)],
                 remainingRaces: Int, remainingSprints: Int, nextRoundHasSprint: Bool) {
        let ordered = standings.sorted { $0.points > $1.points }
        guard let leader = ordered.first, ordered.count >= 2 else { return nil }

        self.kind = kind
        self.remainingRaces = remainingRaces
        self.remainingSprints = remainingSprints
        let available = remainingRaces * kind.raceMax + remainingSprints * kind.sprintMax
        self.pointsAvailable = available

        let all = ordered.map { entry in
            Contender(
                name: entry.name,
                points: entry.points,
                gap: leader.points - entry.points,
                maxPossible: entry.points + Double(available),
                isAlive: entry.points + Double(available) >= leader.points
            )
        }
        contenders = all.filter(\.isAlive)

        let rivals = contenders.dropFirst()
        champion = rivals.isEmpty ? leader.name : nil

        // Next round: the leader clinches when, afterwards, the lead over every rival
        // exceeds what is left. Margin needed over rival i is (left - lead_i + 1), and
        // swings by at most one weekend's haul either way. Rivals can all score zero
        // together, so it is feasible iff each margin fits inside that haul; a rival
        // needing to gain more than a full weekend can't stop it.
        guard champion == nil, remainingRaces > 0 else {
            clinchNextRound = nil
            return
        }
        let weekendMax = kind.raceMax + (nextRoundHasSprint ? kind.sprintMax : 0)
        let leftAfter = available - weekendMax
        let margins = rivals.compactMap { rival -> (rival: String, points: Int)? in
            let lead = leader.points - rival.points
            let needed = Int((Double(leftAfter) - lead).rounded(.down)) + 1
            return needed > -weekendMax ? (rival.name, needed) : nil
        }
        if margins.allSatisfy({ $0.points <= weekendMax }) {
            clinchNextRound = Clinch(leader: leader.name, margins: margins.sorted { $0.points > $1.points })
        } else {
            clinchNextRound = nil
        }
    }
}

public extension F1Standings {
    /// Title fight for drivers or constructors, or nil when the calendar isn't known.
    func titleFight(_ kind: F1TitleFight.Kind) -> F1TitleFight? {
        guard let remainingRaces, let remainingSprints else { return nil }
        let entries: [(name: String, points: Double)] = switch kind {
        case .drivers: driverStandings.map { ($0.driverName, $0.points) }
        case .constructors: constructorStandings.map { ($0.constructorName, $0.points) }
        }
        return F1TitleFight(kind: kind, standings: entries, remainingRaces: remainingRaces,
                            remainingSprints: remainingSprints, nextRoundHasSprint: nextRoundHasSprint ?? false)
    }
}
