//
//  TeamSeasonStats.swift
//  SportsCalModel
//
//  Where a team ranks in its league on the stats that matter — "3rd in points per
//  game, 28th in ERA" — for the team page. From ESPN's core API team statistics.
//

import Foundation

public struct TeamSeasonStats: Codable, Equatable, Hashable, Sendable {
    /// ESPN's season label, e.g. "2026" or "2025-26".
    public var season: String
    /// True when the current season has no regular-season stats yet (preseason) and
    /// these are last season's.
    public var isPreviousSeason: Bool
    public var stats: [Stat]

    public struct Stat: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var name: String
        public var label: String
        public var value: String
        /// League rank where 1 is best. See `TeamSeasonStats.specs(for:)`.
        public var rank: Int?
        /// ESPN's rank text: "3rd", "Tied-12th".
        public var rankDisplay: String?

        public var id: String { name }

        public init(name: String, label: String, value: String, rank: Int?, rankDisplay: String?) {
            self.name = name
            self.label = label
            self.value = value
            self.rank = rank
            self.rankDisplay = rankDisplay
        }
    }

    public init(season: String, isPreviousSeason: Bool, stats: [Stat]) {
        self.season = season
        self.isPreviousSeason = isPreviousSeason
        self.stats = stats
    }
}

// MARK: - Building from ESPN

public extension TeamSeasonStats {
    struct Spec: Sendable {
        /// "category.name" in ESPN's core statistics.
        let key: String
        let label: String
        /// Show the per-game figure rather than the season total. Computed from the total
        /// and games played: ESPN's own per-game value is rounded to a whole number.
        let perGame: Bool

        init(_ key: String, _ label: String, perGame: Bool = false) {
            self.key = key
            self.label = label
            self.perGame = perGame
        }
    }

    /// The stats shown per league.
    ///
    /// ESPN's rank isn't "1 = best": each stat ranks in a fixed direction, so the team
    /// with the *most* turnovers ranks 1st in turnovers, and NHL goals-against ranks
    /// the leakiest defence 1st while goals-against-average ranks the stingiest 1st.
    /// Every stat here was checked against every team in its league (October 2026)
    /// to confirm its 1st is also its best, so a rank can be read as praise.
    static func specs(for league: Leagues) -> [Spec] {
        switch league {
        case .nfl:
            return [
                Spec("scoring.totalPointsPerGame", "Points / Game"),
                Spec("passing.yardsPerGame", "Yards / Game"),
                Spec("passing.passingYardsPerGame", "Passing / Game"),
                Spec("rushing.rushingYardsPerGame", "Rushing / Game"),
                Spec("miscellaneous.thirdDownConvPct", "3rd Down %"),
                Spec("miscellaneous.redzoneScoringPct", "Red Zone %"),
                Spec("miscellaneous.turnOverDifferential", "Turnover Diff"),
                Spec("defensive.sacks", "Sacks"),
            ]
        // ESPN's college ranks are broken for 3rd down % (every team "1st"), red zone %
        // (reads 0.00) and turnover differential (ranks don't follow the values), so
        // those are left out. The rest were checked across five teams, October 2026.
        case .ncaaf:
            return [
                Spec("scoring.totalPointsPerGame", "Points / Game"),
                Spec("passing.yardsPerGame", "Yards / Game"),
                Spec("passing.passingYardsPerGame", "Passing / Game"),
                Spec("rushing.rushingYardsPerGame", "Rushing / Game"),
                Spec("defensive.sacks", "Sacks"),
                Spec("defensiveInterceptions.interceptions", "Interceptions"),
            ]
        case .nba, .wnba:
            return [
                Spec("offensive.points", "Points / Game", perGame: true),
                Spec("offensive.fieldGoalPct", "FG %"),
                Spec("offensive.threePointPct", "3PT %"),
                Spec("offensive.trueShootingPct", "True Shooting %"),
                Spec("offensive.assists", "Assists / Game", perGame: true),
                Spec("general.reboundRate", "Rebound Rate"),
                Spec("defensive.steals", "Steals / Game", perGame: true),
                Spec("defensive.blocks", "Blocks / Game", perGame: true),
            ]
        case .nhl:
            return [
                Spec("offensive.goals", "Goals"),
                Spec("defensive.avgGoalsAgainst", "Goals Against / Game"),
                Spec("general.goalDifferential", "Goal Differential"),
                Spec("offensive.powerPlayPct", "Power Play %"),
                Spec("defensive.penaltyKillPct", "Penalty Kill %"),
                Spec("defensive.savePct", "Save %"),
                Spec("offensive.shootingPct", "Shooting %"),
            ]
        case .mlb:
            return [
                Spec("batting.runs", "Runs"),
                Spec("batting.homeRuns", "Home Runs"),
                Spec("batting.avg", "Batting Avg"),
                Spec("batting.OPS", "OPS"),
                Spec("pitching.ERA", "ERA"),
                Spec("pitching.WHIP", "WHIP"),
                Spec("pitching.strikeouts", "Strikeouts (Pitching)"),
                Spec("fielding.errors", "Errors"),
            ]
        default:
            return []
        }
    }

    /// Nil when nothing curated is present, e.g. a season that hasn't started.
    init?(espn: ESPNCoreTeamStatistics, league: Leagues, season: String, isPreviousSeason: Bool) {
        var byKey: [String: ESPNCoreTeamStatistics.Stat] = [:]
        for category in espn.splits?.categories ?? [] {
            for stat in category.stats ?? [] {
                guard let name = stat.name, let categoryName = category.name else { continue }
                byKey["\(categoryName).\(name)"] = byKey["\(categoryName).\(name)"] ?? stat
            }
        }
        let gamesPlayed = byKey["general.gamesPlayed"]?.value
        let stats: [Stat] = Self.specs(for: league).compactMap { spec in
            guard let stat = byKey[spec.key] else { return nil }
            let value: String?
            if spec.perGame, let total = stat.value, let games = gamesPlayed, games > 0 {
                value = String(format: "%.1f", total / games)
            } else {
                value = stat.displayValue
            }
            guard let value else { return nil }
            return Stat(name: spec.key, label: spec.label, value: value, rank: stat.rank, rankDisplay: stat.rankDisplayValue)
        }
        guard !stats.isEmpty else { return nil }
        self.init(season: season, isPreviousSeason: isPreviousSeason, stats: stats)
    }
}

/// ESPN core API `…/seasons/{year}/types/2/teams/{id}/statistics`, reduced to what's read.
public struct ESPNCoreTeamStatistics: Codable {
    public var splits: Splits?

    public struct Splits: Codable {
        public var categories: [Category]?
    }

    public struct Category: Codable {
        public var name: String?
        public var stats: [Stat]?
    }

    public struct Stat: Codable {
        public var name: String?
        public var value: Double?
        public var displayValue: String?
        public var rank: Int?
        public var rankDisplayValue: String?

        enum CodingKeys: String, CodingKey { case name, value, displayValue, rank, rankDisplayValue }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            value = try? c.decodeIfPresent(Double.self, forKey: .value)
            displayValue = try? c.decodeIfPresent(String.self, forKey: .displayValue)
            // Usually an integer; tolerate "3" or 3.0.
            if let int = try? c.decodeIfPresent(Int.self, forKey: .rank) {
                rank = int
            } else if let double = try? c.decodeIfPresent(Double.self, forKey: .rank) {
                rank = Int(double)
            } else {
                rank = (try? c.decodeIfPresent(String.self, forKey: .rank)).flatMap { $0.flatMap { Int($0) } }
            }
            rankDisplayValue = try? c.decodeIfPresent(String.self, forKey: .rankDisplayValue)
        }
    }
}

/// ESPN core API `…/leagues/{league}/season`: the league's current season.
public struct ESPNCoreSeason: Codable {
    public var year: Int?
    public var displayName: String?
}
