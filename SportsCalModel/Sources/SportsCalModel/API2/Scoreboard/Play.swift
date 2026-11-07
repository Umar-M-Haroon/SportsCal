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
    /// Baseball: ESPN's row kind — "I" inning start, "A" at-bat start, "P" pitch,
    /// "N" result, "S" scoring result, "C" pitching change; nil for end-of markers and
    /// mid-at-bat events (steals, wild pitches). See ``isBaseballResult``.
    public let summaryType: String?
    /// Baseball: the plate appearance this row belongs to, shared by its pitches.
    public let atBatId: String?

    public struct PlayClock: Codable, Equatable, Hashable {
        public let displayValue: String?
        public init(displayValue: String?) { self.displayValue = displayValue }
    }

    public struct PlayPeriod: Codable, Equatable, Hashable {
        public let number: Int?
        /// Baseball: "Top", "Bottom", "Mid" or "End". Football sends "quarter".
        public let type: String?
        public init(number: Int?, type: String? = nil) {
            self.number = number
            self.type = type
        }
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
        type: PlayType? = nil,
        summaryType: String? = nil,
        atBatId: String? = nil
    ) {
        self.id = id
        self.text = text
        self.scoringPlay = scoringPlay
        self.awayScore = awayScore
        self.homeScore = homeScore
        self.clock = clock
        self.period = period
        self.type = type
        self.summaryType = summaryType
        self.atBatId = atBatId
    }
}

public struct ESPNSummaryResponse: Codable {
    public let plays: [Play]?
    /// Home win probability after each play. Basketball, football and baseball only.
    public let winprobability: [ESPNWinProbabilityEntry]?
    public let boxscore: ESPNSummaryBoxscore?
    /// Football groups its plays by drive and sends no top-level `plays`.
    public let drives: Drives?
    /// Head-to-head series between the two teams (baseball's current series, …).
    public let seasonseries: [ESPNSeasonSeries]?
    /// Just the event ID, to place this game within its series.
    public let header: ESPNSummaryHeader?

    public struct Drives: Codable {
        public var previous: [Drive]?
        public var current: Drive?

        public struct Drive: Codable {
            public struct DriveTeam: Codable {
                public var id: String?
                public var abbreviation: String?

                public init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
                    abbreviation = (try? c.decodeIfPresent(String.self, forKey: .abbreviation)) ?? nil
                }
            }

            public var id: String?
            /// "13 plays, 60 yards, 6:55"
            public var description: String?
            /// "Touchdown", "Punt", "Field Goal"
            public var displayResult: String?
            public var isScore: Bool?
            public var team: DriveTeam?
            public var plays: [Play]?

            public init(plays: [Play]?) {
                self.plays = plays
            }

            enum CodingKeys: String, CodingKey { case id, description, displayResult, isScore, team, plays }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                plays = try c.decodeIfPresent([Play].self, forKey: .plays)
                // The drive header is extra: an odd value there must not cost the plays.
                id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
                description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? nil
                displayResult = (try? c.decodeIfPresent(String.self, forKey: .displayResult)) ?? nil
                isScore = (try? c.decodeIfPresent(Bool.self, forKey: .isScore)) ?? nil
                team = (try? c.decodeIfPresent(DriveTeam.self, forKey: .team)) ?? nil
            }
        }

        /// Every play across the drives, oldest first.
        public var allPlays: [Play] {
            (previous ?? []).flatMap { $0.plays ?? [] } + (current?.plays ?? [])
        }

        /// One header per drive that has plays, oldest first. The drive in progress has
        /// no result yet.
        public var summaries: [DriveSummary] {
            var all = (previous ?? []).map { ($0, false) }
            if let current { all.append((current, true)) }
            return all.compactMap { drive, isCurrent in
                guard let first = drive.plays?.first else { return nil }
                return DriveSummary(
                    firstPlayID: first.id,
                    team: drive.team?.abbreviation,
                    summary: drive.description,
                    result: isCurrent ? nil : drive.displayResult,
                    isScore: drive.isScore == true ? true : nil
                )
            }
        }
    }

    public init(plays: [Play]?, winprobability: [ESPNWinProbabilityEntry]? = nil, boxscore: ESPNSummaryBoxscore? = nil, drives: Drives? = nil,
                seasonseries: [ESPNSeasonSeries]? = nil, header: ESPNSummaryHeader? = nil) {
        self.plays = plays
        self.winprobability = winprobability
        self.boxscore = boxscore
        self.drives = drives
        self.seasonseries = seasonseries
        self.header = header
    }

    /// The game's plays, oldest first, wherever ESPN put them: the top-level list for
    /// most sports, the drives for football (whose top-level list is absent).
    public var allPlays: [Play] {
        if let plays, !plays.isEmpty { return plays }
        return drives?.allPlays ?? []
    }

    /// Whether `allPlays` came from the drives.
    public var playsFromDrives: Bool {
        (plays?.isEmpty ?? true) && !(drives?.allPlays.isEmpty ?? true)
    }

    enum CodingKeys: String, CodingKey { case plays, winprobability, boxscore, drives, seasonseries, header }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plays = try c.decodeIfPresent([Play].self, forKey: .plays)
        // The additions are best-effort: they must never cost us the play-by-play.
        winprobability = try? c.decodeIfPresent([ESPNWinProbabilityEntry].self, forKey: .winprobability)
        boxscore = try? c.decodeIfPresent(ESPNSummaryBoxscore.self, forKey: .boxscore)
        drives = try? c.decodeIfPresent(Drives.self, forKey: .drives)
        seasonseries = try? c.decodeIfPresent([ESPNSeasonSeries].self, forKey: .seasonseries)
        header = try? c.decodeIfPresent(ESPNSummaryHeader.self, forKey: .header)
    }

    /// Where this game sits in the teams' current series ("Game 2 of 3 · PHI leads
    /// series 1-0"). Baseball's regular season only: ESPN's "current" series is the
    /// three- or four-game set, and the postseason has its own playoff context.
    public var currentSeries: SeriesContext? {
        guard let current = seasonseries?.first(where: { $0.type == "current" }),
              let summary = current.summary, !summary.isEmpty else { return nil }
        let index = header?.id.flatMap { id in current.events?.firstIndex { $0.id == id } }
        return SeriesContext(
            gameNumber: index.map { $0 + 1 },
            totalGames: current.totalCompetitions,
            summary: summary
        )
    }
}

/// One `seasonseries` entry of an ESPN summary.
public struct ESPNSeasonSeries: Codable {
    public struct SeriesEvent: Codable {
        public var id: String?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
        }
    }

    /// "current", "season", "preseason", …
    public var type: String?
    /// "PHI leads series 2-1"
    public var summary: String?
    public var totalCompetitions: Int?
    public var events: [SeriesEvent]?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? nil
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? nil
        totalCompetitions = (try? c.decodeIfPresent(Int.self, forKey: .totalCompetitions)) ?? nil
        events = (try? c.decodeIfPresent([SeriesEvent].self, forKey: .events)) ?? nil
    }
}

/// The summary's `header`, for its event ID.
public struct ESPNSummaryHeader: Codable {
    public var id: String?

    public init(id: String? = nil) { self.id = id }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
    }
}

/// A football drive's header, keyed to its first play so the client can split the
/// flat play list back into drives.
public struct DriveSummary: Codable, Equatable, Hashable, Sendable {
    public var firstPlayID: String
    /// The offense, e.g. "KC".
    public var team: String?
    /// "13 plays, 60 yards, 6:55"
    public var summary: String?
    /// "Touchdown", "Punt"; nil while the drive is in progress.
    public var result: String?
    public var isScore: Bool?

    public init(firstPlayID: String, team: String? = nil, summary: String? = nil, result: String? = nil, isScore: Bool? = nil) {
        self.firstPlayID = firstPlayID
        self.team = team
        self.summary = summary
        self.result = result
        self.isScore = isScore
    }
}

/// A regular-season series between two teams, from the game's point of view.
public struct SeriesContext: Codable, Equatable, Hashable, Sendable {
    /// This game's place in the series, 1-based.
    public var gameNumber: Int?
    public var totalGames: Int?
    /// ESPN's summary, "PHI leads series 2-1".
    public var summary: String

    public init(gameNumber: Int? = nil, totalGames: Int? = nil, summary: String) {
        self.gameNumber = gameNumber
        self.totalGames = totalGames
        self.summary = summary
    }

    /// "Game 2 of 3 · PHI leads series 1-0"
    public var displayText: String {
        guard let gameNumber, let totalGames, gameNumber <= totalGames else { return summary }
        return "Game \(gameNumber) of \(totalGames) · \(summary)"
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
    /// Football: one header per drive, oldest first.
    public var drives: [DriveSummary]?
    /// Baseball: the regular-season series this game belongs to.
    public var series: SeriesContext?

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
        var extras = CachedPlaysExtras(winProbability: winProbability, teamStats: teamStats, excitement: excitement)
        extras.drives = drives
        extras.series = series
        return extras
    }

    /// Sets the drive headers and series from archived or freshly derived extras.
    public mutating func apply(_ extras: CachedPlaysExtras) {
        drives = extras.drives
        series = extras.series
    }
}

/// Everything in `CachedPlays` beyond the plays themselves, stored as one JSON blob.
public struct CachedPlaysExtras: Codable, Equatable {
    public var winProbability: WinProbabilitySeries?
    public var teamStats: TeamStatComparison?
    public var excitement: Int?
    public var drives: [DriveSummary]?
    public var series: SeriesContext?

    public init(winProbability: WinProbabilitySeries? = nil, teamStats: TeamStatComparison? = nil, excitement: Int? = nil) {
        self.winProbability = winProbability
        self.teamStats = teamStats
        self.excitement = excitement
    }

    public var isEmpty: Bool {
        winProbability == nil && teamStats == nil && excitement == nil && drives == nil && series == nil
    }
}

public extension ESPNSummaryResponse {
    /// Derives the cache extras from this summary. `league` picks the box-score layout
    /// and the excitement calibration; excitement is only scored once the game is final.
    func extras(league: Leagues?, isFinal: Bool) -> CachedPlaysExtras {
        // Period boundaries come from joining play IDs.
        let series = winprobability.flatMap { WinProbabilitySeries(entries: $0, plays: allPlays) }
        let sport = league.map(SportType.init(league:))
        let teamStats = sport.flatMap { TeamStatComparison(boxscore: boxscore, sport: $0) }
        var excitement: Int?
        if isFinal, let series, let league {
            excitement = ExcitementIndex.score(series: series.home, league: league)
        }
        var extras = CachedPlaysExtras(winProbability: series, teamStats: teamStats, excitement: excitement)
        let drives = self.drives?.summaries ?? []
        extras.drives = drives.isEmpty ? nil : drives
        if league == .mlb {
            extras.series = currentSeries
        }
        return extras
    }
}
