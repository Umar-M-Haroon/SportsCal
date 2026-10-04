//
//  SoccerMatchDetail.swift
//  SportsCalModel
//
//  Per-match detail for any soccer fixture: the team stat comparison, the
//  goal/card/sub timeline, both lineups (with formation slots for a pitch view),
//  every shot with an estimated xG, a momentum series, live commentary, and each
//  side's recent form plus the head-to-head record.
//
//  Built server-side from ESPN's per-event `summary` endpoint and fetched lazily
//  per game via `/soccer/match/:eventID`. It is intentionally NOT part of the
//  ridealong `LiveScore` payload (one match is large and only needed when a
//  detail view opens).
//
//  This began life as the World Cup box score; the JSON keys of the original
//  fields are unchanged, so app versions still calling `/worldcup/boxscore`
//  decode it as before. Fields added since decode as empty when absent.
//
//  `BracketSide` (home/away) is reused from WorldCupEnrichment.
//

import Foundation

// MARK: - Match detail

public struct SoccerMatchDetail: Codable, Equatable, Hashable {
    public var eventID: String
    public var home: SoccerLineup
    public var away: SoccerLineup
    /// Head-to-head team stats (possession, shots, fouls…), in display order.
    public var teamStats: [SoccerTeamStat]
    /// Goal / card / substitution timeline, ordered earliest → latest.
    public var events: [SoccerMatchEvent]
    /// Every shot with pitch coordinates, earliest → latest. Own goals are excluded:
    /// they aren't a shot by the team they count for.
    public var shots: [SoccerShot]
    /// One point per match minute; positive means the home side is on top.
    public var momentum: [SoccerMomentumPoint]
    /// ESPN's running commentary, earliest → latest.
    public var commentary: [SoccerCommentaryEntry]
    public var headToHead: SoccerHeadToHead?

    public init(
        eventID: String,
        home: SoccerLineup,
        away: SoccerLineup,
        teamStats: [SoccerTeamStat] = [],
        events: [SoccerMatchEvent] = [],
        shots: [SoccerShot] = [],
        momentum: [SoccerMomentumPoint] = [],
        commentary: [SoccerCommentaryEntry] = [],
        headToHead: SoccerHeadToHead? = nil
    ) {
        self.eventID = eventID
        self.home = home
        self.away = away
        self.teamStats = teamStats
        self.events = events
        self.shots = shots
        self.momentum = momentum
        self.commentary = commentary
        self.headToHead = headToHead
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try c.decode(String.self, forKey: .eventID)
        home = try c.decode(SoccerLineup.self, forKey: .home)
        away = try c.decode(SoccerLineup.self, forKey: .away)
        teamStats = try c.decodeIfPresent([SoccerTeamStat].self, forKey: .teamStats) ?? []
        events = try c.decodeIfPresent([SoccerMatchEvent].self, forKey: .events) ?? []
        shots = try c.decodeIfPresent([SoccerShot].self, forKey: .shots) ?? []
        momentum = try c.decodeIfPresent([SoccerMomentumPoint].self, forKey: .momentum) ?? []
        commentary = try c.decodeIfPresent([SoccerCommentaryEntry].self, forKey: .commentary) ?? []
        headToHead = try c.decodeIfPresent(SoccerHeadToHead.self, forKey: .headToHead)
    }

    /// True when there is nothing worth shipping/displaying.
    public var isEmpty: Bool {
        teamStats.isEmpty && events.isEmpty && home.players.isEmpty && away.players.isEmpty
            && commentary.isEmpty && home.form.isEmpty && away.form.isEmpty && headToHead == nil
    }

    /// Summed estimated xG for one side.
    public func expectedGoals(_ side: BracketSide) -> Double {
        shots.filter { $0.side == side }.reduce(0) { $0 + $1.xG }
    }
}

// MARK: - Per-team lineup

public struct SoccerLineup: Codable, Equatable, Hashable {
    public var teamID: String?
    public var teamName: String
    public var teamBadge: String?
    /// Formation string from ESPN, e.g. "4-2-3-1". Nil if not provided.
    public var formation: String?
    /// Starters first (by formation place), then substitutes.
    public var players: [SoccerLineupPlayer]
    /// This side's last five results going into the match, oldest first — the order a
    /// form strip reads, with the latest result last.
    public var form: [SoccerFormMatch]

    public init(
        teamID: String? = nil,
        teamName: String,
        teamBadge: String? = nil,
        formation: String? = nil,
        players: [SoccerLineupPlayer] = [],
        form: [SoccerFormMatch] = []
    ) {
        self.teamID = teamID
        self.teamName = teamName
        self.teamBadge = teamBadge
        self.formation = formation
        self.players = players
        self.form = form
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teamID = try c.decodeIfPresent(String.self, forKey: .teamID)
        teamName = try c.decode(String.self, forKey: .teamName)
        teamBadge = try c.decodeIfPresent(String.self, forKey: .teamBadge)
        formation = try c.decodeIfPresent(String.self, forKey: .formation)
        players = try c.decodeIfPresent([SoccerLineupPlayer].self, forKey: .players) ?? []
        form = try c.decodeIfPresent([SoccerFormMatch].self, forKey: .form) ?? []
    }

    public var starters: [SoccerLineupPlayer] { players.filter(\.starter) }
    public var substitutes: [SoccerLineupPlayer] { players.filter { !$0.starter } }
}

public struct SoccerLineupPlayer: Codable, Equatable, Hashable, Identifiable {
    public var athleteID: String?
    public var name: String
    /// ESPN's short form, e.g. "V. van Dijk". Nil when ESPN omits it.
    public var shortName: String?
    public var jersey: String?
    /// Position abbreviation, e.g. "G", "CD-L", "AM", "F".
    public var position: String?
    public var positionName: String?
    public var starter: Bool
    public var subbedIn: Bool
    public var subbedOut: Bool
    /// The starter's slot in the formation: 1 is the goalkeeper, then ESPN numbers
    /// each line from the defence forward. Nil for substitutes.
    public var formationPlace: Int?
    /// Notable stat lines for this player (goals, shots, fouls…), already trimmed
    /// server-side to the meaningful ones.
    public var stats: [SoccerPlayerStat]

    public var id: String { athleteID ?? "\(name)-\(jersey ?? "")" }

    public init(
        athleteID: String? = nil,
        name: String,
        shortName: String? = nil,
        jersey: String? = nil,
        position: String? = nil,
        positionName: String? = nil,
        starter: Bool = false,
        subbedIn: Bool = false,
        subbedOut: Bool = false,
        formationPlace: Int? = nil,
        stats: [SoccerPlayerStat] = []
    ) {
        self.athleteID = athleteID
        self.name = name
        self.shortName = shortName
        self.jersey = jersey
        self.position = position
        self.positionName = positionName
        self.starter = starter
        self.subbedIn = subbedIn
        self.subbedOut = subbedOut
        self.formationPlace = formationPlace
        self.stats = stats
    }

    /// The numeric value of one of this player's stats, or 0.
    public func stat(_ name: String) -> Int {
        Int(stats.first { $0.name == name }?.value ?? 0)
    }
}

public struct SoccerPlayerStat: Codable, Equatable, Hashable {
    /// ESPN stat key, e.g. "totalGoals", "totalShots", "foulsCommitted".
    public var name: String
    /// Short label for compact display, e.g. "G", "SH", "FC".
    public var abbreviation: String?
    public var displayName: String?
    public var value: Double?
    public var displayValue: String

    public init(
        name: String,
        abbreviation: String? = nil,
        displayName: String? = nil,
        value: Double? = nil,
        displayValue: String
    ) {
        self.name = name
        self.abbreviation = abbreviation
        self.displayName = displayName
        self.value = value
        self.displayValue = displayValue
    }
}

// MARK: - Team stat comparison

public struct SoccerTeamStat: Codable, Equatable, Hashable, Identifiable {
    /// ESPN stat key, e.g. "possessionPct", "totalShots".
    public var name: String
    /// Display label, e.g. "Possession", "Shots".
    public var label: String
    public var homeDisplay: String
    public var awayDisplay: String
    /// Numeric values when parseable — used to size comparison bars.
    public var homeValue: Double?
    public var awayValue: Double?

    public var id: String { name }

    public init(
        name: String,
        label: String,
        homeDisplay: String,
        awayDisplay: String,
        homeValue: Double? = nil,
        awayValue: Double? = nil
    ) {
        self.name = name
        self.label = label
        self.homeDisplay = homeDisplay
        self.awayDisplay = awayDisplay
        self.homeValue = homeValue
        self.awayValue = awayValue
    }
}

// MARK: - Match event timeline

public enum SoccerMatchEventType: String, Codable, Equatable, Hashable {
    case goal
    case ownGoal
    case penaltyGoal
    case penaltyMissed
    case yellowCard
    case redCard
    case substitution
    case other
}

public struct SoccerMatchEvent: Codable, Equatable, Hashable, Identifiable {
    public var id: String
    public var type: SoccerMatchEventType
    /// Raw ESPN type text, e.g. "Goal", "Substitution" — fallback display label.
    public var typeText: String
    /// Clock display, e.g. "66'". Nil for non-timed events (kickoff/halftime).
    public var clock: String?
    public var period: Int?
    /// Which side the event belongs to, resolved server-side from the team id.
    public var side: BracketSide?
    public var scoringPlay: Bool
    /// Full ESPN narration, e.g. "Goal! France 1, Senegal 0. Kylian Mbappé…".
    public var text: String?
    public var shortText: String?
    /// Athletes involved — for a goal: [scorer, assister]; for a sub: [in, out].
    public var playerNames: [String]

    public init(
        id: String,
        type: SoccerMatchEventType,
        typeText: String,
        clock: String? = nil,
        period: Int? = nil,
        side: BracketSide? = nil,
        scoringPlay: Bool = false,
        text: String? = nil,
        shortText: String? = nil,
        playerNames: [String] = []
    ) {
        self.id = id
        self.type = type
        self.typeText = typeText
        self.clock = clock
        self.period = period
        self.side = side
        self.scoringPlay = scoringPlay
        self.text = text
        self.shortText = shortText
        self.playerNames = playerNames
    }
}

// MARK: - Shots

public enum SoccerShotOutcome: String, Codable, Equatable, Hashable {
    case goal
    case saved
    case missed
    case blocked
    case woodwork

    public var isOnTarget: Bool { self == .goal || self == .saved }
}

public enum SoccerShotBodyPart: String, Codable, Equatable, Hashable {
    case rightFoot
    case leftFoot
    case head
    case other
}

public enum SoccerShotSituation: String, Codable, Equatable, Hashable {
    case openPlay
    /// From a corner or an indirect set piece.
    case setPiece
    case directFreeKick
    case penalty
    case fastBreak
}

public struct SoccerShot: Codable, Equatable, Hashable, Identifiable {
    public var id: String
    public var side: BracketSide
    public var playerName: String?
    /// Clock display, e.g. "57'" or "90'+2'".
    public var clock: String
    /// Minutes elapsed when the shot was taken (stoppage time included), for charts.
    public var minute: Double
    /// 1 and 2 are the halves, 3 and 4 extra time. Nil when ESPN omits it.
    public var period: Int?
    public var outcome: SoccerShotOutcome
    public var bodyPart: SoccerShotBodyPart
    public var situation: SoccerShotSituation
    /// Where the shot was taken, 0–100 on both axes from the shooting team's view:
    /// x runs from its own goal line (0) to the goal it attacks (100); y runs from
    /// the shooter's right touchline (0) to the left (100).
    public var x: Double
    public var y: Double
    /// Where the ball crossed the goal line, on the same y scale (50 is the centre
    /// of the goal; the posts are about 44.6 and 55.4). Nil when ESPN omits it.
    public var goalMouthY: Double?
    /// Estimated expected goals — see `SoccerExpectedGoals`.
    public var xG: Double

    public init(
        id: String,
        side: BracketSide,
        playerName: String? = nil,
        clock: String,
        minute: Double,
        period: Int? = nil,
        outcome: SoccerShotOutcome,
        bodyPart: SoccerShotBodyPart = .other,
        situation: SoccerShotSituation = .openPlay,
        x: Double,
        y: Double,
        goalMouthY: Double? = nil,
        xG: Double
    ) {
        self.id = id
        self.side = side
        self.playerName = playerName
        self.clock = clock
        self.minute = minute
        self.period = period
        self.outcome = outcome
        self.bodyPart = bodyPart
        self.situation = situation
        self.x = x
        self.y = y
        self.goalMouthY = goalMouthY
        self.xG = xG
    }
}

// MARK: - Momentum

public struct SoccerMomentumPoint: Codable, Equatable, Hashable {
    /// 1 and 2 are the halves, 3 and 4 extra time.
    public var period: Int
    /// Match minute, running through stoppage: first-half stoppage reads 46, 47…
    /// within period 1, so plot by period rather than by minute alone.
    public var minute: Int
    /// −1…1: positive when the home side is pressing, negative for the away side.
    public var value: Double

    public init(period: Int, minute: Int, value: Double) {
        self.period = period
        self.minute = minute
        self.value = value
    }
}

// MARK: - Commentary

public enum SoccerCommentaryKind: String, Codable, Equatable, Hashable {
    case goal
    case chance
    case card
    case substitution
    case `var`
    case periodBoundary
    case other
}

public struct SoccerCommentaryEntry: Codable, Equatable, Hashable, Identifiable {
    public var id: String
    /// Clock display, e.g. "6'". Nil for un-timed lines.
    public var clock: String?
    public var text: String
    public var kind: SoccerCommentaryKind
    public var side: BracketSide?

    public init(id: String, clock: String? = nil, text: String, kind: SoccerCommentaryKind = .other, side: BracketSide? = nil) {
        self.id = id
        self.clock = clock
        self.text = text
        self.kind = kind
        self.side = side
    }
}

// MARK: - Form and head-to-head

public enum SoccerResult: String, Codable, Equatable, Hashable {
    case win = "W"
    case draw = "D"
    case loss = "L"
}

/// One of a side's recent results, from that side's point of view.
public struct SoccerFormMatch: Codable, Equatable, Hashable, Identifiable {
    public var eventID: String
    public var date: Date?
    public var result: SoccerResult
    public var goalsFor: Int
    public var goalsAgainst: Int
    public var isHome: Bool
    public var opponentName: String
    public var opponentAbbreviation: String?
    public var opponentBadge: String?
    /// e.g. "Premier League".
    public var competition: String?

    public var id: String { eventID }

    public init(
        eventID: String,
        date: Date? = nil,
        result: SoccerResult,
        goalsFor: Int,
        goalsAgainst: Int,
        isHome: Bool,
        opponentName: String,
        opponentAbbreviation: String? = nil,
        opponentBadge: String? = nil,
        competition: String? = nil
    ) {
        self.eventID = eventID
        self.date = date
        self.result = result
        self.goalsFor = goalsFor
        self.goalsAgainst = goalsAgainst
        self.isHome = isHome
        self.opponentName = opponentName
        self.opponentAbbreviation = opponentAbbreviation
        self.opponentBadge = opponentBadge
        self.competition = competition
    }
}

public struct SoccerHeadToHead: Codable, Equatable, Hashable {
    /// ESPN's one-liner, e.g. "LIV leads series 4-1".
    public var summary: String?
    /// Past meetings, most recent first.
    public var matches: [SoccerPastMeeting]

    public init(summary: String? = nil, matches: [SoccerPastMeeting] = []) {
        self.summary = summary
        self.matches = matches
    }
}

public struct SoccerPastMeeting: Codable, Equatable, Hashable, Identifiable {
    public var eventID: String
    public var date: Date?
    public var homeName: String
    public var awayName: String
    public var homeAbbreviation: String?
    public var awayAbbreviation: String?
    public var homeScore: Int?
    public var awayScore: Int?

    public var id: String { eventID }

    public init(
        eventID: String,
        date: Date? = nil,
        homeName: String,
        awayName: String,
        homeAbbreviation: String? = nil,
        awayAbbreviation: String? = nil,
        homeScore: Int? = nil,
        awayScore: Int? = nil
    ) {
        self.eventID = eventID
        self.date = date
        self.homeName = homeName
        self.awayName = awayName
        self.homeAbbreviation = homeAbbreviation
        self.awayAbbreviation = awayAbbreviation
        self.homeScore = homeScore
        self.awayScore = awayScore
    }
}
