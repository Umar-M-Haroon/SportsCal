//
//  FantasyScoring.swift
//  SportsCalModel
//
//  How many fantasy points a stat line is worth. A scoring is a weight per stat
//  (`PlayerLiveStatLine.stats` keys plus the derived ones in `FantasyStatKey`) and a
//  few threshold rules (yardage bonuses, D/ST points-allowed tiers).
//
//  Built-in presets, a user's edited copy, or one imported from a Sleeper / ESPN
//  league all share this shape, so every surface scores the same way.
//

import Foundation

public struct FantasyScoring: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// "nfl.halfPPR", "custom.nfl", "sleeper.1180…", "espn.336358".
    public var id: String
    /// "Half-PPR", "My scoring", "Dynasty Degens".
    public var name: String
    public var sport: SportType
    /// Stat key → points per unit (`passing.passingYards` 0.04).
    public var weights: [String: Double]
    /// Points awarded once when a stat lands in a range.
    public var rules: [Rule]

    public init(id: String, name: String, sport: SportType, weights: [String: Double], rules: [Rule] = []) {
        self.id = id
        self.name = name
        self.sport = sport
        self.weights = weights
        self.rules = rules
    }

    /// `points` once `stat` is in `min..<max` (no upper bound when `max` is nil).
    /// A 300-yard passing bonus is `min: 300`; a points-allowed tier is `min: 7, max: 14`.
    public struct Rule: Codable, Equatable, Hashable, Sendable {
        public var stat: String
        public var min: Double
        public var max: Double?
        public var points: Double

        public init(stat: String, min: Double, max: Double? = nil, points: Double) {
            self.stat = stat
            self.min = min
            self.max = max
            self.points = points
        }

        public func applies(to value: Double) -> Bool {
            value >= min && (max.map { value < $0 } ?? true)
        }
    }

    // MARK: Scoring

    /// The line's total. Stats the scoring doesn't weigh count for nothing.
    public func points(_ stats: [String: Double]) -> Double {
        let lines = breakdown(stats)
        return Self.rounded(lines.reduce(0) { $0 + $1.points })
    }

    /// One entry per stat (or rule) that scored, biggest contribution first.
    public func breakdown(_ stats: [String: Double]) -> [Contribution] {
        let values = FantasyStatKey.withDerived(stats, sport: sport)
        var out: [Contribution] = []
        for (key, weight) in weights where weight != 0 {
            guard let value = values[key], value != 0 else { continue }
            out.append(Contribution(stat: key, value: value, points: value * weight, isRule: false))
        }
        for rule in rules where rule.points != 0 {
            // Rules need the stat on the line: a D/ST tier only scores the D/ST line.
            guard let value = values[rule.stat], rule.applies(to: value) else { continue }
            out.append(Contribution(stat: rule.stat, value: value, points: rule.points, isRule: true))
        }
        return out.sorted { abs($0.points) > abs($1.points) }
    }

    public struct Contribution: Equatable, Hashable, Sendable {
        public var stat: String
        public var value: Double
        public var points: Double
        /// A bonus or tier rather than a per-unit weight.
        public var isRule: Bool
    }

    /// Two decimals, the way every fantasy app shows it.
    public static func rounded(_ points: Double) -> Double {
        (points * 100).rounded() / 100
    }

    /// "18.4", "-1", "22.75".
    public static func format(_ points: Double) -> String {
        let value = rounded(points)
        if value == value.rounded() { return String(Int(value)) }
        let tenths = (value * 10).rounded() / 10
        return tenths == value ? String(format: "%.1f", value) : String(format: "%.2f", value)
    }

    /// Whether this scoring weighs anything this stat line could carry (a kicker scoring
    /// on a quarterback still returns true: weights are per stat, not per position).
    public var isEmpty: Bool { weights.values.allSatisfy { $0 == 0 } && rules.isEmpty }
}

// MARK: - Presets

public extension FantasyScoring {
    /// Built-in scorings for a sport, the default first.
    static func presets(for sport: SportType) -> [FantasyScoring] {
        switch sport {
        case .nfl: return [nflHalfPPR, nflPPR, nflStandard]
        default: return []
        }
    }

    static func preset(id: String) -> FantasyScoring? {
        SportType.allCases.lazy.flatMap { presets(for: $0) }.first { $0.id == id }
    }

    static func defaultScoring(for sport: SportType) -> FantasyScoring? {
        presets(for: sport).first
    }

    /// Whether fantasy scoring is available for a sport yet.
    static func supports(_ sport: SportType) -> Bool { !presets(for: sport).isEmpty }

    // NFL: the scoring ESPN, Sleeper and Yahoo default leagues share, differing only in
    // points per reception.

    static let nflStandard = nfl(id: "nfl.standard", name: "Standard", perReception: 0)
    static let nflHalfPPR = nfl(id: "nfl.halfPPR", name: "Half-PPR", perReception: 0.5)
    static let nflPPR = nfl(id: "nfl.ppr", name: "PPR", perReception: 1)

    private static func nfl(id: String, name: String, perReception: Double) -> FantasyScoring {
        typealias K = FantasyStatKey.NFL
        return FantasyScoring(
            id: id,
            name: name,
            sport: .nfl,
            weights: [
                K.passingYards: 0.04,
                K.passingTouchdowns: 4,
                K.interceptionsThrown: -2,
                K.rushingYards: 0.1,
                K.rushingTouchdowns: 6,
                K.receptions: perReception,
                K.receivingYards: 0.1,
                K.receivingTouchdowns: 6,
                K.fumblesLost: -2,
                K.twoPointConversions: 2,
                K.kickReturnTouchdowns: 6,
                K.puntReturnTouchdowns: 6,
                K.fieldGoals0to39: 3,
                K.fieldGoals40to49: 4,
                K.fieldGoals50plus: 5,
                K.fieldGoalsMissed: -1,
                K.extraPointsMade: 1,
                K.extraPointsMissed: -1,
                K.dstSacks: 1,
                K.dstInterceptions: 2,
                K.dstFumblesRecovered: 2,
                K.dstTouchdowns: 6,
                K.dstSafeties: 2,
            ],
            rules: nflPointsAllowedTiers
        )
    }

    /// ESPN's default D/ST points-allowed table.
    static let nflPointsAllowedTiers: [Rule] = [
        Rule(stat: FantasyStatKey.NFL.dstPointsAllowed, min: 0, max: 1, points: 5),
        Rule(stat: FantasyStatKey.NFL.dstPointsAllowed, min: 1, max: 7, points: 4),
        Rule(stat: FantasyStatKey.NFL.dstPointsAllowed, min: 7, max: 14, points: 3),
        Rule(stat: FantasyStatKey.NFL.dstPointsAllowed, min: 14, max: 18, points: 1),
        Rule(stat: FantasyStatKey.NFL.dstPointsAllowed, min: 18, max: 28, points: 0),
        Rule(stat: FantasyStatKey.NFL.dstPointsAllowed, min: 28, max: 35, points: -1),
        Rule(stat: FantasyStatKey.NFL.dstPointsAllowed, min: 35, max: 46, points: -3),
        Rule(stat: FantasyStatKey.NFL.dstPointsAllowed, min: 46, points: -5),
    ]
}

// MARK: - Stat keys

/// The stat keys fantasy scoring reads: `PlayerLiveStatLine` keys as they are, plus a
/// few the server derives from the summary's scoring plays and the D/ST line.
public enum FantasyStatKey {
    public enum NFL {
        public static let passingYards = "passing.passingYards"
        public static let passingTouchdowns = "passing.passingTouchdowns"
        public static let interceptionsThrown = "passing.interceptions"
        public static let completions = "passing.completions"
        public static let passingAttempts = "passing.passingAttempts"
        public static let sacksTaken = "passing.sacks"
        public static let rushingAttempts = "rushing.rushingAttempts"
        public static let rushingYards = "rushing.rushingYards"
        public static let rushingTouchdowns = "rushing.rushingTouchdowns"
        public static let receptions = "receiving.receptions"
        public static let targets = "receiving.receivingTargets"
        public static let receivingYards = "receiving.receivingYards"
        public static let receivingTouchdowns = "receiving.receivingTouchdowns"
        public static let fumbles = "fumbles.fumbles"
        public static let fumblesLost = "fumbles.fumblesLost"
        public static let kickReturnTouchdowns = "kickReturns.kickReturnTouchdowns"
        public static let puntReturnTouchdowns = "puntReturns.puntReturnTouchdowns"
        public static let fieldGoalsMade = "kicking.fieldGoalsMade"
        public static let fieldGoalAttempts = "kicking.fieldGoalAttempts"
        public static let extraPointsMade = "kicking.extraPointsMade"
        public static let extraPointAttempts = "kicking.extraPointAttempts"

        // Derived on the server from scoring plays (`FantasyStatLines`).
        public static let twoPointConversions = "fantasy.twoPointConversions"
        public static let fieldGoals0to39 = "kicking.fg0_39"
        public static let fieldGoals40to49 = "kicking.fg40_49"
        public static let fieldGoals50plus = "kicking.fg50plus"
        // Derived in `withDerived` from the box score's made/attempted columns.
        public static let fieldGoalsMissed = "kicking.fieldGoalsMissed"
        public static let extraPointsMissed = "kicking.extraPointsMissed"

        // D/ST (a synthetic line per team, `FantasyStatLines.dstAthleteID`).
        public static let dstSacks = "dst.sacks"
        public static let dstInterceptions = "dst.interceptions"
        public static let dstFumblesRecovered = "dst.fumblesRecovered"
        public static let dstTouchdowns = "dst.touchdowns"
        public static let dstSafeties = "dst.safeties"
        public static let dstPointsAllowed = "dst.pointsAllowed"
        public static let dstBlockedKicks = "dst.blockedKicks"
    }

    /// `stats` with the keys computed from others filled in (misses from made/attempts;
    /// all made field goals into the 0–39 bucket when the distances never arrived).
    public static func withDerived(_ stats: [String: Double], sport: SportType) -> [String: Double] {
        guard sport == .nfl else { return stats }
        typealias K = NFL
        var out = stats
        if out[K.fieldGoalsMissed] == nil, let attempts = stats[K.fieldGoalAttempts] {
            out[K.fieldGoalsMissed] = max(0, attempts - (stats[K.fieldGoalsMade] ?? 0))
        }
        if out[K.extraPointsMissed] == nil, let attempts = stats[K.extraPointAttempts] {
            out[K.extraPointsMissed] = max(0, attempts - (stats[K.extraPointsMade] ?? 0))
        }
        if let made = stats[K.fieldGoalsMade], made > 0 {
            let bucketed = (stats[K.fieldGoals0to39] ?? 0) + (stats[K.fieldGoals40to49] ?? 0) + (stats[K.fieldGoals50plus] ?? 0)
            if bucketed < made {
                out[K.fieldGoals0to39] = (stats[K.fieldGoals0to39] ?? 0) + (made - bucketed)
            }
        }
        return out
    }

    /// Short label for a breakdown row: "Pass YD", "Rec", "FG 50+".
    public static func label(_ key: String) -> String {
        typealias K = NFL
        switch key {
        case K.passingYards: return "Pass yards"
        case K.passingTouchdowns: return "Pass TD"
        case K.interceptionsThrown: return "Interceptions"
        case K.rushingYards: return "Rush yards"
        case K.rushingTouchdowns: return "Rush TD"
        case K.receptions: return "Receptions"
        case K.receivingYards: return "Rec yards"
        case K.receivingTouchdowns: return "Rec TD"
        case K.fumblesLost: return "Fumbles lost"
        case K.twoPointConversions: return "2-pt conversions"
        case K.kickReturnTouchdowns: return "Kick return TD"
        case K.puntReturnTouchdowns: return "Punt return TD"
        case K.fieldGoalsMade: return "Field goals"
        case K.fieldGoals0to39: return "FG 0–39"
        case K.fieldGoals40to49: return "FG 40–49"
        case K.fieldGoals50plus: return "FG 50+"
        case K.fieldGoalsMissed: return "FG missed"
        case K.extraPointsMade: return "Extra points"
        case K.extraPointsMissed: return "XP missed"
        case K.dstSacks: return "Sacks"
        case K.dstInterceptions: return "Interceptions"
        case K.dstFumblesRecovered: return "Fumble recoveries"
        case K.dstTouchdowns: return "Defensive TD"
        case K.dstSafeties: return "Safeties"
        case K.dstPointsAllowed: return "Points allowed"
        case K.dstBlockedKicks: return "Blocked kicks"
        case K.completions: return "Completions"
        case K.passingAttempts: return "Pass attempts"
        case K.rushingAttempts: return "Carries"
        case K.targets: return "Targets"
        case K.sacksTaken: return "Sacked"
        default: return AlertMilestone.humanized(key).capitalized
        }
    }

    /// The stats a scoring editor offers for a sport, in the order it shows them.
    public static func editable(for sport: SportType) -> [String] {
        typealias K = NFL
        switch sport {
        case .nfl:
            return [K.passingYards, K.passingTouchdowns, K.interceptionsThrown, K.completions, K.passingAttempts,
                    K.sacksTaken, K.rushingYards, K.rushingTouchdowns, K.rushingAttempts, K.receptions,
                    K.receivingYards, K.receivingTouchdowns, K.targets, K.fumblesLost, K.twoPointConversions,
                    K.kickReturnTouchdowns, K.puntReturnTouchdowns, K.fieldGoals0to39, K.fieldGoals40to49,
                    K.fieldGoals50plus, K.fieldGoalsMissed, K.extraPointsMade, K.extraPointsMissed,
                    K.dstSacks, K.dstInterceptions, K.dstFumblesRecovered, K.dstTouchdowns, K.dstSafeties,
                    K.dstBlockedKicks]
        default:
            return []
        }
    }
}

// MARK: - Codable (SportType isn't Codable; the sport travels as its raw value)

struct FantasySportCoding {
    static func decode<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) throws -> SportType {
        let raw = try container.decode(String.self, forKey: key)
        guard let sport = SportType(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Unknown sport \(raw)")
        }
        return sport
    }
}

extension FantasyScoring {
    enum CodingKeys: String, CodingKey { case id, name, sport, weights, rules }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sport = try FantasySportCoding.decode(c, forKey: .sport)
        weights = (try? c.decodeIfPresent([String: Double].self, forKey: .weights)) ?? [:]
        rules = (try? c.decodeIfPresent([Rule].self, forKey: .rules)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(sport.rawValue, forKey: .sport)
        try c.encode(weights, forKey: .weights)
        try c.encode(rules, forKey: .rules)
    }
}
