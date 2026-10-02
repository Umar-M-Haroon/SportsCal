//
//  TeamStatComparison.swift
//  SportsCalModel
//
//  Side-by-side team stats for one game (shots, possession, yards, rebounds…), built
//  from the box score on ESPN's per-event summary.
//

import Foundation

/// The rows of a head-to-head team stats panel, in display order.
public struct TeamStatComparison: Codable, Equatable, Hashable, Sendable {
    public var rows: [Row]

    public struct Row: Codable, Equatable, Hashable, Sendable, Identifiable {
        /// ESPN stat name, for identity.
        public var name: String
        public var label: String
        public var home: String
        public var away: String
        /// For stats where fewer is better (turnovers, penalties, errors), so the
        /// bar highlights the right side.
        public var lowerIsBetter: Bool?

        public var id: String { name }

        public init(name: String, label: String, home: String, away: String, lowerIsBetter: Bool? = nil) {
            self.name = name
            self.label = label
            self.home = home
            self.away = away
            self.lowerIsBetter = lowerIsBetter
        }

        /// Numeric values for proportional bars. "50-97" and "22/40" read as the made
        /// count, "31:11" as seconds, "42.7" and "52%" as themselves.
        public var homeValue: Double? { Self.numeric(home) }
        public var awayValue: Double? { Self.numeric(away) }

        static func numeric(_ text: String) -> Double? {
            let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
            if trimmed.contains(":") {
                let parts = trimmed.split(separator: ":").compactMap { Double($0) }
                guard parts.count == 2 else { return nil }
                return parts[0] * 60 + parts[1]
            }
            if let separator = trimmed.firstIndex(where: { $0 == "-" || $0 == "/" }), separator != trimmed.startIndex {
                return Double(trimmed[..<separator])
            }
            return Double(trimmed.replacingOccurrences(of: ",", with: ""))
        }
    }

    public init(rows: [Row]) {
        self.rows = rows
    }
}

// MARK: - Building from the ESPN summary

public extension TeamStatComparison {
    /// One curated stat: where it lives in the box score and how to show it.
    struct Spec: Sendable {
        /// ESPN stat name. For baseball, prefixed with its category: "batting.hits".
        let name: String
        let label: String
        let lowerIsBetter: Bool
        /// Multiplies the value for display, for ESPN's 0...1 fractions shown as percents.
        let percentOfOne: Bool

        init(_ name: String, _ label: String, lowerIsBetter: Bool = false, percentOfOne: Bool = false) {
            self.name = name
            self.label = label
            self.lowerIsBetter = lowerIsBetter
            self.percentOfOne = percentOfOne
        }
    }

    /// The stats worth a row, per sport. ESPN's boxes run to 25+ (baseball's to 150+);
    /// these are the ones that say how a game is going.
    static func specs(for sport: SportType) -> [Spec] {
        switch sport {
        case .nfl:
            return [
                Spec("totalYards", "Total Yards"),
                Spec("netPassingYards", "Passing"),
                Spec("rushingYards", "Rushing"),
                Spec("firstDowns", "1st Downs"),
                Spec("thirdDownEff", "3rd Down"),
                Spec("redZoneAttempts", "Red Zone"),
                Spec("turnovers", "Turnovers", lowerIsBetter: true),
                Spec("totalPenaltiesYards", "Penalties", lowerIsBetter: true),
                Spec("possessionTime", "Possession"),
            ]
        case .basketball:
            return [
                Spec("fieldGoalsMade-fieldGoalsAttempted", "Field Goals"),
                Spec("fieldGoalPct", "FG %"),
                Spec("threePointFieldGoalsMade-threePointFieldGoalsAttempted", "3-Pointers"),
                Spec("freeThrowsMade-freeThrowsAttempted", "Free Throws"),
                Spec("totalRebounds", "Rebounds"),
                Spec("assists", "Assists"),
                Spec("turnovers", "Turnovers", lowerIsBetter: true),
                Spec("pointsInPaint", "Points in Paint"),
                Spec("fastBreakPoints", "Fast Break"),
                Spec("largestLead", "Largest Lead"),
            ]
        case .hockey:
            return [
                Spec("shotsTotal", "Shots"),
                Spec("powerPlayGoals", "Power Play Goals"),
                Spec("faceoffPercent", "Faceoff %"),
                Spec("hits", "Hits"),
                Spec("blockedShots", "Blocked Shots"),
                Spec("takeaways", "Takeaways"),
                Spec("giveaways", "Giveaways", lowerIsBetter: true),
                Spec("penaltyMinutes", "Penalty Minutes", lowerIsBetter: true),
            ]
        case .soccer:
            return [
                Spec("possessionPct", "Possession"),
                Spec("totalShots", "Shots"),
                Spec("shotsOnTarget", "On Target"),
                Spec("wonCorners", "Corners"),
                Spec("passPct", "Pass Accuracy", percentOfOne: true),
                Spec("foulsCommitted", "Fouls", lowerIsBetter: true),
                Spec("offsides", "Offsides", lowerIsBetter: true),
                Spec("yellowCards", "Yellow Cards", lowerIsBetter: true),
                Spec("saves", "Saves"),
            ]
        case .mlb:
            return [
                Spec("batting.hits", "Hits"),
                Spec("batting.homeRuns", "Home Runs"),
                Spec("batting.walks", "Walks"),
                Spec("batting.strikeouts", "Strikeouts", lowerIsBetter: true),
                Spec("batting.runnersLeftOnBase", "Left on Base", lowerIsBetter: true),
                Spec("fielding.errors", "Errors", lowerIsBetter: true),
                Spec("pitching.pitches", "Pitches Thrown", lowerIsBetter: true),
            ]
        case .golf, .tennis, .racing:
            return []
        }
    }

    /// Builds the comparison from a summary box score. Nil when the box is missing a
    /// side or nothing curated is present (a game that hasn't started).
    init?(boxscore: ESPNSummaryBoxscore?, sport: SportType) {
        guard let teams = boxscore?.teams,
              let home = teams.first(where: { $0.homeAway == "home" }),
              let away = teams.first(where: { $0.homeAway == "away" }) else { return nil }
        let homeStats = home.flattenedStats()
        let awayStats = away.flattenedStats()

        let rows: [Row] = Self.specs(for: sport).compactMap { spec in
            guard let h = homeStats[spec.name], let a = awayStats[spec.name] else { return nil }
            return Row(
                name: spec.name,
                label: spec.label,
                home: spec.format(h, sport: sport),
                away: spec.format(a, sport: sport),
                lowerIsBetter: spec.lowerIsBetter ? true : nil
            )
        }
        guard !rows.isEmpty else { return nil }
        self.init(rows: rows)
    }
}

extension TeamStatComparison.Spec {
    func format(_ value: String, sport: SportType) -> String {
        if percentOfOne, let fraction = Double(value) {
            return "\(Int((fraction * 100).rounded()))%"
        }
        // Possession in soccer and plain percentages read better with the sign.
        if name == "possessionPct" || name.hasSuffix("Pct") || name.hasSuffix("Percent") {
            return value.hasSuffix("%") ? value : "\(value)%"
        }
        return value
    }
}

// MARK: - ESPN summary box score

public struct ESPNSummaryBoxscore: Codable {
    public var teams: [Team]?

    public struct Team: Codable {
        public var homeAway: String?
        public var statistics: [Stat]?

        /// Most sports list stats flat; baseball nests them under batting/pitching/
        /// fielding categories. Either way, flatten to name → display value, with
        /// nested names prefixed by their category.
        func flattenedStats() -> [String: String] {
            var out: [String: String] = [:]
            for stat in statistics ?? [] {
                if let nested = stat.stats {
                    let category = stat.name ?? ""
                    for inner in nested {
                        guard let name = inner.name, let value = inner.displayValue else { continue }
                        out["\(category).\(name)"] = out["\(category).\(name)"] ?? value
                    }
                } else if let name = stat.name, let value = stat.displayValue {
                    out[name] = out[name] ?? value
                }
            }
            return out
        }

        enum CodingKeys: String, CodingKey { case homeAway, statistics }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            homeAway = try? c.decodeIfPresent(String.self, forKey: .homeAway)
            statistics = try? c.decodeIfPresent([Stat].self, forKey: .statistics)
        }
    }

    public struct Stat: Codable {
        public var name: String?
        public var displayValue: String?
        /// Baseball's per-category stats.
        public var stats: [Stat]?

        enum CodingKeys: String, CodingKey { case name, displayValue, stats }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            displayValue = try? c.decodeIfPresent(String.self, forKey: .displayValue)
            stats = try? c.decodeIfPresent([Stat].self, forKey: .stats)
        }
    }

    enum CodingKeys: String, CodingKey { case teams }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teams = try? c.decodeIfPresent([Team].self, forKey: .teams)
    }
}
