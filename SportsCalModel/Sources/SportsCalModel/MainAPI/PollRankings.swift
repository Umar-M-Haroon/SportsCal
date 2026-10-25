//
//  PollRankings.swift
//  SportsCalModel
//
//  College polls — AP Top 25, the Coaches Poll and the lower-division polls — for one
//  week of a season. Built by the server from ESPN's rankings (the latest week from the
//  site API, earlier weeks from the core API).
//

import Foundation

public struct PollRankings: Codable, Equatable, Hashable, Sendable {
    /// `Leagues` raw value.
    public var league: Int
    /// ESPN's season year (2026 for the 2026 football season, 2027 for 2026–27 basketball).
    public var season: Int
    /// The week these polls are from.
    public var week: Week
    /// Every week with polls so far this season, oldest first, ending at the latest.
    public var weeks: [Week]
    public var polls: [Poll]

    public init(league: Int, season: Int, week: Week, weeks: [Week], polls: [Poll]) {
        self.league = league
        self.season = season
        self.week = week
        self.weeks = weeks
        self.polls = polls
    }

    public struct Week: Codable, Equatable, Hashable, Sendable, Identifiable {
        /// ESPN season type: 1 preseason, 2 regular season, 3 postseason.
        public var seasonType: Int
        public var number: Int
        /// "Preseason", "Week 8", "Final Rankings".
        public var label: String

        public var id: String { "\(seasonType)-\(number)" }

        public init(seasonType: Int, number: Int, label: String) {
            self.seasonType = seasonType
            self.number = number
            self.label = label
        }
    }

    public struct Poll: Codable, Equatable, Hashable, Sendable, Identifiable {
        /// ESPN's poll ID: "1" AP, "2" Coaches, "21" College Football Playoff…
        public var id: String
        /// "AP Top 25".
        public var name: String
        /// "AP Poll".
        public var shortName: String
        /// The release date, ISO 8601 as ESPN sends it ("2026-10-18T07:00Z").
        public var date: String?
        public var ranks: [Entry]
        /// Others receiving votes, most points first.
        public var others: [Entry]
        /// Ranked last week, not this week.
        public var droppedOut: [Entry]

        public init(id: String, name: String, shortName: String, date: String?,
                    ranks: [Entry], others: [Entry], droppedOut: [Entry]) {
            self.id = id
            self.name = name
            self.shortName = shortName
            self.date = date
            self.ranks = ranks
            self.others = others
            self.droppedOut = droppedOut
        }

        public var releaseDate: Date? { date.flatMap(DateParsers.parse) }
    }

    public struct Entry: Codable, Equatable, Hashable, Sendable, Identifiable {
        /// Nil for others receiving votes and dropped-out teams.
        public var rank: Int?
        /// Last week's rank; nil when unranked last week.
        public var previous: Int?
        public var points: Double?
        public var firstPlaceVotes: Int?
        /// "6-0". Only ranked teams carry one — ESPN sends "0-0" for everyone else.
        public var record: String?
        public var team: Team

        public var id: String { team.id }

        public init(rank: Int?, previous: Int?, points: Double?, firstPlaceVotes: Int?,
                    record: String?, team: Team) {
            self.rank = rank
            self.previous = previous
            self.points = points
            self.firstPlaceVotes = firstPlaceVotes
            self.record = record
            self.team = team
        }

        /// Places moved since last week: positive is up. Nil when unranked either week.
        /// Computed from the ranks rather than ESPN's `trend`, which is wrong for
        /// unranked teams ("+18" for a team that dropped out of 18th).
        public var movement: Int? {
            guard let rank, let previous else { return nil }
            return previous - rank
        }

        /// Ranked this week but not last.
        public var isNew: Bool { rank != nil && previous == nil }
    }

    public struct Team: Codable, Equatable, Hashable, Sendable {
        /// ESPN team ID.
        public var id: String
        /// "Ohio State".
        public var location: String
        /// "Buckeyes".
        public var name: String
        public var abbreviation: String?
        /// Hex without "#".
        public var color: String?
        public var logo: String?
        public var darkLogo: String?
        /// "SEC", "Big Ten"; nil for lower-division polls where ESPN omits it.
        public var conference: String?

        public init(id: String, location: String, name: String, abbreviation: String?,
                    color: String?, logo: String?, darkLogo: String?, conference: String?) {
            self.id = id
            self.location = location
            self.name = name
            self.abbreviation = abbreviation
            self.color = color
            self.logo = logo
            self.darkLogo = darkLogo
            self.conference = conference
        }

        /// "Ohio State Buckeyes".
        public var displayName: String { name.isEmpty ? location : "\(location) \(name)" }
    }
}

public extension Leagues {
    /// Leagues with weekly polls.
    var hasPollRankings: Bool { self == .ncaaf || self == .ncaaMBBTournament }
}
