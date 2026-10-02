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
    ///   - previous: The situation as of the last check, used to spot a win-probability flip.
    ///   - homeName/awayName: Short team names for the alert copy.
    static func detect(
        sport: SportType,
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

        switch sport {
        case .mlb:
            if let moment = baseball(situation, homeScore: homeScore, awayScore: awayScore,
                                     homeName: homeName, awayName: awayName, scoreLine: scoreLine) {
                return moment
            }
        case .nfl:
            if period >= 4, margin <= 8, situation.isRedZone == true, let side = situation.possession {
                let team = side == .home ? homeName : awayName
                let down = situation.shortDownDistanceText.map { " · \($0)" } ?? ""
                return ClutchMoment(
                    kind: .redZone,
                    title: "\(team) in the red zone",
                    body: "\(periodName(sport: sport, period: period))\(down) · \(scoreLine)",
                    // One alert per drive: a drive is one possession at one score.
                    key: "redzone-\(period)-\(side.rawValue)-\(awayScore)-\(homeScore)"
                )
            }
        case .basketball:
            if period >= 4, let clock = situation.clock, clock <= 120, margin <= 3 {
                return ClutchMoment(
                    kind: .crunchTime,
                    title: margin == 0 ? "Tied in the final 2 minutes" : "One-possession game, under 2 minutes",
                    body: "\(periodName(sport: sport, period: period)) · \(scoreLine)",
                    key: "crunch-\(period)"
                )
            }
        case .hockey:
            if period >= 3, let clock = situation.clock, clock <= 120, margin == 1 {
                return ClutchMoment(
                    kind: .finalMinutesOneGoal,
                    title: "One-goal game, under 2 minutes",
                    body: "\(periodName(sport: sport, period: period)) · \(scoreLine)",
                    key: "onegoal-\(period)"
                )
            }
        case .soccer, .golf, .tennis, .racing:
            return nil
        }

        // Late flip of the favourite — after the situation-specific rules, which say more.
        if isLate(sport: sport, period: period),
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

    private static func isLate(sport: SportType, period: Int) -> Bool {
        switch sport {
        case .mlb: return period >= 7
        case .nfl, .basketball: return period >= 4
        case .hockey: return period >= 3
        default: return false
        }
    }

    static func periodName(sport: SportType, period: Int) -> String {
        switch sport {
        case .nfl, .basketball:
            return period <= 4 ? "Q\(period)" : (period == 5 ? "OT" : "\(period - 4)OT")
        case .hockey:
            return period <= 3 ? "P\(period)" : (period == 4 ? "OT" : "\(period - 3)OT")
        default:
            return ordinal(period)
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
