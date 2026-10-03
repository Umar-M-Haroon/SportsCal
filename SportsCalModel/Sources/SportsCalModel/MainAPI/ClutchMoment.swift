//
//  ClutchMoment.swift
//  SportsCalModel
//
//  "Tune in now" moments read off a live game's situation: the tying run at the plate
//  in the 9th, a one-score game in the red zone in the 4th, a one-possession game in
//  the last two minutes. Pure, so the server can decide when to alert and tests can
//  pin the rules down.
//

import Foundation

public struct ClutchMoment: Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Baseball, 9th or later: the batting team trails and the tying run is on base or at the plate.
        case tyingRunAtPlate
        /// Baseball, 9th or later, tied: the go-ahead run is in scoring position.
        case goAheadRunInScoringPosition
        /// Baseball, 7th or later, within three: bases loaded.
        case basesLoaded
        /// Football, 4th quarter or overtime, one-score game: offense in the red zone.
        case redZone
        /// Basketball, final two minutes of the 4th or overtime, within one possession.
        case crunchTime
        /// Hockey, final two minutes of the 3rd, one-goal game.
        case finalMinutesOneGoal
        /// Late, the favourite flipped: win probability crossed 50%.
        case favoriteFlipped
    }

    public let kind: Kind
    public let title: String
    public let body: String
    /// Identifies this occurrence so it alerts once. Two moments with the same key are the
    /// same moment observed on two ticks, e.g. the same inning half's bases-loaded.
    public let key: String

    public init(kind: Kind, title: String, body: String, key: String) {
        self.kind = kind
        self.title = title
        self.body = body
        self.key = key
    }
}

public extension ClutchMoment {
    /// The most important clutch moment in `situation` right now, if any.
    ///
    /// - Parameters:
    ///   - sport: The game's sport; decides which moments apply.
    ///   - league: Sets the period structure (the NCAA tournament plays halves); defaults per sport.
    ///   - situation: The game situation right now.
    ///   - previous: The situation as of the last check, used to spot a win-probability flip.
    ///   - homeScore: Current home score.
    ///   - awayScore: Current away score.
    ///   - homeName: Short home team name for the alert copy.
    ///   - awayName: Short away team name for the alert copy.
    static func detect(
        sport: SportType,
        league: Leagues? = nil,
        situation: GameSituation,
        previous: GameSituation?,
        homeScore: Int,
        awayScore: Int,
        homeName: String,
        awayName: String
    ) -> ClutchMoment? {
        let margin = abs(homeScore - awayScore)
        let scoreLine = "\(awayName) \(awayScore), \(homeName) \(homeScore)"
        let period = situation.period ?? 0
        // The league decides the shape of the game: the NCAA tournament plays halves.
        let league = league ?? Self.defaultLeague(for: sport)
        let finalPeriod = league?.regulationPeriods ?? 4
        func periodName(_ period: Int) -> String { league?.periodName(period) ?? "\(period)" }

        switch sport {
        case .mlb:
            if let moment = baseball(situation, homeScore: homeScore, awayScore: awayScore,
                                     homeName: homeName, awayName: awayName, scoreLine: scoreLine) {
                return moment
            }
        case .nfl:
            if period >= finalPeriod, margin <= 8, situation.isRedZone == true, let side = situation.possession {
                let team = side == .home ? homeName : awayName
                let down = situation.shortDownDistanceText.map { " · \($0)" } ?? ""
                return ClutchMoment(
                    kind: .redZone,
                    title: "\(team) in the red zone",
                    body: "\(periodName(period))\(down) · \(scoreLine)",
                    // One alert per drive: a drive is one possession at one score.
                    key: "redzone-\(period)-\(side.rawValue)-\(awayScore)-\(homeScore)"
                )
            }
        case .basketball:
            if period >= finalPeriod, let clock = situation.clock, clock <= 120, margin <= 3 {
                return ClutchMoment(
                    kind: .crunchTime,
                    title: margin == 0 ? "Tied in the final 2 minutes" : "One-possession game, under 2 minutes",
                    body: "\(periodName(period)) · \(scoreLine)",
                    key: "crunch-\(period)"
                )
            }
        case .hockey:
            if period >= finalPeriod, let clock = situation.clock, clock <= 120, margin == 1 {
                return ClutchMoment(
                    kind: .finalMinutesOneGoal,
                    title: "One-goal game, under 2 minutes",
                    body: "\(periodName(period)) · \(scoreLine)",
                    key: "onegoal-\(period)"
                )
            }
        case .soccer, .golf, .tennis, .racing:
            return nil
        }

        // Late flip of the favourite — after the situation-specific rules, which say more.
        if let regulation = league?.regulationPeriods, period >= (sport == .mlb ? 7 : regulation),
           let now = situation.homeWinProbability,
           let before = previous?.homeWinProbability,
           (before - 0.5) * (now - 0.5) < 0,
           // A wobble across 50% isn't news; require a real move.
           abs(now - before) >= 0.15 {
            let favorite = now > 0.5 ? homeName : awayName
            let percent = Int((max(now, 1 - now) * 100).rounded())
            return ClutchMoment(
                kind: .favoriteFlipped,
                title: "\(favorite) now favored",
                body: "\(percent)% to win · \(scoreLine)",
                key: "flip-\(period)-\(now > 0.5 ? "home" : "away")"
            )
        }
        return nil
    }

    private static func baseball(
        _ s: GameSituation, homeScore: Int, awayScore: Int,
        homeName: String, awayName: String, scoreLine: String
    ) -> ClutchMoment? {
        guard let inning = s.period, let half = s.inningHalf, let batting = half.battingSide else { return nil }
        let outs = s.outs ?? 0
        guard outs < 3 else { return nil }
        let battingScore = batting == .home ? homeScore : awayScore
        let fieldingScore = batting == .home ? awayScore : homeScore
        let deficit = fieldingScore - battingScore
        let team = batting == .home ? homeName : awayName
        let inningText = "\(half == .top ? "Top" : "Bottom") \(ordinal(inning))"
        let outsText = "\(outs) out\(outs == 1 ? "" : "s")"
        let key = "\(inning)\(half.rawValue)"

        if inning >= 9, deficit >= 1, s.runnersOn + 1 >= deficit {
            // The batter is the tying run when exactly enough runners are aboard to tie;
            // with more aboard, the tying run is on base and the batter would win (or lead).
            let title: String
            if s.runnersOn + 1 == deficit {
                title = "\(team): tying run at the plate"
            } else {
                title = batting == .home ? "\(team): winning run at the plate" : "\(team): go-ahead run at the plate"
            }
            return ClutchMoment(
                kind: .tyingRunAtPlate,
                title: title,
                body: "\(inningText), \(outsText) · \(scoreLine)",
                key: "tying-\(key)"
            )
        }
        if inning >= 9, deficit == 0, s.runnerInScoringPosition {
            return ClutchMoment(
                kind: .goAheadRunInScoringPosition,
                title: batting == .home ? "\(team): winning run in scoring position" : "\(team): go-ahead run in scoring position",
                body: "\(inningText), \(outsText) · \(scoreLine)",
                key: "goahead-\(key)"
            )
        }
        if inning >= 7, abs(deficit) <= 3, s.basesLoaded {
            return ClutchMoment(
                kind: .basesLoaded,
                title: "Bases loaded for \(team)",
                body: "\(inningText), \(outsText) · \(scoreLine)",
                key: "loaded-\(key)"
            )
        }
        return nil
    }

    /// The league a sport's moments are judged by when the caller doesn't say.
    static func defaultLeague(for sport: SportType) -> Leagues? {
        switch sport {
        case .basketball: return .nba
        case .nfl: return .nfl
        case .hockey: return .nhl
        case .mlb: return .mlb
        default: return nil
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}

// MARK: - Periods

public extension Leagues {
    /// Periods in regulation: quarters, halves, periods or innings. Nil where it isn't
    /// a fixed count we reason about (soccer, individual sports).
    var regulationPeriods: Int? {
        switch self {
        case .nba, .wnba, .nfl: return 4
        case .ncaaMBBTournament: return 2
        case .nhl: return 3
        case .mlb: return 9
        default: return nil
        }
    }

    /// "Q4", "H2", "P3", "OT", "2OT", or an inning ordinal.
    func periodName(_ period: Int) -> String {
        guard let regulation = regulationPeriods else { return "\(period)" }
        if self == .mlb { return ClutchMoment.ordinal(period) }
        if period <= regulation {
            switch self {
            case .ncaaMBBTournament: return "H\(period)"
            case .nhl: return "P\(period)"
            default: return "Q\(period)"
            }
        }
        let overtime = period - regulation
        return overtime == 1 ? "OT" : "\(overtime)OT"
    }
}
