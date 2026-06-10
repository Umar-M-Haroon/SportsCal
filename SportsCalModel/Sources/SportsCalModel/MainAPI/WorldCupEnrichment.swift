//
//  WorldCupEnrichment.swift
//  SportsCalModel
//
//  Enrichment payload for the FIFA World Cup: the knockout bracket and the
//  Golden Boot (top scorers) race. Built server-side (see WorldCupEnrichmentJob)
//  and shipped inside the main `LiveScore` schedule so the client picks it up
//  with zero extra fetches — the same pattern as `F1Standings`.
//
//  Squads (`WorldCupSquad`) are intentionally NOT part of the ridealong payload:
//  they are large (~48 teams × ~26 players) and fetched lazily per team via the
//  `/worldcup/squad/:teamID` route.
//

import Foundation

// MARK: - Ridealong enrichment (attached to LiveScore)

public struct WorldCupEnrichment: Codable, Equatable, Hashable {
    public var bracket: WorldCupBracket?
    public var topScorers: [WorldCupScorer]

    public init(bracket: WorldCupBracket? = nil, topScorers: [WorldCupScorer] = []) {
        self.bracket = bracket
        self.topScorers = topScorers
    }

    /// True when there is nothing worth shipping/displaying.
    public var isEmpty: Bool {
        (bracket?.isEmpty ?? true) && topScorers.isEmpty
    }
}

// MARK: - Bracket

/// The knockout bracket. Round structure is derived from ESPN (never hardcoded):
/// the 2026 tournament uses the new 48-team format that begins at the Round of 32.
public struct WorldCupBracket: Codable, Equatable, Hashable {
    /// Ordered earliest → latest (e.g. Round of 32 → Round of 16 → … → Final).
    public var rounds: [WorldCupBracketRound]
    /// Third-place playoff, modeled separately since it sits outside the main tree.
    public var thirdPlacePlayoff: WorldCupBracketMatch?

    public init(rounds: [WorldCupBracketRound] = [], thirdPlacePlayoff: WorldCupBracketMatch? = nil) {
        self.rounds = rounds
        self.thirdPlacePlayoff = thirdPlacePlayoff
    }

    public var isEmpty: Bool {
        rounds.allSatisfy { $0.matches.isEmpty } && thirdPlacePlayoff == nil
    }
}

public struct WorldCupBracketRound: Codable, Equatable, Hashable {
    /// Display name from ESPN, e.g. "Round of 32", "Quarterfinals", "Final".
    public var roundName: String
    /// Stable identifier for ordering / matching (ESPN round id or a derived slug).
    public var slug: String
    public var matches: [WorldCupBracketMatch]

    public init(roundName: String, slug: String, matches: [WorldCupBracketMatch] = []) {
        self.roundName = roundName
        self.slug = slug
        self.matches = matches
    }
}

public enum BracketSide: String, Codable, Equatable, Hashable {
    case home
    case away
}

public struct WorldCupBracketMatch: Codable, Equatable, Hashable {
    /// Links to a `Game.idEvent` once the fixture is scheduled; nil for TBD slots.
    public var eventID: String?
    public var homeTeamName: String?
    public var awayTeamName: String?
    public var homeTeamBadge: String?
    public var awayTeamBadge: String?
    public var homeScore: String?
    public var awayScore: String?
    /// Aggregate / penalties text, reusing the `Game.aggregateScore` convention.
    public var aggregateScore: String?
    public var winner: BracketSide?
    public var date: Date?
    /// Placeholder text for undecided slots, e.g. "Winner Group A".
    public var homePlaceholder: String?
    public var awayPlaceholder: String?
    /// Ordering within the round (top → bottom of the column).
    public var bracketPosition: Int

    public init(
        eventID: String? = nil,
        homeTeamName: String? = nil,
        awayTeamName: String? = nil,
        homeTeamBadge: String? = nil,
        awayTeamBadge: String? = nil,
        homeScore: String? = nil,
        awayScore: String? = nil,
        aggregateScore: String? = nil,
        winner: BracketSide? = nil,
        date: Date? = nil,
        homePlaceholder: String? = nil,
        awayPlaceholder: String? = nil,
        bracketPosition: Int = 0
    ) {
        self.eventID = eventID
        self.homeTeamName = homeTeamName
        self.awayTeamName = awayTeamName
        self.homeTeamBadge = homeTeamBadge
        self.awayTeamBadge = awayTeamBadge
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.aggregateScore = aggregateScore
        self.winner = winner
        self.date = date
        self.homePlaceholder = homePlaceholder
        self.awayPlaceholder = awayPlaceholder
        self.bracketPosition = bracketPosition
    }

    /// True when neither side has a resolved team yet (a pure TBD slot).
    public var isPlaceholder: Bool {
        (homeTeamName?.isEmpty ?? true) && (awayTeamName?.isEmpty ?? true)
    }
}

// MARK: - Golden Boot

public struct WorldCupScorer: Codable, Equatable, Hashable {
    public var rank: Int
    public var playerName: String
    public var teamName: String
    public var teamBadge: String?
    public var headshotURL: String?
    public var goals: Int
    public var assists: Int?

    public init(
        rank: Int,
        playerName: String,
        teamName: String,
        teamBadge: String? = nil,
        headshotURL: String? = nil,
        goals: Int,
        assists: Int? = nil
    ) {
        self.rank = rank
        self.playerName = playerName
        self.teamName = teamName
        self.teamBadge = teamBadge
        self.headshotURL = headshotURL
        self.goals = goals
        self.assists = assists
    }
}

// MARK: - Squads (fetched lazily, not part of the ridealong payload)

public struct WorldCupSquad: Codable, Equatable, Hashable {
    public var teamID: String?
    public var teamName: String
    public var teamBadge: String?
    public var players: [WorldCupSquadPlayer]

    public init(teamID: String? = nil, teamName: String, teamBadge: String? = nil, players: [WorldCupSquadPlayer] = []) {
        self.teamID = teamID
        self.teamName = teamName
        self.teamBadge = teamBadge
        self.players = players
    }
}

public struct WorldCupSquadPlayer: Codable, Equatable, Hashable {
    public var name: String
    public var position: String?
    public var jersey: String?
    public var headshotURL: String?
    public var age: Int?

    public init(name: String, position: String? = nil, jersey: String? = nil, headshotURL: String? = nil, age: Int? = nil) {
        self.name = name
        self.position = position
        self.jersey = jersey
        self.headshotURL = headshotURL
        self.age = age
    }
}
