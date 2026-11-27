//
//  FantasySlate.swift
//  SportsCalModel
//
//  One fantasy "slate" — an NFL week, or a day for the other sports — as
//  `/fantasy/:league/slate` serves it: every player line from the slate's games
//  that have started, with season averages. The client scores it with whichever
//  `FantasyScoring` the user picked, so the server never needs to know.
//

import Foundation

public struct FantasySlate: Codable, Equatable, Sendable {
    public var sport: SportType
    public var season: Int
    /// NFL week (regular season); nil for day slates.
    public var week: Int?
    /// "Week 13", "Thu, Nov 26".
    public var label: String
    public var generatedAt: Date
    public var players: [FantasyPlayerLine]
    /// The slate's games, including ones not started (so "My team" can show "Sun 1:00").
    public var games: [Game]?
    /// Weeks a client can ask for, oldest first.
    public var availableWeeks: [Int]?

    public struct Game: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var id: String
        public var date: Date?
        public var state: String?
        public var status: String?
        public var homeTeamID: String?
        public var awayTeamID: String?
        public var homeAbbreviation: String?
        public var awayAbbreviation: String?

        public init(id: String, date: Date? = nil, state: String? = nil, status: String? = nil,
                    homeTeamID: String? = nil, awayTeamID: String? = nil,
                    homeAbbreviation: String? = nil, awayAbbreviation: String? = nil) {
            self.id = id
            self.date = date
            self.state = state
            self.status = status
            self.homeTeamID = homeTeamID
            self.awayTeamID = awayTeamID
            self.homeAbbreviation = homeAbbreviation
            self.awayAbbreviation = awayAbbreviation
        }
    }

    public init(sport: SportType, season: Int, week: Int?, label: String, generatedAt: Date,
                players: [FantasyPlayerLine], games: [Game]? = nil, availableWeeks: [Int]? = nil) {
        self.sport = sport
        self.season = season
        self.week = week
        self.label = label
        self.generatedAt = generatedAt
        self.players = players
        self.games = games
        self.availableWeeks = availableWeeks
    }
}

// MARK: - Studs and stinkers

/// How a player's game is going under one scoring, against what they usually score.
public struct FantasyEvaluation: Equatable, Hashable, Sendable, Identifiable {
    public var line: FantasyPlayerLine
    public var points: Double
    /// Season average under this scoring; nil without history.
    public var averagePoints: Double?
    /// The average scaled to how much of the game has been played.
    public var expectedSoFar: Double?

    public var id: String { line.id }

    /// Points above (+) or below (−) what the player usually has by this point of a game.
    public var delta: Double? { expectedSoFar.map { points - $0 } }

    public init(line: FantasyPlayerLine, scoring: FantasyScoring) {
        self.line = line
        points = scoring.points(line.stats)
        if let average = line.seasonAverage, (line.seasonGames ?? 0) > 0 {
            let averagePoints = scoring.points(average)
            self.averagePoints = averagePoints
            expectedSoFar = FantasyScoring.rounded(averagePoints * Self.progress(of: line))
        }
    }

    /// Final games count in full; a live one by how far along it is.
    static func progress(of line: FantasyPlayerLine) -> Double {
        if line.isFinal { return 1 }
        return min(max(line.gameProgress ?? 0, 0), 1)
    }

    public var verdict: Verdict {
        guard let expected = expectedSoFar, let average = averagePoints,
              average >= FantasyVerdictRules.floor(for: line), Self.progress(of: line) >= FantasyVerdictRules.minimumProgress
        else { return .steady }
        if points >= max(expected * 1.5, expected + FantasyVerdictRules.margin(for: line)) { return .stud }
        if points <= expected * 0.5 { return .stinker }
        return .steady
    }

    public enum Verdict: String, Sendable {
        case stud, stinker, steady
    }
}

public enum FantasyVerdictRules {
    /// A stinker needs half the game played: a slow first quarter isn't a dud.
    public static let minimumProgress = 0.5

    /// Players who average less than this aren't judged: a WR4's quiet day isn't news.
    public static func floor(for line: FantasyPlayerLine) -> Double {
        switch line.position {
        case "K", "DST": return 6
        default: return 9
        }
    }

    /// How far over expectation a big game must be, besides 1.5×.
    public static func margin(for line: FantasyPlayerLine) -> Double {
        switch line.position {
        case "K", "DST": return 5
        default: return 8
        }
    }
}

public extension FantasySlate {
    func evaluations(scoring: FantasyScoring) -> [FantasyEvaluation] {
        players.map { FantasyEvaluation(line: $0, scoring: scoring) }
    }

    /// The slate's top scorers, most points first.
    static func studs(_ evaluations: [FantasyEvaluation], limit: Int = 25) -> [FantasyEvaluation] {
        Array(evaluations.filter { $0.points > 0 }.sorted {
            $0.points != $1.points ? $0.points > $1.points : ($0.delta ?? 0) > ($1.delta ?? 0)
        }.prefix(limit))
    }

    /// Players well short of their usual output, the furthest short first.
    static func stinkers(_ evaluations: [FantasyEvaluation], limit: Int = 25) -> [FantasyEvaluation] {
        Array(evaluations.filter { $0.verdict == .stinker }.sorted {
            ($0.delta ?? 0) < ($1.delta ?? 0)
        }.prefix(limit))
    }

    /// Players blowing past their usual output, the furthest over first.
    static func booms(_ evaluations: [FantasyEvaluation], limit: Int = 25) -> [FantasyEvaluation] {
        Array(evaluations.filter { $0.verdict == .stud }.sorted {
            ($0.delta ?? 0) > ($1.delta ?? 0)
        }.prefix(limit))
    }
}

// MARK: - Display

public extension FantasyPlayerLine {
    /// "22/31, 287 YD, 3 TD, 1 INT · 4 CAR, 21 YD": the stats that drove the score.
    var statSummary: String {
        typealias K = FantasyStatKey.NFL
        func n(_ key: String) -> Int { Int(stats[key] ?? 0) }
        func has(_ key: String) -> Bool { (stats[key] ?? 0) != 0 }
        if isDST {
            var parts: [String] = ["\(n(K.dstPointsAllowed)) PA"]
            if has(K.dstSacks) { parts.append("\(n(K.dstSacks)) SCK") }
            if has(K.dstInterceptions) { parts.append("\(n(K.dstInterceptions)) INT") }
            if has(K.dstFumblesRecovered) { parts.append("\(n(K.dstFumblesRecovered)) FR") }
            if has(K.dstTouchdowns) { parts.append("\(n(K.dstTouchdowns)) TD") }
            if has(K.dstSafeties) { parts.append("\(n(K.dstSafeties)) SF") }
            return parts.joined(separator: ", ")
        }
        var groups: [String] = []
        if has(K.passingAttempts) {
            var parts = ["\(n(K.completions))/\(n(K.passingAttempts))", "\(n(K.passingYards)) YD"]
            if has(K.passingTouchdowns) { parts.append("\(n(K.passingTouchdowns)) TD") }
            if has(K.interceptionsThrown) { parts.append("\(n(K.interceptionsThrown)) INT") }
            groups.append(parts.joined(separator: ", "))
        }
        if has(K.rushingAttempts) {
            var parts = ["\(n(K.rushingAttempts)) CAR", "\(n(K.rushingYards)) YD"]
            if has(K.rushingTouchdowns) { parts.append("\(n(K.rushingTouchdowns)) TD") }
            groups.append(parts.joined(separator: ", "))
        }
        if has(K.receptions) || has(K.targets) {
            var parts = ["\(n(K.receptions))/\(n(K.targets)) REC", "\(n(K.receivingYards)) YD"]
            if has(K.receivingTouchdowns) { parts.append("\(n(K.receivingTouchdowns)) TD") }
            groups.append(parts.joined(separator: ", "))
        }
        if has(K.fieldGoalAttempts) || has(K.extraPointAttempts) {
            groups.append("\(n(K.fieldGoalsMade))/\(n(K.fieldGoalAttempts)) FG, \(n(K.extraPointsMade))/\(n(K.extraPointAttempts)) XP")
        }
        if has(K.fumblesLost) { groups.append("\(n(K.fumblesLost)) FUM") }
        return groups.joined(separator: " · ")
    }
}

extension FantasySlate {
    enum CodingKeys: String, CodingKey { case sport, season, week, label, generatedAt, players, games, availableWeeks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sport = try FantasySportCoding.decode(c, forKey: .sport)
        season = try c.decode(Int.self, forKey: .season)
        week = try c.decodeIfPresent(Int.self, forKey: .week)
        label = try c.decode(String.self, forKey: .label)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        players = try c.decode([FantasyPlayerLine].self, forKey: .players)
        games = try? c.decodeIfPresent([Game].self, forKey: .games)
        availableWeeks = try? c.decodeIfPresent([Int].self, forKey: .availableWeeks)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sport.rawValue, forKey: .sport)
        try c.encode(season, forKey: .season)
        try c.encodeIfPresent(week, forKey: .week)
        try c.encode(label, forKey: .label)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encode(players, forKey: .players)
        try c.encodeIfPresent(games, forKey: .games)
        try c.encodeIfPresent(availableWeeks, forKey: .availableWeeks)
    }
}
