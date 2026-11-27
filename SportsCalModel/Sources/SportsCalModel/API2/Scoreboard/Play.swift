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
    /// Who was involved, from ESPN's `participants[]`, in ESPN's order. Hockey and
    /// baseball send a `role` for each, so match on that. Basketball sends none: the
    /// first is the player who made the play (shooter, rebounder, fouler), the next
    /// the assister, blocker or player fouled. Football's drive plays carry none.
    ///
    /// Server-side only: it adds 20–50% to a game's plays, so `CachedPlays` (what
    /// `/plays` serves and the archive stores) drops it. Optional, so payloads without
    /// it decode, and clients that predate it ignore it.
    public let participants: [PlayParticipant]?

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
        atBatId: String? = nil,
        participants: [PlayParticipant]? = nil
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
        self.participants = participants
    }

    enum CodingKeys: String, CodingKey {
        case id, text, scoringPlay, awayScore, homeScore, clock, period, type, summaryType, atBatId, participants
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The fields that predate `participants` decode exactly as the synthesized
        // decoder did, so nothing that decoded before fails now.
        id = try c.decode(String.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        scoringPlay = try c.decodeIfPresent(Bool.self, forKey: .scoringPlay)
        awayScore = try c.decodeIfPresent(Int.self, forKey: .awayScore)
        homeScore = try c.decodeIfPresent(Int.self, forKey: .homeScore)
        clock = try c.decodeIfPresent(PlayClock.self, forKey: .clock)
        period = try c.decodeIfPresent(PlayPeriod.self, forKey: .period)
        type = try c.decodeIfPresent(PlayType.self, forKey: .type)
        summaryType = try c.decodeIfPresent(String.self, forKey: .summaryType)
        atBatId = try c.decodeIfPresent(String.self, forKey: .atBatId)
        // Best-effort and per participant: an odd entry must never cost the play.
        let decoded = (try? c.decodeIfPresent([LossyParticipant].self, forKey: .participants))?
            .compactMap(\.value)
        participants = (decoded?.isEmpty ?? true) ? nil : decoded
    }

    private struct LossyParticipant: Decodable {
        let value: PlayParticipant?
        init(from decoder: Decoder) throws { value = try? PlayParticipant(from: decoder) }
    }

    /// This play without its participants, for payloads that leave the server.
    public var withoutParticipants: Play {
        guard participants != nil else { return self }
        return Play(
            id: id, text: text, scoringPlay: scoringPlay, awayScore: awayScore, homeScore: homeScore,
            clock: clock, period: period, type: type, summaryType: summaryType, atBatId: atBatId
        )
    }

    /// This play with each participant's missing name filled from `names` (athlete
    /// ID → name). ESPN names hockey participants but not basketball or baseball
    /// ones; the box score in the same summary knows them.
    public func namingParticipants(_ names: [String: String]) -> Play {
        guard let participants, participants.contains(where: { $0.name == nil }) else { return self }
        let named = participants.map { participant -> PlayParticipant in
            guard participant.name == nil, let name = names[participant.athleteID] else { return participant }
            return PlayParticipant(athleteID: participant.athleteID, name: name, role: participant.role)
        }
        return Play(
            id: id, text: text, scoringPlay: scoringPlay, awayScore: awayScore, homeScore: homeScore,
            clock: clock, period: period, type: type, summaryType: summaryType, atBatId: atBatId,
            participants: named
        )
    }
}

/// One athlete involved in a play.
///
/// Decodes both ESPN's shape (`{"athlete": {"id", "shortName"}, "type"}`) and its own
/// (`{"athleteID", "name", "role"}`), and encodes its own.
public struct PlayParticipant: Codable, Equatable, Hashable, Sendable {
    /// ESPN athlete ID, the same ID as `PlayerBoxScore.Row.id`.
    public var athleteID: String
    /// "N. Jokic". ESPN names only some sports' participants; see `Play.namingParticipants`.
    public var name: String?
    /// ESPN's participant type: hockey "scorer", "assister", "shooter", "saver",
    /// "face-off-winner", "hit-credited"…; baseball "batter", "pitcher", "onFirst"…
    /// Nil where ESPN sends none (basketball).
    public var role: String?

    public init(athleteID: String, name: String? = nil, role: String? = nil) {
        self.athleteID = athleteID
        self.name = name
        self.role = role
    }

    enum CodingKeys: String, CodingKey { case athleteID, name, role }
    private enum ESPNKeys: String, CodingKey { case athlete, type }
    private struct ESPNAthlete: Decodable {
        let id: String?
        let shortName: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey { case id, shortName, displayName }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // ESPN IDs are strings, but don't lose a participant over a numeric one.
            if let string = try? c.decodeIfPresent(String.self, forKey: .id) {
                id = string
            } else if let number = try? c.decodeIfPresent(Int.self, forKey: .id) {
                id = String(number)
            } else {
                id = nil
            }
            shortName = try? c.decodeIfPresent(String.self, forKey: .shortName)
            displayName = try? c.decodeIfPresent(String.self, forKey: .displayName)
        }
    }

    public init(from decoder: Decoder) throws {
        let own = try decoder.container(keyedBy: CodingKeys.self)
        if let athleteID = try? own.decodeIfPresent(String.self, forKey: .athleteID), !athleteID.isEmpty {
            self.athleteID = athleteID
            name = try? own.decodeIfPresent(String.self, forKey: .name)
            role = try? own.decodeIfPresent(String.self, forKey: .role)
            return
        }
        let espn = try decoder.container(keyedBy: ESPNKeys.self)
        let athlete = try espn.decode(ESPNAthlete.self, forKey: .athlete)
        guard let id = athlete.id, !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .athlete, in: espn, debugDescription: "Participant without an athlete ID")
        }
        athleteID = id
        name = athlete.shortName ?? athlete.displayName
        role = try? espn.decodeIfPresent(String.self, forKey: .type)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(athleteID, forKey: .athleteID)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(role, forKey: .role)
    }
}

public struct ESPNSummaryResponse: Codable {
    public let plays: [Play]?
    /// Home win probability after each play. Basketball, football and baseball only.
    public let winprobability: [ESPNWinProbabilityEntry]?
    public let boxscore: ESPNSummaryBoxscore?
    /// Football groups its plays by drive and sends no top-level `plays`.
    public let drives: Drives?
    /// Football's scoring plays, with tidier text than the drive plays.
    public let scoringPlays: [ScoringPlay]?
    /// `plays[]` again, read for the fields `Play` leaves out (participants, strength,
    /// team). Feeds `ScoringSummary`; never encoded.
    public let detailPlays: [DetailPlay]?
    /// Head-to-head series between the two teams (baseball's current series, …).
    public let seasonseries: [ESPNSeasonSeries]?
    /// Just the event ID, to place this game within its series.
    public let header: ESPNSummaryHeader?
    /// The ESPN team ID of each top-level play, index for index. Read only to count team
    /// fouls and timeouts (`BasketballPlayTally`); kept off `Play` so the cached and
    /// served play-by-play doesn't grow by a team per play.
    public var playTeamIDs: [String?]? = nil

    private struct PlayTeamRef: Decodable {
        let teamID: String?

        enum CodingKeys: String, CodingKey { case team }
        struct TeamID: Decodable { let id: String? }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            teamID = (try? c.decodeIfPresent(TeamID.self, forKey: .team))?.id
        }
    }

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

    public init(
        plays: [Play]?, winprobability: [ESPNWinProbabilityEntry]? = nil, boxscore: ESPNSummaryBoxscore? = nil,
        drives: Drives? = nil, scoringPlays: [ScoringPlay]? = nil, detailPlays: [DetailPlay]? = nil,
        seasonseries: [ESPNSeasonSeries]? = nil, header: ESPNSummaryHeader? = nil
    ) {
        self.plays = plays
        self.winprobability = winprobability
        self.boxscore = boxscore
        self.drives = drives
        self.scoringPlays = scoringPlays
        self.detailPlays = detailPlays
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

    enum CodingKeys: String, CodingKey { case plays, winprobability, boxscore, drives, scoringPlays, seasonseries, header }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plays = try c.decodeIfPresent([Play].self, forKey: .plays)
        // The additions are best-effort: they must never cost us the play-by-play.
        winprobability = try? c.decodeIfPresent([ESPNWinProbabilityEntry].self, forKey: .winprobability)
        boxscore = try? c.decodeIfPresent(ESPNSummaryBoxscore.self, forKey: .boxscore)
        drives = try? c.decodeIfPresent(Drives.self, forKey: .drives)
        scoringPlays = (try? c.decodeIfPresent([Lossy<ScoringPlay>].self, forKey: .scoringPlays))?.compactMap(\.value)
        detailPlays = (try? c.decodeIfPresent([Lossy<DetailPlay>].self, forKey: .plays))?.compactMap(\.value)
        seasonseries = try? c.decodeIfPresent([ESPNSeasonSeries].self, forKey: .seasonseries)
        header = try? c.decodeIfPresent(ESPNSummaryHeader.self, forKey: .header)
        playTeamIDs = (try? c.decodeIfPresent([PlayTeamRef].self, forKey: .plays))?.map(\.teamID)
    }

    /// One element of a list that may fail on its own without failing the list.
    struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
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
    /// Football's week number (`header.week`).
    public var week: Int?
    public var season: Season?
    /// `header.competitions[0]`: date, status and the two teams' scores.
    public var competition: Competition?

    public struct Season: Codable {
        public var year: Int?
        /// 1 pre, 2 regular, 3 post.
        public var type: Int?
    }

    public struct Competition: Codable {
        public var date: String?
        public var status: Status?
        public var competitors: [Competitor]?

        public struct Status: Codable {
            /// Seconds left in the period.
            public var clock: Double?
            public var period: Int?
            public var type: StatusType?
        }
        public struct StatusType: Codable {
            public var state: String?
            public var completed: Bool?
            public var shortDetail: String?
        }
        public struct Competitor: Codable {
            public var id: String?
            public var homeAway: String?
            public var score: String?
        }
    }

    public init(id: String? = nil, week: Int? = nil, season: Season? = nil, competition: Competition? = nil) {
        self.id = id
        self.week = week
        self.season = season
        self.competition = competition
    }

    enum CodingKeys: String, CodingKey { case id, week, season, competitions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
        week = (try? c.decodeIfPresent(Int.self, forKey: .week)) ?? nil
        season = (try? c.decodeIfPresent(Season.self, forKey: .season)) ?? nil
        competition = ((try? c.decodeIfPresent([Competition].self, forKey: .competitions)) ?? nil)?.first
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(week, forKey: .week)
        try c.encodeIfPresent(season, forKey: .season)
        try c.encodeIfPresent(competition.map { [$0] }, forKey: .competitions)
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
    /// Per-player stat lines. Only sent when the request asks (`players=1`).
    public var players: PlayerBoxScore?
    /// Scoring plays (football, hockey, baseball). Sent with `players`.
    public var scoringSummary: ScoringSummary?
    /// Football: one header per drive, oldest first.
    public var drives: [DriveSummary]?
    /// Baseball: the regular-season series this game belongs to.
    public var series: SeriesContext?
    /// Basketball, while live: team fouls, timeouts and the current run, counted from
    /// the plays when they were fetched. The live job stamps it onto the game's situation.
    public var basketballTally: BasketballPlayTally?

    public init(
        eventID: String, lastPlayId: String, plays: [Play], isFinal: Bool, fetchedAt: Date,
        winProbability: WinProbabilitySeries? = nil, teamStats: TeamStatComparison? = nil, excitement: Int? = nil,
        players: PlayerBoxScore? = nil, scoringSummary: ScoringSummary? = nil,
        drives: [DriveSummary]? = nil, series: SeriesContext? = nil, basketballTally: BasketballPlayTally? = nil
    ) {
        self.eventID = eventID
        self.lastPlayId = lastPlayId
        // What `/plays` serves and the archive stores: participants stay on the
        // server (they'd grow every game's plays by 20–50%).
        self.plays = plays.map(\.withoutParticipants)
        self.isFinal = isFinal
        self.fetchedAt = fetchedAt
        self.winProbability = winProbability
        self.teamStats = teamStats
        self.excitement = excitement
        self.players = players
        self.scoringSummary = scoringSummary
        self.drives = drives
        self.series = series
        self.basketballTally = basketballTally
    }

    public init(eventID: String, lastPlayId: String, plays: [Play], isFinal: Bool, fetchedAt: Date, extras: CachedPlaysExtras?) {
        self.init(
            eventID: eventID, lastPlayId: lastPlayId, plays: plays, isFinal: isFinal, fetchedAt: fetchedAt,
            winProbability: extras?.winProbability, teamStats: extras?.teamStats, excitement: extras?.excitement,
            players: extras?.players, scoringSummary: extras?.scoringSummary,
            drives: extras?.drives, series: extras?.series, basketballTally: extras?.basketballTally
        )
    }

    /// The parts of a payload stored beside the plays in the server's archive.
    public var extras: CachedPlaysExtras {
        CachedPlaysExtras(
            winProbability: winProbability, teamStats: teamStats, excitement: excitement,
            players: players, scoringSummary: scoringSummary,
            drives: drives, series: series, basketballTally: basketballTally
        )
    }

    /// This payload without the opt-in player detail, for callers that didn't ask.
    /// Drives, series and the basketball tally stay: they're part of the default payload.
    public var withoutPlayerDetail: CachedPlays {
        var copy = self
        copy.players = nil
        copy.scoringSummary = nil
        return copy
    }

    /// Sets the derived detail (player box score, scoring summary, drive headers,
    /// series, basketball tally) from archived or freshly derived extras.
    public mutating func apply(_ extras: CachedPlaysExtras) {
        players = extras.players
        scoringSummary = extras.scoringSummary
        drives = extras.drives
        series = extras.series
        basketballTally = extras.basketballTally
    }
}

/// Everything in `CachedPlays` beyond the plays themselves, stored as one JSON blob.
public struct CachedPlaysExtras: Codable, Equatable {
    public var winProbability: WinProbabilitySeries?
    public var teamStats: TeamStatComparison?
    public var excitement: Int?
    public var players: PlayerBoxScore?
    public var scoringSummary: ScoringSummary?
    public var drives: [DriveSummary]?
    public var series: SeriesContext?
    public var basketballTally: BasketballPlayTally?

    public init(
        winProbability: WinProbabilitySeries? = nil, teamStats: TeamStatComparison? = nil, excitement: Int? = nil,
        players: PlayerBoxScore? = nil, scoringSummary: ScoringSummary? = nil,
        drives: [DriveSummary]? = nil, series: SeriesContext? = nil, basketballTally: BasketballPlayTally? = nil
    ) {
        self.winProbability = winProbability
        self.teamStats = teamStats
        self.excitement = excitement
        self.players = players
        self.scoringSummary = scoringSummary
        self.drives = drives
        self.series = series
        self.basketballTally = basketballTally
    }

    public var isEmpty: Bool {
        // Split up: one long `&&` chain of optional comparisons is slow to type-check.
        let base = winProbability == nil && teamStats == nil && excitement == nil
        let detail = players == nil && scoringSummary == nil
        let context = drives == nil && series == nil && basketballTally == nil
        return base && detail && context
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
        let players = sport.flatMap { PlayerBoxScore(boxscore: boxscore, sport: $0) }
        let scoring = sport.flatMap { ScoringSummary(summary: self, sport: $0) }
        var excitement: Int?
        if isFinal, let series, let league {
            excitement = ExcitementIndex.score(series: series.home, league: league)
        }
        let drives = self.drives?.summaries ?? []
        return CachedPlaysExtras(
            winProbability: series, teamStats: teamStats, excitement: excitement,
            players: players, scoringSummary: scoring,
            drives: drives.isEmpty ? nil : drives,
            series: league == .mlb ? currentSeries : nil
        )
    }
}
