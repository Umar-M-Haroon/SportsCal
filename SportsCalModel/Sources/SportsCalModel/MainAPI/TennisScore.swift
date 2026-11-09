//
//  TennisScore.swift
//  SportsCalModel
//
//  A tennis match's score as the views read it: which sets are finished (and who won
//  them), tiebreak points, who's serving, retirements and walkovers.
//
//  The set games live in `homeLinescores` / `awayLinescores`, which can't tell a set in
//  progress from a finished one: 6-4 3-2 is one set each by a naive count. ESPN marks
//  each finished set with `winner` (the set in play has none), so that's carried in
//  `TennisMatchExtras` and preferred; older payloads fall back to the set score.
//

import Foundation

/// Tennis detail from ESPN's scoreboard, on `ScoreboardExtras.tennis`. Every field is
/// optional, so older clients and payloads decode unchanged.
public struct TennisMatchExtras: Codable, Equatable, Hashable, Sendable {
    public struct SetDetail: Codable, Equatable, Hashable, Sendable {
        /// Tiebreak points, when the set went to one.
        public var homeTiebreak: Int?
        public var awayTiebreak: Int?
        /// Who won the set. Nil while it's being played (or when ESPN named nobody, as
        /// for a set cut short by a retirement).
        public var winner: GameSituation.Side?
        /// ESPN has ruled on the set (it carries a `winner` flag either way).
        public var finished: Bool?

        public init(homeTiebreak: Int? = nil, awayTiebreak: Int? = nil, winner: GameSituation.Side? = nil, finished: Bool? = nil) {
            self.homeTiebreak = homeTiebreak
            self.awayTiebreak = awayTiebreak
            self.winner = winner
            self.finished = finished
        }
    }

    public var sets: [SetDetail]?
    /// Who's serving, while the match is live.
    public var server: GameSituation.Side?
    /// "Court Central". Nil until the order of play names one.
    public var court: String?
    /// Play was suspended at some point (rain, darkness).
    public var wasSuspended: Bool?
    /// Tournament seeds.
    public var homeSeed: Int?
    public var awaySeed: Int?

    public init(sets: [SetDetail]? = nil, server: GameSituation.Side? = nil, court: String? = nil,
                wasSuspended: Bool? = nil, homeSeed: Int? = nil, awaySeed: Int? = nil) {
        self.sets = sets
        self.server = server
        self.court = court
        self.wasSuspended = wasSuspended
        self.homeSeed = homeSeed
        self.awaySeed = awaySeed
    }

    /// From an ESPN tennis competition. Nil when it carries none of this.
    init?(competition: Competition, home: Competitor, away: Competitor) {
        let homeSets = home.linescores ?? []
        let awaySets = away.linescores ?? []
        let count = Swift.max(homeSets.count, awaySets.count)
        let sets: [SetDetail] = (0..<count).map { index in
            let h = index < homeSets.count ? homeSets[index] : nil
            let a = index < awaySets.count ? awaySets[index] : nil
            let winner: GameSituation.Side? = h?.winner == true ? .home : (a?.winner == true ? .away : nil)
            let finished = h?.winner != nil || a?.winner != nil
            return SetDetail(homeTiebreak: h?.tiebreak, awayTiebreak: a?.tiebreak, winner: winner, finished: finished ? true : nil)
        }
        let state = competition.status?.type.state
        let server: GameSituation.Side? = state == "in"
            ? (home.possession == true ? .home : (away.possession == true ? .away : nil))
            : nil
        let court = competition.venue?.court?.trimmingCharacters(in: .whitespaces)
        func seed(_ competitor: Competitor) -> Int? {
            competitor.curatedRank?.current.flatMap { (1...64).contains($0) ? $0 : nil }
        }
        let extras = TennisMatchExtras(
            sets: sets.contains(where: { $0 != SetDetail() }) ? sets : nil,
            server: server,
            court: (court?.isEmpty ?? true) ? nil : court,
            wasSuspended: competition.wasSuspended == true ? true : nil,
            homeSeed: seed(home),
            awaySeed: seed(away)
        )
        guard extras != TennisMatchExtras() else { return nil }
        self = extras
    }
}

/// One set as displayed.
public struct TennisSet: Hashable, Sendable {
    public var home: Int?
    public var away: Int?
    public var homeTiebreak: Int?
    public var awayTiebreak: Int?
    /// Nil while the set is in play, or for a set nobody won (retirement mid-set).
    public var winner: GameSituation.Side?
    public var isComplete: Bool

    /// "7⁷" — games, then tiebreak points as a superscript.
    public func text(for side: GameSituation.Side) -> String {
        let games = side == .home ? home : away
        guard let games else { return "-" }
        let tiebreak = side == .home ? homeTiebreak : awayTiebreak
        return "\(games)" + (tiebreak.map(TennisSet.superscript) ?? "")
    }

    /// Spoken form: "7 6, tiebreak 7 5".
    public var spokenText: String {
        let score = "\(home.map(String.init) ?? "-") \(away.map(String.init) ?? "-")"
        guard let ht = homeTiebreak, let at = awayTiebreak else { return score }
        return "\(score), tiebreak \(ht) \(at)"
    }

    static func superscript(_ value: Int) -> String {
        let digits: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
                                              "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"]
        return String(String(value).map { digits[$0] ?? $0 })
    }

    /// A finished-looking set score: 6-4, 7-5, 7-6, or a long final set won by two.
    static func isDecisive(_ a: Int, _ b: Int) -> Bool {
        let high = Swift.max(a, b), low = Swift.min(a, b)
        return (high >= 6 && high - low >= 2) || (high == 7 && low == 6)
    }
}

public extension Game {
    /// Sets in order. A set counts as finished when ESPN says so; without that (older
    /// payloads) every set before the last is finished, and the last only once the
    /// match is over or the score is decisive.
    var tennisSets: [TennisSet] {
        let homeGames = homeLinescores ?? []
        let awayGames = awayLinescores ?? []
        let count = Swift.max(homeGames.count, awayGames.count)
        guard count > 0 else { return [] }
        let details = tennisExtras?.sets ?? []
        let matchOver = isTennisMatchOver
        return (0..<count).map { index in
            let h = index < homeGames.count ? Int(homeGames[index]) : nil
            let a = index < awayGames.count ? Int(awayGames[index]) : nil
            let detail = index < details.count ? details[index] : nil
            var set = TennisSet(home: h, away: a, homeTiebreak: detail?.homeTiebreak, awayTiebreak: detail?.awayTiebreak,
                                winner: nil, isComplete: false)
            if let detail, detail.finished == true || detail.winner != nil {
                set.isComplete = true
                set.winner = detail.winner
            } else if !details.isEmpty {
                // ESPN rules on every finished set; one without a ruling is in play.
                set.isComplete = false
            } else if let h, let a {
                let isLast = index == count - 1
                let complete = !isLast || TennisSet.isDecisive(h, a) || (matchOver && h != a && tennisResultMarker == nil)
                set.isComplete = complete
                if complete, h != a { set.winner = h > a ? .home : .away }
            }
            return set
        }
    }

    /// Sets won by each side, counting finished sets only.
    var tennisSetsWon: (home: Int, away: Int) {
        let sets = tennisSets
        return (sets.filter { $0.winner == .home }.count, sets.filter { $0.winner == .away }.count)
    }

    /// The match is over (final, retired, walkover).
    var isTennisMatchOver: Bool {
        strStatus == "post" || isCompleted == true
    }

    /// Who won, once it's over: ESPN's `winner` first (the only reliable call for a
    /// retirement or walkover), else the sets.
    var tennisMatchWinner: GameSituation.Side? {
        if homeWinner == true { return .home }
        if awayWinner == true { return .away }
        guard isTennisMatchOver, tennisResultMarker == nil else { return nil }
        let won = tennisSetsWon
        if won.home == won.away { return nil }
        return won.home > won.away ? .home : .away
    }

    /// "ret." or "w/o" when the match ended early.
    var tennisResultMarker: String? {
        let text = (strProgress ?? "").lowercased()
        if text.contains("walkover") || text == "w/o" || text == "wo" { return "w/o" }
        if text.contains("retired") || text.hasPrefix("ret") { return "ret." }
        if text.contains("default") { return "def." }
        return nil
    }

    /// Who's serving, while the match is live.
    var tennisServer: GameSituation.Side? {
        strStatus == "in" ? tennisExtras?.server : nil
    }

    /// A rain delay or suspension, as ESPN words it ("Suspended", "Rain Delay").
    var tennisStoppageText: String? {
        guard !isTennisMatchOver, let progress = strProgress else { return nil }
        let lower = progress.lowercased()
        for marker in ["suspended", "delay", "rain", "postponed", "interrupted"] where lower.contains(marker) {
            return progress
        }
        return nil
    }

    var tennisHomeSeed: Int? { tennisExtras?.homeSeed }
    var tennisAwaySeed: Int? { tennisExtras?.awaySeed }
    var tennisCourt: String? { tennisExtras?.court }

    /// Singles or doubles, from the draw slug.
    var isTennisDoubles: Bool {
        drawSlug?.contains("doubles") ?? false
    }
}

// MARK: - Live Activity

/// Tennis Live Activity content: the games in every set, tiebreaks and who's serving.
/// Rides in the Live Activity `ContentState` as an optional field next to `race`;
/// `homeScore` / `awayScore` carry sets won. Built in one place so the app's foreground
/// updates and the server's pushes agree.
public struct LiveActivityTennis: Codable, Hashable, Sendable {
    public struct SetScore: Codable, Hashable, Sendable {
        public var home: Int
        public var away: Int
        public var homeTiebreak: Int?
        public var awayTiebreak: Int?
        public var winner: GameSituation.Side?

        public init(home: Int, away: Int, homeTiebreak: Int? = nil, awayTiebreak: Int? = nil, winner: GameSituation.Side? = nil) {
            self.home = home
            self.away = away
            self.homeTiebreak = homeTiebreak
            self.awayTiebreak = awayTiebreak
            self.winner = winner
        }

        public func text(for side: GameSituation.Side) -> String {
            TennisSet(home: home, away: away, homeTiebreak: homeTiebreak, awayTiebreak: awayTiebreak,
                      winner: winner, isComplete: winner != nil).text(for: side)
        }
    }

    public var sets: [SetScore]
    public var server: GameSituation.Side?
    /// "ret." / "w/o" when it ended early.
    public var marker: String?
    public var winner: GameSituation.Side?

    public init(sets: [SetScore], server: GameSituation.Side? = nil, marker: String? = nil, winner: GameSituation.Side? = nil) {
        self.sets = sets
        self.server = server
        self.marker = marker
        self.winner = winner
    }

    public init?(game: Game) {
        guard game.isTennisMatch else { return nil }
        self.sets = game.tennisSets.compactMap { set in
            guard let home = set.home, let away = set.away else { return nil }
            return SetScore(home: home, away: away, homeTiebreak: set.homeTiebreak, awayTiebreak: set.awayTiebreak, winner: set.winner)
        }
        self.server = game.tennisServer
        self.marker = game.tennisResultMarker
        self.winner = game.tennisMatchWinner
    }
}
