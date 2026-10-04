//
//  SoccerMatchAnalytics.swift
//  SportsCalModel
//
//  The numbers ESPN doesn't publish but its shot coordinates let us estimate:
//  expected goals per shot, and a momentum series for the match. Both are pure
//  functions of the play-by-play so the server builds them once per fetch.
//
//  Coordinates follow ESPN's commentary convention (see `SoccerShot.x`/`.y`):
//  0–100 from the acting team's view, attacking toward x = 100.
//

import Foundation

// MARK: - Expected goals

/// A small location-based xG model: a logistic curve over distance to goal and the
/// angle the goal mouth subtends, fitted to published benchmarks for footed
/// open-play shots, then adjusted for headers, fast breaks and penalties.
///
/// It is an estimate, not Opta's model — no defender positions or shot height — so
/// the app labels it "xG (est.)". Over 708 shots from the top leagues in Sept 2026
/// it summed to 60.2 against 67 non-penalty goals.
public enum SoccerExpectedGoals {
    static let pitchLength = 105.0
    static let pitchWidth = 68.0
    static let goalWidth = 7.32

    static let intercept = -1.6253
    static let angleCoefficient = 1.4743
    static let distanceCoefficient = -0.0901

    /// Conversion rate of a penalty kick across the big European leagues.
    public static let penalty = 0.76

    public static func estimate(
        x: Double,
        y: Double,
        bodyPart: SoccerShotBodyPart,
        situation: SoccerShotSituation
    ) -> Double {
        if situation == .penalty { return penalty }
        let (distance, angle) = geometry(x: x, y: y)
        let z = intercept + angleCoefficient * angle + distanceCoefficient * distance
        var xG = 1 / (1 + exp(-z))
        if bodyPart == .head { xG *= 0.55 }
        if situation == .fastBreak { xG *= 1.2 }
        return min(max(xG, 0.005), 0.95)
    }

    /// Distance to the centre of the goal (metres) and the angle the goal mouth
    /// subtends from the shot (radians).
    static func geometry(x: Double, y: Double) -> (distance: Double, angle: Double) {
        let dx = (100 - x) / 100 * pitchLength
        let dy = (y - 50) / 100 * pitchWidth
        let distance = (dx * dx + dy * dy).squareRoot()
        var angle = atan2(goalWidth * dx, dx * dx + dy * dy - (goalWidth / 2) * (goalWidth / 2))
        if angle < 0 { angle += .pi }
        return (distance, angle)
    }
}

// MARK: - Shot description parsing

/// Reads what ESPN's coordinates don't carry — body part and situation — from the
/// shot's narration, e.g. "Attempt saved. Evanilson (Bournemouth) left footed shot
/// from the left side of the six yard box … following a fast break."
public enum SoccerShotText {
    public static func bodyPart(_ text: String) -> SoccerShotBodyPart {
        let lower = text.lowercased()
        if lower.contains("header") || lower.contains("with a header") { return .head }
        if lower.contains("left footed") { return .leftFoot }
        if lower.contains("right footed") { return .rightFoot }
        return .other
    }

    /// `typeKey` is ESPN's play type slug, e.g. "penalty---scored", "goal---free-kick".
    public static func situation(_ text: String, typeKey: String) -> SoccerShotSituation {
        let lower = text.lowercased()
        if typeKey.contains("penalty") || lower.contains("penalty saved") || lower.contains("penalty missed")
            || lower.contains("converts the penalty") {
            return .penalty
        }
        if typeKey.contains("free-kick") || lower.contains("direct free kick") || lower.contains("from a free kick") {
            return .directFreeKick
        }
        if lower.contains("fast break") { return .fastBreak }
        if lower.contains("following a corner") || lower.contains("following a set piece")
            || lower.contains("from a corner") {
            return .setPiece
        }
        return .openPlay
    }

    /// Maps an ESPN play type slug to a shot outcome; nil for plays that aren't shots
    /// (and for own goals, which aren't a shot by the team they count for).
    public static func outcome(typeKey: String, text: String) -> SoccerShotOutcome? {
        switch typeKey {
        case "own-goal": return nil
        case "shot-on-target": return .saved
        case "shot-off-target": return .missed
        case "shot-blocked": return .blocked
        case "shot-hit-woodwork": return .woodwork
        default: break
        }
        if typeKey.hasPrefix("goal") || typeKey == "penalty---scored" { return .goal }
        if typeKey.hasPrefix("penalty---") {
            return typeKey.contains("saved") ? .saved : .missed
        }
        return nil
    }
}

// MARK: - Momentum

/// Builds FotMob-style momentum from where things happen: each located action is
/// worth more the closer to the opponent's goal it is, shots and corners more than
/// fouls won, and the per-minute home-minus-away balance is smoothed so a spell of
/// pressure reads as one wave rather than a picket fence.
public enum SoccerMomentum {
    /// One located action, from the acting team's view (attacking toward x = 100).
    public struct Action: Equatable {
        public enum Kind: Equatable { case goal, shot, corner, offside, freeKickWon }

        public var minute: Double
        public var side: BracketSide
        public var x: Double
        public var kind: Kind

        public init(minute: Double, side: BracketSide, x: Double, kind: Kind) {
            self.minute = minute
            self.side = side
            self.x = x
            self.kind = kind
        }
    }

    public static func compute(_ actions: [Action], through lastMinute: Int? = nil) -> [SoccerMomentumPoint] {
        guard !actions.isEmpty else { return [] }
        let end = max(lastMinute ?? 0, Int(actions.map(\.minute).max() ?? 0) + 1)
        var raw = Array(repeating: 0.0, count: end + 1)
        for action in actions {
            let minute = min(max(Int(action.minute), 0), end)
            let signed = threat(action) * (action.side == .home ? 1 : -1)
            raw[minute] += signed
        }

        // Gaussian smoothing, σ ≈ 1.5 minutes.
        let radius = 4
        let sigma = 1.5
        let kernel = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        var smoothed = Array(repeating: 0.0, count: raw.count)
        for i in raw.indices {
            var total = 0.0
            for (k, weight) in kernel.enumerated() {
                let j = i + k - radius
                if raw.indices.contains(j) { total += raw[j] * weight }
            }
            smoothed[i] = total
        }

        let peak = smoothed.map(abs).max() ?? 0
        guard peak > 0 else { return [] }
        return smoothed.enumerated().map { minute, value in
            SoccerMomentumPoint(minute: minute, value: (value / peak * 100).rounded() / 100)
        }
    }

    /// A small floor for any action, rising sharply through the opponent's half.
    static func threat(_ action: Action) -> Double {
        let depth = max(0, (action.x - 50) / 50)
        let weight: Double
        switch action.kind {
        case .goal: weight = 4
        case .shot: weight = 3
        case .corner: weight = 2
        case .offside: weight = 1
        case .freeKickWon: weight = 1
        }
        return weight * (0.25 + depth * depth)
    }
}
