//
//  ScoreboardExtras.swift
//  SportsCalModel
//
//  Per-game facts from ESPN's scoreboard beyond the score: who won (covering shootouts,
//  retirements and walkovers), shootout goals, baseball hits / errors / pitchers, soccer
//  goals and cards, and the TV networks. Built in `LiveEvent(events:league:)`, carried
//  on `Game.scoreboardExtras`, and read through the forwarding properties on `Game`
//  (`homeWinner`, `soccerDetails`, …).
//
//  Kept as one value so a merge takes ESPN's copy whole: a fresh board that no longer
//  names a winner must not fall back to a stale one. Old clients ignore the `extras`
//  key; every field is optional.
//

import Foundation

public struct ScoreboardExtras: Codable, Equatable, Hashable, Sendable {
    /// ESPN's `competitor.winner`. Nil until the game is decided.
    public var homeWinner: Bool?
    public var awayWinner: Bool?
    /// Soccer penalty-shootout goals.
    public var homeShootoutScore: Int?
    public var awayShootoutScore: Int?
    /// Baseball hits and errors.
    public var homeHits: Int?
    public var awayHits: Int?
    public var homeErrors: Int?
    public var awayErrors: Int?
    /// Baseball probable starters, before first pitch.
    public var homeProbable: ProbablePitcher?
    public var awayProbable: ProbablePitcher?
    /// Goals, cards and shootout kicks, in match order. Soccer only. Dropped from the
    /// schedule a few days after full time (`withoutHeavyDetail`).
    public var soccerDetails: [MatchIncident]?
    /// TV / streaming networks, e.g. ["ESPN", "ABC"].
    public var broadcasts: [String]?
    /// Baseball's winning, losing and saving pitchers, once the game is final.
    public var featuredPitchers: [FeaturedPitcher]?
    /// Tennis: per-set tiebreaks and winners, who's serving, the court. See ``TennisMatchExtras``.
    public var tennis: TennisMatchExtras?

    public init(homeWinner: Bool? = nil, awayWinner: Bool? = nil,
                homeShootoutScore: Int? = nil, awayShootoutScore: Int? = nil,
                homeHits: Int? = nil, awayHits: Int? = nil, homeErrors: Int? = nil, awayErrors: Int? = nil,
                homeProbable: ProbablePitcher? = nil, awayProbable: ProbablePitcher? = nil,
                soccerDetails: [MatchIncident]? = nil, broadcasts: [String]? = nil,
                featuredPitchers: [FeaturedPitcher]? = nil, tennis: TennisMatchExtras? = nil) {
        self.homeWinner = homeWinner
        self.awayWinner = awayWinner
        self.homeShootoutScore = homeShootoutScore
        self.awayShootoutScore = awayShootoutScore
        self.homeHits = homeHits
        self.awayHits = awayHits
        self.homeErrors = homeErrors
        self.awayErrors = awayErrors
        self.homeProbable = homeProbable
        self.awayProbable = awayProbable
        self.soccerDetails = soccerDetails
        self.broadcasts = broadcasts
        self.featuredPitchers = featuredPitchers
        self.tennis = tennis
    }

    /// Nothing to carry.
    public var isEmpty: Bool {
        self == ScoreboardExtras()
    }

    /// This copy without the lists only a recent game needs (goal/card timeline, the
    /// pitchers), for finished games the schedule keeps for months.
    public var withoutHeavyDetail: ScoreboardExtras {
        var slim = self
        slim.soccerDetails = nil
        slim.homeProbable = nil
        slim.awayProbable = nil
        slim.featuredPitchers = nil
        return slim
    }
}

/// A probable starting pitcher.
public struct ProbablePitcher: Codable, Equatable, Hashable, Sendable {
    public var name: String
    /// Season line as ESPN shows it, e.g. "10-5, 3.21 ERA". Nil when ESPN sends none.
    public var record: String?

    public init(name: String, record: String? = nil) {
        self.name = name
        self.record = record
    }
}

/// A pitcher of record on a final baseball game.
public struct FeaturedPitcher: Codable, Equatable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case win = "W", loss = "L", save = "SV"
    }

    public var role: Role
    public var name: String
    public var side: GameSituation.Side?
    /// e.g. "(12-4)" for a W/L, "(31)" saves.
    public var line: String?

    public init(role: Role, name: String, side: GameSituation.Side? = nil, line: String? = nil) {
        self.role = role
        self.name = name
        self.side = side
        self.line = line
    }
}

/// A goal, card or shootout kick in a soccer match.
public struct MatchIncident: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case goal, penaltyGoal, ownGoal, yellowCard, redCard, shootoutGoal, shootoutMiss, other

        public init(from decoder: Decoder) throws {
            // A kind added by a newer server reads as `.other`, not a failed game.
            self = (try? Kind(rawValue: decoder.singleValueContainer().decode(String.self))) ?? .other
        }
    }

    public var kind: Kind
    /// Match minute as ESPN shows it: "21'", "90'+3'".
    public var clock: String?
    public var athlete: String?
    public var side: GameSituation.Side?
    /// ESPN's own label ("Goal - Header", "Penalty - Scored"), for kinds we don't model.
    public var text: String?

    public init(kind: Kind, clock: String? = nil, athlete: String? = nil, side: GameSituation.Side? = nil, text: String? = nil) {
        self.kind = kind
        self.clock = clock
        self.athlete = athlete
        self.side = side
        self.text = text
    }
}

// MARK: - From ESPN

extension ScoreboardExtras {
    /// Built from a team-sport competition. Nil when ESPN sent none of it.
    init?(competition: Competition, status: Status?, home: Competitor, away: Competitor,
          homeTeamID: String, sport: SportType) {
        func int(_ number: ESPNFlexibleNumber?) -> Int? {
            number?.value.map { Int($0) }
        }
        func side(_ teamID: String?) -> GameSituation.Side? {
            guard let teamID else { return nil }
            return teamID == homeTeamID ? .home : (teamID == away.team?.id ? .away : nil)
        }
        var extras = ScoreboardExtras(
            homeWinner: home.winner, awayWinner: away.winner,
            homeShootoutScore: int(home.shootoutScore), awayShootoutScore: int(away.shootoutScore),
            broadcasts: Self.broadcastNames(competition.broadcasts)
        )
        if sport == .mlb {
            extras.homeHits = int(home.hits)
            extras.awayHits = int(away.hits)
            extras.homeErrors = int(home.errors)
            extras.awayErrors = int(away.errors)
            extras.homeProbable = home.probables.flatMap(ProbablePitcher.init(espn:))
            extras.awayProbable = away.probables.flatMap(ProbablePitcher.init(espn:))
            let featured = (status?.featuredAthletes ?? []).compactMap { FeaturedPitcher(espn: $0, side: side) }
            extras.featuredPitchers = featured.isEmpty ? nil : featured
        }
        if sport == .soccer {
            let incidents = (competition.details ?? []).compactMap { MatchIncident(espn: $0, side: side) }
            extras.soccerDetails = incidents.isEmpty ? nil : incidents
        }
        guard !extras.isEmpty else { return nil }
        self = extras
    }

    /// Distinct network names in ESPN's order.
    static func broadcastNames(_ broadcasts: [Broadcast]?) -> [String]? {
        var names: [String] = []
        for name in (broadcasts ?? []).flatMap(\.names) where !name.isEmpty && !names.contains(name) {
            names.append(name)
        }
        return names.isEmpty ? nil : names
    }
}

extension ProbablePitcher {
    /// The starting pitcher among a competitor's probables.
    init?(espn probables: [ESPNProbable]) {
        let starter = probables.first { $0.name == "probableStartingPitcher" } ?? probables.first
        guard let starter, let name = starter.athlete?.displayName ?? starter.athlete?.shortName else { return nil }
        self.name = name
        if let record = starter.record, !record.isEmpty {
            self.record = record
        } else {
            let era = starter.statistics?.first { $0.abbreviation == "ERA" || $0.name == "ERA" }?.displayValue
            self.record = era.map { "\($0) ERA" }
        }
    }
}

extension FeaturedPitcher {
    init?(espn: ESPNFeaturedAthlete, side: (String?) -> GameSituation.Side?) {
        let role: Role
        switch espn.name {
        case "winningPitcher": role = .win
        case "losingPitcher": role = .loss
        case "savingPitcher": role = .save
        default:
            guard let abbreviation = espn.abbreviation, let parsed = Role(rawValue: abbreviation) else { return nil }
            role = parsed
        }
        guard let name = espn.athlete?.shortName ?? espn.athlete?.displayName else { return nil }
        self.role = role
        self.name = name
        self.side = side(espn.team?.id ?? espn.athlete?.team?.id)
        // ESPN's featured stats lead with the season record ("12-4") or saves.
        self.line = espn.statistics?.first?.displayValue.map { "(\($0))" }
    }
}

extension MatchIncident {
    init?(espn: ESPNCompetitionDetail, side: (String?) -> GameSituation.Side?) {
        let text = espn.type?.text
        let lower = (text ?? "").lowercased()
        let kind: Kind
        if espn.shootout == true {
            kind = (espn.scoringPlay == true) ? .shootoutGoal : .shootoutMiss
        } else if espn.redCard == true {
            kind = .redCard
        } else if espn.yellowCard == true {
            kind = .yellowCard
        } else if espn.ownGoal == true {
            kind = .ownGoal
        } else if espn.scoringPlay == true {
            kind = espn.penaltyKick == true ? .penaltyGoal : .goal
        } else if lower.isEmpty {
            return nil
        } else {
            kind = .other
        }
        self.kind = kind
        self.clock = espn.clock?.displayValue
        self.athlete = espn.athletesInvolved?.first.flatMap { $0.displayName ?? $0.shortName }
        self.side = side(espn.team?.id)
        self.text = text
    }
}

// MARK: - On Game

public extension Game {
    /// ESPN's `winner` for the home side. See ``ScoreboardExtras``.
    var homeWinner: Bool? { scoreboardExtras?.homeWinner }
    var awayWinner: Bool? { scoreboardExtras?.awayWinner }
    var homeShootoutScore: Int? { scoreboardExtras?.homeShootoutScore }
    var awayShootoutScore: Int? { scoreboardExtras?.awayShootoutScore }
    var homeHits: Int? { scoreboardExtras?.homeHits }
    var awayHits: Int? { scoreboardExtras?.awayHits }
    var homeErrors: Int? { scoreboardExtras?.homeErrors }
    var awayErrors: Int? { scoreboardExtras?.awayErrors }
    var homeProbable: ProbablePitcher? { scoreboardExtras?.homeProbable }
    var awayProbable: ProbablePitcher? { scoreboardExtras?.awayProbable }
    var soccerDetails: [MatchIncident]? { scoreboardExtras?.soccerDetails }
    var broadcasts: [String]? { scoreboardExtras?.broadcasts }
    var featuredPitchers: [FeaturedPitcher]? { scoreboardExtras?.featuredPitchers }
    var tennisExtras: TennisMatchExtras? { scoreboardExtras?.tennis }

    /// A rank or bracket seed after a merge. For college (where ESPN's curated rank is
    /// the only source) a fresh copy is final even when it's nil — a team that falls out
    /// of the Top 25 loses its number. Elsewhere a missing fresh value keeps the old one.
    static func mergedSeed(fresh: Int?, stale: Int?, idLeague: String?) -> Int? {
        let league = idLeague.flatMap { Int($0) }.flatMap(Leagues.init(rawValue:))
        if league == .ncaaf || league == .ncaaMBBTournament { return fresh }
        return fresh ?? stale
    }
}
