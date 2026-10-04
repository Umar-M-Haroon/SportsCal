//
//  WinProbability.swift
//  SportsCalModel
//
//  A game's win-probability history, and the "worth watching" score derived from it.
//

import Foundation

/// Home win probability after each play, compacted for the wire: a bare array of
/// probabilities plus the indices where each period starts, for chart gridlines.
public struct WinProbabilitySeries: Codable, Equatable, Hashable, Sendable {
    /// Home win probability after each play, 0...1, oldest first.
    public var home: [Double]
    /// Index into `home` where each period after the first begins.
    public var periodStarts: [Int]
    /// The period that begins at each of `periodStarts`. Recorded rather than inferred
    /// from position: a period with no win-probability entries would otherwise shift
    /// every later label by one.
    public var startPeriods: [Int]?

    public init(home: [Double], periodStarts: [Int] = [], startPeriods: [Int]? = nil) {
        self.home = home
        self.periodStarts = periodStarts
        self.startPeriods = startPeriods
    }

    /// Each period boundary with its label ("Q2", "H2", "OT", "7th").
    public func boundaries(league: Leagues?) -> [(index: Int, label: String)] {
        periodStarts.enumerated().map { offset, index in
            let period = startPeriods.flatMap { offset < $0.count ? $0[offset] : nil } ?? offset + 2
            return (index, league?.periodName(period) ?? "\(period)")
        }
    }

    /// Builds the series from a summary's `winprobability` entries, placing period
    /// boundaries by joining each entry's play ID against the play-by-play.
    public init?(entries: [ESPNWinProbabilityEntry], plays: [Play]) {
        let periodByPlay = Dictionary(
            plays.compactMap { play in play.period?.number.map { (play.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        var home: [Double] = []
        var periodStarts: [Int] = []
        var startPeriods: [Int] = []
        var lastPeriod: Int?
        for entry in entries {
            guard let value = entry.homeWinPercentage else { continue }
            if let id = entry.playId, let period = periodByPlay[id] {
                if let lastPeriod, period > lastPeriod {
                    periodStarts.append(home.count)
                    startPeriods.append(period)
                }
                lastPeriod = period
            }
            home.append(GameSituation.rounded(value))
        }
        guard home.count >= 2 else { return nil }
        self.init(home: home, periodStarts: periodStarts, startPeriods: startPeriods)
    }
}

/// One entry of a summary's `winprobability` array.
public struct ESPNWinProbabilityEntry: Codable, Equatable {
    public var homeWinPercentage: Double?
    public var tiePercentage: Double?
    public var playId: String?

    public init(homeWinPercentage: Double?, tiePercentage: Double? = nil, playId: String? = nil) {
        self.homeWinPercentage = homeWinPercentage
        self.tiePercentage = tiePercentage
        self.playId = playId
    }
}

// MARK: - Excitement

/// How much a finished game is worth watching, 0...100, from its win-probability swings.
///
/// The raw measure is the total movement in win probability across the game, the
/// "excitement index" used in sports analytics, with the last quarter of the game
/// counted twice so a late collapse outranks an early one. Raw values aren't comparable
/// across sports (a basketball game has ~480 plays to a baseball game's ~80), so each
/// league maps onto 0...100 through anchors measured from real games: its 10th, 50th and
/// 90th percentile land on 10, 50 and 90.
///
/// Anchors were measured in October 2026 from 117 completed games pulled from ESPN:
/// 40 NFL (2026 weeks 1–4), 37 NBA (2025–26 season) and 40 MLB (September 2026).
/// WNBA and the NCAA tournament borrow the NBA's; college football borrows the NFL's.
public enum ExcitementIndex {
    /// Total swing with late swings double-counted.
    public static func raw(_ series: [Double]) -> Double {
        guard series.count >= 2 else { return 0 }
        let lateStart = Int(Double(series.count) * 0.75)
        var total = 0.0
        for i in 1..<series.count {
            let step = abs(series[i] - series[i - 1])
            total += i > lateStart ? step * 2 : step
        }
        return total
    }

    struct Anchors {
        let p10: Double, p50: Double, p90: Double
    }

    static func anchors(for league: Leagues) -> Anchors? {
        switch league {
        case .nfl, .ncaaf: return Anchors(p10: 1.81, p50: 5.06, p90: 8.91)
        case .nba, .wnba, .ncaaMBBTournament: return Anchors(p10: 2.51, p50: 8.91, p90: 19.71)
        case .mlb: return Anchors(p10: 1.44, p50: 2.65, p90: 5.33)
        default: return nil
        }
    }

    /// 0...100, or nil for a league ESPN doesn't publish win probability for.
    public static func score(series: [Double], league: Leagues) -> Int? {
        guard series.count >= 10, let anchors = anchors(for: league) else { return nil }
        return score(raw: raw(series), anchors: anchors)
    }

    static func score(raw: Double, anchors a: Anchors) -> Int {
        // Piecewise-linear through (0,0) (p10,10) (p50,50) (p90,90), then on to 100
        // at twice the 90th percentile.
        let points: [(Double, Double)] = [(0, 0), (a.p10, 10), (a.p50, 50), (a.p90, 90), (a.p90 * 2, 100)]
        for i in 1..<points.count where raw <= points[i].0 {
            let (x0, y0) = points[i - 1], (x1, y1) = points[i]
            let t = (raw - x0) / (x1 - x0)
            return Int((y0 + t * (y1 - y0)).rounded())
        }
        return 100
    }
}

/// The label a finished game's excitement earns. Only the top two tiers get shown:
/// the badge exists to point at games worth watching, not to call others dull.
public enum ExcitementTier: Int, Comparable, Sendable {
    case ordinary, close, thriller, classic

    public init(score: Int) {
        switch score {
        case 92...: self = .classic
        case 75...: self = .thriller
        case 50...: self = .close
        default: self = .ordinary
        }
    }

    /// Whether to badge the game at all.
    public var isWorthWatching: Bool { self >= .thriller }

    public var displayName: String {
        switch self {
        case .classic: return "Instant Classic"
        case .thriller: return "Thriller"
        case .close: return "Competitive"
        case .ordinary: return "Decided Early"
        }
    }

    public static func < (lhs: ExcitementTier, rhs: ExcitementTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

public extension Game {
    /// The tier for `excitement`, when the game has one.
    var excitementTier: ExcitementTier? {
        excitement.map(ExcitementTier.init(score:))
    }
}
