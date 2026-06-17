//
//  WorldCupBoxScore.swift
//  SportsCalModel
//
//  Per-match box score for a FIFA World Cup fixture: the team stat comparison
//  (possession, shots, fouls…), the goal/card/substitution timeline, and the
//  two lineups with per-player stat lines.
//
//  Built server-side from ESPN's per-event `summary` endpoint and fetched lazily
//  per game via `/worldcup/boxscore/:eventID` — the same on-demand pattern as
//  `WorldCupSquad`. It is intentionally NOT part of the ridealong `LiveScore`
//  payload (one match is large and only needed when a detail view opens).
//
//  `BracketSide` (home/away) is reused from WorldCupEnrichment.
//

import Foundation

// MARK: - Box score

public struct WorldCupBoxScore: Codable, Equatable, Hashable {
    public var eventID: String
    public var home: WorldCupBoxScoreTeam
    public var away: WorldCupBoxScoreTeam
    /// Head-to-head team stats (possession, shots, fouls…), ordered as ESPN returns them.
    public var teamStats: [WorldCupTeamStat]
    /// Goal / card / substitution timeline, ordered earliest → latest.
    public var events: [WorldCupMatchEvent]

    public init(
        eventID: String,
        home: WorldCupBoxScoreTeam,
        away: WorldCupBoxScoreTeam,
        teamStats: [WorldCupTeamStat] = [],
        events: [WorldCupMatchEvent] = []
    ) {
        self.eventID = eventID
        self.home = home
        self.away = away
        self.teamStats = teamStats
        self.events = events
    }

    /// True when there is nothing worth shipping/displaying.
    public var isEmpty: Bool {
        teamStats.isEmpty && events.isEmpty && home.players.isEmpty && away.players.isEmpty
    }
}

// MARK: - Per-team lineup

public struct WorldCupBoxScoreTeam: Codable, Equatable, Hashable {
    public var teamID: String?
    public var teamName: String
    public var teamBadge: String?
    /// Formation string from ESPN, e.g. "4-2-3-1". Nil if not provided.
    public var formation: String?
    /// Starters first (by formation place), then substitutes.
    public var players: [WorldCupBoxScorePlayer]

    public init(
        teamID: String? = nil,
        teamName: String,
        teamBadge: String? = nil,
        formation: String? = nil,
        players: [WorldCupBoxScorePlayer] = []
    ) {
        self.teamID = teamID
        self.teamName = teamName
        self.teamBadge = teamBadge
        self.formation = formation
        self.players = players
    }
}

public struct WorldCupBoxScorePlayer: Codable, Equatable, Hashable, Identifiable {
    public var athleteID: String?
    public var name: String
    public var jersey: String?
    /// Position abbreviation, e.g. "G", "D", "M", "F".
    public var position: String?
    public var positionName: String?
    public var starter: Bool
    public var subbedIn: Bool
    public var subbedOut: Bool
    /// Notable stat lines for this player (goals, shots, fouls…), already trimmed
    /// server-side to the meaningful ones.
    public var stats: [WorldCupPlayerStat]

    public var id: String { athleteID ?? "\(name)-\(jersey ?? "")" }

    public init(
        athleteID: String? = nil,
        name: String,
        jersey: String? = nil,
        position: String? = nil,
        positionName: String? = nil,
        starter: Bool = false,
        subbedIn: Bool = false,
        subbedOut: Bool = false,
        stats: [WorldCupPlayerStat] = []
    ) {
        self.athleteID = athleteID
        self.name = name
        self.jersey = jersey
        self.position = position
        self.positionName = positionName
        self.starter = starter
        self.subbedIn = subbedIn
        self.subbedOut = subbedOut
        self.stats = stats
    }
}

public struct WorldCupPlayerStat: Codable, Equatable, Hashable {
    /// ESPN stat key, e.g. "goals", "shotsTotal", "foulsCommitted".
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

public struct WorldCupTeamStat: Codable, Equatable, Hashable, Identifiable {
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

public enum WorldCupMatchEventType: String, Codable, Equatable, Hashable {
    case goal
    case ownGoal
    case penaltyGoal
    case penaltyMissed
    case yellowCard
    case redCard
    case substitution
    case other
}

public struct WorldCupMatchEvent: Codable, Equatable, Hashable, Identifiable {
    public var id: String
    public var type: WorldCupMatchEventType
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
        type: WorldCupMatchEventType,
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
