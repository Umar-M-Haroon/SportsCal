//
//  GameSituation.swift
//  SportsCalModel
//
//  The live state of a game beyond its score: count, outs and runners in baseball;
//  down, distance and field position in football; the clock and win probability
//  everywhere ESPN publishes them. Built from the scoreboard's `situation`, carried
//  on `Game` only while the game is in progress.
//

import Foundation

public struct GameSituation: Codable, Equatable, Hashable, Sendable {
    public enum Side: String, Codable, Sendable {
        case home, away

        public var opposite: Side { self == .home ? .away : .home }
    }

    /// Which half of the inning is being played. ESPN only says so in prose
    /// ("Top 9th", "Mid 9th"), so this is parsed from the status detail.
    public enum InningHalf: String, Codable, Sendable {
        case top, middle, bottom, end

        /// The batting side, while one is batting.
        public var battingSide: Side? {
            switch self {
            case .top: return .away
            case .bottom: return .home
            case .middle, .end: return nil
            }
        }
    }

    // MARK: Clock

    /// Period number: quarter, period, inning or half.
    public var period: Int?
    /// Seconds left in the period (counts down in basketball, football and hockey).
    public var clock: Double?

    // MARK: Baseball

    public var inningHalf: InningHalf?
    public var balls: Int?
    public var strikes: Int?
    public var outs: Int?
    public var onFirst: Bool?
    public var onSecond: Bool?
    public var onThird: Bool?
    public var batter: String?
    /// The batter's line for the game, e.g. "1-3, HR".
    public var batterLine: String?
    public var pitcher: String?
    /// The pitcher's line for the game, e.g. "6.0 IP, 2 ER, 7 K".
    public var pitcherLine: String?

    // MARK: Football

    public var down: Int?
    public var distance: Int?
    public var yardLine: Int?
    /// "3rd & 4 at KC 32"
    public var downDistanceText: String?
    /// "3rd & 4"
    public var shortDownDistanceText: String?
    public var possession: Side?
    public var isRedZone: Bool?
    public var homeTimeouts: Int?
    public var awayTimeouts: Int?

    // MARK: Any sport

    /// Which side the last play belonged to.
    public var lastPlaySide: Side?
    /// Home win probability, 0...1. Basketball, football and baseball.
    public var homeWinProbability: Double?
    /// Draw probability, 0...1, where a draw is possible.
    public var tieProbability: Double?

    public init(
        period: Int? = nil, clock: Double? = nil,
        inningHalf: InningHalf? = nil, balls: Int? = nil, strikes: Int? = nil, outs: Int? = nil,
        onFirst: Bool? = nil, onSecond: Bool? = nil, onThird: Bool? = nil,
        batter: String? = nil, batterLine: String? = nil, pitcher: String? = nil, pitcherLine: String? = nil,
        down: Int? = nil, distance: Int? = nil, yardLine: Int? = nil,
        downDistanceText: String? = nil, shortDownDistanceText: String? = nil,
        possession: Side? = nil, isRedZone: Bool? = nil, homeTimeouts: Int? = nil, awayTimeouts: Int? = nil,
        lastPlaySide: Side? = nil, homeWinProbability: Double? = nil, tieProbability: Double? = nil
    ) {
        self.period = period
        self.clock = clock
        self.inningHalf = inningHalf
        self.balls = balls
        self.strikes = strikes
        self.outs = outs
        self.onFirst = onFirst
        self.onSecond = onSecond
        self.onThird = onThird
        self.batter = batter
        self.batterLine = batterLine
        self.pitcher = pitcher
        self.pitcherLine = pitcherLine
        self.down = down
        self.distance = distance
        self.yardLine = yardLine
        self.downDistanceText = downDistanceText
        self.shortDownDistanceText = shortDownDistanceText
        self.possession = possession
        self.isRedZone = isRedZone
        self.homeTimeouts = homeTimeouts
        self.awayTimeouts = awayTimeouts
        self.lastPlaySide = lastPlaySide
        self.homeWinProbability = homeWinProbability
        self.tieProbability = tieProbability
    }

    // MARK: Derived

    /// Away win probability, when home's is known. ESPN's own away figure is
    /// `1 - home - tie` with float noise, so derive it rather than carry it.
    public var awayWinProbability: Double? {
        homeWinProbability.map { max(0, 1 - $0 - (tieProbability ?? 0)) }
    }

    public var runnersOn: Int {
        [onFirst, onSecond, onThird].filter { $0 == true }.count
    }

    public var basesLoaded: Bool { runnersOn == 3 }

    public var runnerInScoringPosition: Bool { onSecond == true || onThird == true }

    /// Whether there's anything to show beyond the clock.
    public var hasBaseballState: Bool {
        outs != nil || balls != nil || onFirst != nil || batter != nil
    }

    public var hasFootballState: Bool {
        down != nil || downDistanceText != nil || possession != nil
    }
}

// MARK: - Building from ESPN

public extension GameSituation {
    /// Builds the situation for one competition, resolving ESPN team IDs to sides so the
    /// result survives the server's ESPN → TheSportsDB team ID translation.
    ///
    /// Returns nil unless the game is in progress: a pre-game or final situation is
    /// either empty or stale, and leaving it off keeps the schedule payload small.
    init?(
        espn situation: Situation?,
        status: Status?,
        sport: SportType,
        homeTeamID: String?,
        awayTeamID: String?
    ) {
        guard status?.type.state == "in" else { return nil }

        func side(_ teamID: String?) -> Side? {
            guard let teamID else { return nil }
            if teamID == homeTeamID { return .home }
            if teamID == awayTeamID { return .away }
            return nil
        }

        self.init()
        period = status?.period
        // Soccer's clock counts up from kickoff and baseball has none; only keep a
        // countdown clock, which is what the clutch rules compare against.
        if sport == .basketball || sport == .nfl || sport == .hockey {
            clock = status?.clock
        }

        if let situation {
            if sport == .mlb {
                balls = situation.balls
                strikes = situation.strikes
                outs = situation.outs
                onFirst = situation.onFirst
                onSecond = situation.onSecond
                onThird = situation.onThird
                batter = situation.batter?.athlete?.shortName ?? situation.batter?.athlete?.displayName
                batterLine = situation.batter?.summary
                pitcher = situation.pitcher?.athlete?.shortName ?? situation.pitcher?.athlete?.displayName
                pitcherLine = situation.pitcher?.summary
            }
            if sport == .nfl {
                down = situation.down
                distance = situation.distance
                yardLine = situation.yardLine
                downDistanceText = situation.downDistanceText
                shortDownDistanceText = situation.shortDownDistanceText
                possession = side(situation.possession)
                isRedZone = situation.isRedZone
                homeTimeouts = situation.homeTimeouts
                awayTimeouts = situation.awayTimeouts
            }
            lastPlaySide = side(situation.lastPlay?.team?.id)
            if let probability = situation.lastPlay?.probability,
               let home = probability.homeWinPercentage {
                homeWinProbability = Self.rounded(home)
                if let tie = probability.tiePercentage, tie > 0 {
                    tieProbability = Self.rounded(tie)
                }
            }
        }
        if sport == .mlb {
            inningHalf = Self.inningHalf(from: status?.type.shortDetail ?? status?.type.detail)
        }
    }

    /// "Top 9th" / "Bot 9th" / "Mid 9th" / "End 9th" → half. Nil for anything else.
    static func inningHalf(from detail: String?) -> InningHalf? {
        guard let word = detail?.lowercased().split(separator: " ").first else { return nil }
        switch word {
        case "top": return .top
        case "bot", "bottom": return .bottom
        case "mid", "middle": return .middle
        case "end": return .end
        default: return nil
        }
    }

    /// Three decimals is finer than any display or rule needs, and stops float noise
    /// from changing the game's signature (and so re-sending it) on every tick.
    static func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }
}
