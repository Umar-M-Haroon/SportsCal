//
//  SoccerCompetition.swift
//  SportsCalModel
//
//  The two soccer pages beyond a single match:
//
//  - `SoccerCompetitionHub`: one competition's table (with zones, rank change and
//    each side's form), and its top scorers and assisters. Served by
//    `/soccer/competition/:leagueID`. Fixtures come from the app's own schedule.
//  - `SoccerPlayerProfile`: one player's bio, season lines per competition, recent
//    matches and next fixture. Served by `/soccer/player/:athleteID`.
//
//  Both are built server-side from ESPN and fetched on demand, like the match centre.
//

import Foundation

// MARK: - Competition hub

public struct SoccerCompetitionHub: Codable, Equatable, Hashable {
    public var leagueID: Int
    /// One group for a league, several for a group stage.
    public var groups: [SoccerTableGroup]
    public var scorers: [SoccerLeader]
    public var assisters: [SoccerLeader]

    public init(leagueID: Int, groups: [SoccerTableGroup] = [], scorers: [SoccerLeader] = [], assisters: [SoccerLeader] = []) {
        self.leagueID = leagueID
        self.groups = groups
        self.scorers = scorers
        self.assisters = assisters
    }

    public var isEmpty: Bool { groups.isEmpty && scorers.isEmpty && assisters.isEmpty }

    /// Every zone that appears in the table, in table order, for a legend.
    public var zones: [SoccerTableZone] {
        var seen = Set<SoccerTableZone>()
        return groups.flatMap(\.rows).compactMap(\.zone).filter { seen.insert($0).inserted }
    }
}

public struct SoccerTableGroup: Codable, Equatable, Hashable, Identifiable {
    /// Nil for a single-table league; "Group A" etc. otherwise.
    public var name: String?
    public var rows: [SoccerTableRow]

    public var id: String { name ?? "table" }

    public init(name: String? = nil, rows: [SoccerTableRow]) {
        self.name = name
        self.rows = rows
    }
}

public struct SoccerTableRow: Codable, Equatable, Hashable, Identifiable {
    public var rank: Int
    /// ESPN team id.
    public var teamID: String
    public var teamName: String
    public var abbreviation: String?
    public var badge: String?
    public var played: Int
    public var won: Int
    public var drawn: Int
    public var lost: Int
    public var goalsFor: Int
    public var goalsAgainst: Int
    public var points: Int
    /// Places gained (positive) or lost since the last round.
    public var rankChange: Int
    /// The qualification or relegation band this place sits in, if any.
    public var zone: SoccerTableZone?
    /// Last five league results, oldest first.
    public var form: [SoccerResult]

    public var id: String { teamID }
    public var goalDifference: Int { goalsFor - goalsAgainst }

    public init(
        rank: Int, teamID: String, teamName: String, abbreviation: String? = nil, badge: String? = nil,
        played: Int, won: Int, drawn: Int, lost: Int, goalsFor: Int, goalsAgainst: Int, points: Int,
        rankChange: Int = 0, zone: SoccerTableZone? = nil, form: [SoccerResult] = []
    ) {
        self.rank = rank
        self.teamID = teamID
        self.teamName = teamName
        self.abbreviation = abbreviation
        self.badge = badge
        self.played = played
        self.won = won
        self.drawn = drawn
        self.lost = lost
        self.goalsFor = goalsFor
        self.goalsAgainst = goalsAgainst
        self.points = points
        self.rankChange = rankChange
        self.zone = zone
        self.form = form
    }
}

public struct SoccerTableZone: Codable, Equatable, Hashable {
    /// e.g. "Champions League", "Relegation".
    public var description: String
    /// ESPN's band colour, e.g. "#81D6AC".
    public var colorHex: String

    public init(description: String, colorHex: String) {
        self.description = description
        self.colorHex = colorHex
    }
}

public struct SoccerLeader: Codable, Equatable, Hashable, Identifiable {
    public var rank: Int
    public var athleteID: String
    public var name: String
    public var teamName: String?
    public var teamBadge: String?
    public var goals: Int
    public var assists: Int
    public var appearances: Int

    public var id: String { athleteID }

    public init(rank: Int, athleteID: String, name: String, teamName: String? = nil, teamBadge: String? = nil,
                goals: Int = 0, assists: Int = 0, appearances: Int = 0) {
        self.rank = rank
        self.athleteID = athleteID
        self.name = name
        self.teamName = teamName
        self.teamBadge = teamBadge
        self.goals = goals
        self.assists = assists
        self.appearances = appearances
    }
}

// MARK: - Form

/// Last-five form for every team from one list of finished matches, so a whole
/// table's form costs a single season scoreboard fetch.
public enum SoccerForm {
    public struct Result: Equatable {
        public var date: Date
        public var homeID: String
        public var awayID: String
        public var homeScore: Int
        public var awayScore: Int

        public init(date: Date, homeID: String, awayID: String, homeScore: Int, awayScore: Int) {
            self.date = date
            self.homeID = homeID
            self.awayID = awayID
            self.homeScore = homeScore
            self.awayScore = awayScore
        }
    }

    /// Team id → its last `count` results, oldest first.
    public static func lastResults(_ results: [Result], count: Int = 5) -> [String: [SoccerResult]] {
        var byTeam: [String: [SoccerResult]] = [:]
        for match in results.sorted(by: { $0.date < $1.date }) {
            let homeResult: SoccerResult = match.homeScore > match.awayScore ? .win
                : match.homeScore < match.awayScore ? .loss : .draw
            let awayResult: SoccerResult = homeResult == .win ? .loss : homeResult == .loss ? .win : .draw
            byTeam[match.homeID, default: []].append(homeResult)
            byTeam[match.awayID, default: []].append(awayResult)
        }
        return byTeam.mapValues { Array($0.suffix(count)) }
    }
}

// MARK: - Player profile

public struct SoccerPlayerProfile: Codable, Equatable, Hashable {
    public var athleteID: String
    public var name: String
    public var position: String?
    public var jersey: String?
    public var age: Int?
    public var height: String?
    public var nationality: String?
    public var flagURL: String?
    public var teamID: String?
    public var teamName: String?
    /// One line per competition this season (league, cups, internationals).
    public var seasons: [SoccerPlayerSeason]
    /// Most recent first.
    public var recentMatches: [SoccerPlayerMatch]
    public var nextMatch: SoccerPlayerFixture?

    public init(
        athleteID: String, name: String, position: String? = nil, jersey: String? = nil, age: Int? = nil,
        height: String? = nil, nationality: String? = nil, flagURL: String? = nil,
        teamID: String? = nil, teamName: String? = nil,
        seasons: [SoccerPlayerSeason] = [], recentMatches: [SoccerPlayerMatch] = [],
        nextMatch: SoccerPlayerFixture? = nil
    ) {
        self.athleteID = athleteID
        self.name = name
        self.position = position
        self.jersey = jersey
        self.age = age
        self.height = height
        self.nationality = nationality
        self.flagURL = flagURL
        self.teamID = teamID
        self.teamName = teamName
        self.seasons = seasons
        self.recentMatches = recentMatches
        self.nextMatch = nextMatch
    }

    /// Season totals across every competition for one stat key.
    public func total(_ statName: String) -> Int {
        seasons.reduce(0) { sum, season in
            sum + Int(season.stats.first { $0.name == statName }?.value ?? 0)
        }
    }
}

public struct SoccerPlayerSeason: Codable, Equatable, Hashable, Identifiable {
    /// e.g. "2026-27 English Premier League".
    public var competition: String
    public var leagueSlug: String?
    public var stats: [SoccerPlayerStat]

    public var id: String { leagueSlug ?? competition }

    public init(competition: String, leagueSlug: String? = nil, stats: [SoccerPlayerStat]) {
        self.competition = competition
        self.leagueSlug = leagueSlug
        self.stats = stats
    }
}

public struct SoccerPlayerMatch: Codable, Equatable, Hashable, Identifiable {
    public var eventID: String
    public var date: Date?
    public var opponentName: String
    public var opponentAbbreviation: String?
    public var isHome: Bool
    /// From the player's team's view.
    public var result: SoccerResult?
    public var goalsFor: Int?
    public var goalsAgainst: Int?
    public var competition: String?
    /// "Started" or "Substitute", as ESPN reports the appearance.
    public var appearance: String?
    public var stats: [SoccerPlayerStat]

    public var id: String { eventID }

    public init(
        eventID: String, date: Date? = nil, opponentName: String, opponentAbbreviation: String? = nil,
        isHome: Bool, result: SoccerResult? = nil, goalsFor: Int? = nil, goalsAgainst: Int? = nil,
        competition: String? = nil, appearance: String? = nil, stats: [SoccerPlayerStat] = []
    ) {
        self.eventID = eventID
        self.date = date
        self.opponentName = opponentName
        self.opponentAbbreviation = opponentAbbreviation
        self.isHome = isHome
        self.result = result
        self.goalsFor = goalsFor
        self.goalsAgainst = goalsAgainst
        self.competition = competition
        self.appearance = appearance
        self.stats = stats
    }

    /// The numeric value of one of this match's stats, or 0.
    public func stat(_ name: String) -> Int {
        Int(stats.first { $0.name == name }?.value ?? 0)
    }
}

public struct SoccerPlayerFixture: Codable, Equatable, Hashable {
    public var eventID: String
    public var date: Date?
    /// e.g. "Manchester City at Liverpool".
    public var name: String
    public var competition: String?

    public init(eventID: String, date: Date? = nil, name: String, competition: String? = nil) {
        self.eventID = eventID
        self.date = date
        self.name = name
        self.competition = competition
    }
}
