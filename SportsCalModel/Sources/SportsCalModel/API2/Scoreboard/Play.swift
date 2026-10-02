//
//  Play.swift
//  SportsCalModel
//
//  Decodes the `plays[]` array from ESPN's
//  `/apis/site/v2/sports/{sport}/{league}/summary?event={id}` endpoint.
//  Used for NBA/NFL/NHL/MLB play-by-play.
//

import Foundation

public struct Play: Codable, Equatable, Identifiable, Hashable {
    public let id: String
    public let text: String?
    public let scoringPlay: Bool?
    public let awayScore: Int?
    public let homeScore: Int?
    public let clock: PlayClock?
    public let period: PlayPeriod?
    public let type: PlayType?

    public struct PlayClock: Codable, Equatable, Hashable {
        public let displayValue: String?
        public init(displayValue: String?) { self.displayValue = displayValue }
    }

    public struct PlayPeriod: Codable, Equatable, Hashable {
        public let number: Int?
        public init(number: Int?) { self.number = number }
    }

    public struct PlayType: Codable, Equatable, Hashable {
        public let id: String?
        public let text: String?
        public init(id: String?, text: String?) {
            self.id = id
            self.text = text
        }
    }

    public init(
        id: String,
        text: String? = nil,
        scoringPlay: Bool? = nil,
        awayScore: Int? = nil,
        homeScore: Int? = nil,
        clock: PlayClock? = nil,
        period: PlayPeriod? = nil,
        type: PlayType? = nil
    ) {
        self.id = id
        self.text = text
        self.scoringPlay = scoringPlay
        self.awayScore = awayScore
        self.homeScore = homeScore
        self.clock = clock
        self.period = period
        self.type = type
    }
}

public struct ESPNSummaryResponse: Codable {
    public let plays: [Play]?
    /// Home win probability after each play. Basketball, football and baseball only.
    public let winprobability: [ESPNWinProbabilityEntry]?
    public let boxscore: ESPNSummaryBoxscore?
    /// Football groups its plays by drive and sends no top-level `plays`.
    public let drives: Drives?

    public struct Drives: Codable {
        public var previous: [Drive]?
        public var current: Drive?

        public struct Drive: Codable {
            public var plays: [Play]?
        }

        /// Every play across the drives, oldest first.
        public var allPlays: [Play] {
            (previous ?? []).flatMap { $0.plays ?? [] } + (current?.plays ?? [])
        }
    }

    public init(plays: [Play]?, winprobability: [ESPNWinProbabilityEntry]? = nil, boxscore: ESPNSummaryBoxscore? = nil, drives: Drives? = nil) {
        self.plays = plays
        self.winprobability = winprobability
        self.boxscore = boxscore
        self.drives = drives
    }

    enum CodingKeys: String, CodingKey { case plays, winprobability, boxscore, drives }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plays = try c.decodeIfPresent([Play].self, forKey: .plays)
        // The additions are best-effort: they must never cost us the play-by-play.
        winprobability = try? c.decodeIfPresent([ESPNWinProbabilityEntry].self, forKey: .winprobability)
        boxscore = try? c.decodeIfPresent(ESPNSummaryBoxscore.self, forKey: .boxscore)
        drives = try? c.decodeIfPresent(Drives.self, forKey: .drives)
    }
}

/// Persistent lookup record from TheSportsDB event ID → ESPN event ID + sport/league slugs.
/// Populated during play-by-play enrichment so the `/plays/:eventID` on-demand path can
/// resolve a client-supplied TSDB ID back to ESPN for a just-in-time fetch.
public struct ESPNEventMapping: Codable, Equatable {
    public let espnEventID: String
    public let sport: String   // "basketball" | "baseball" | "football" | "hockey"
    public let league: String  // "nba" | "mlb" | "nfl" | "nhl"

    public init(espnEventID: String, sport: String, league: String) {
        self.espnEventID = espnEventID
        self.sport = sport
        self.league = league
    }
}

/// Payload cached per-event in Redis and returned by `GET /plays/:eventID`.
public struct CachedPlays: Codable, Equatable {
    public let eventID: String
    public let lastPlayId: String
    public let plays: [Play]
    public let isFinal: Bool
    public let fetchedAt: Date
    /// The game's win-probability history, where ESPN publishes one.
    public var winProbability: WinProbabilitySeries?
    /// Side-by-side team stats from the box score.
    public var teamStats: TeamStatComparison?
    /// "Worth watching" score, 0...100, once the game is final. See `ExcitementIndex`.
    public var excitement: Int?

    public init(
        eventID: String, lastPlayId: String, plays: [Play], isFinal: Bool, fetchedAt: Date,
        winProbability: WinProbabilitySeries? = nil, teamStats: TeamStatComparison? = nil, excitement: Int? = nil
    ) {
        self.eventID = eventID
        self.lastPlayId = lastPlayId
        self.plays = plays
        self.isFinal = isFinal
        self.fetchedAt = fetchedAt
        self.winProbability = winProbability
        self.teamStats = teamStats
        self.excitement = excitement
    }

    /// The parts of a payload stored beside the plays in the server's archive.
    public var extras: CachedPlaysExtras {
        CachedPlaysExtras(winProbability: winProbability, teamStats: teamStats, excitement: excitement)
    }
}

/// Everything in `CachedPlays` beyond the plays themselves, stored as one JSON blob.
public struct CachedPlaysExtras: Codable, Equatable {
    public var winProbability: WinProbabilitySeries?
    public var teamStats: TeamStatComparison?
    public var excitement: Int?

    public init(winProbability: WinProbabilitySeries? = nil, teamStats: TeamStatComparison? = nil, excitement: Int? = nil) {
        self.winProbability = winProbability
        self.teamStats = teamStats
        self.excitement = excitement
    }

    public var isEmpty: Bool { winProbability == nil && teamStats == nil && excitement == nil }
}

public extension ESPNSummaryResponse {
    /// Derives the cache extras from this summary. `league` picks the box-score layout
    /// and the excitement calibration; excitement is only scored once the game is final.
    func extras(league: Leagues?, isFinal: Bool) -> CachedPlaysExtras {
        // Period boundaries come from joining play IDs; football's plays live under drives.
        let periodSource = (plays?.isEmpty == false ? plays : nil) ?? drives?.allPlays ?? []
        let series = winprobability.flatMap { WinProbabilitySeries(entries: $0, plays: periodSource) }
        let sport = league.map(SportType.init(league:))
        let teamStats = sport.flatMap { TeamStatComparison(boxscore: boxscore, sport: $0) }
        var excitement: Int?
        if isFinal, let series, let league {
            excitement = ExcitementIndex.score(series: series.home, league: league)
        }
        return CachedPlaysExtras(winProbability: series, teamStats: teamStats, excitement: excitement)
    }
}
