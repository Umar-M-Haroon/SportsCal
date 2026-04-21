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
    public init(plays: [Play]?) { self.plays = plays }
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

    public init(eventID: String, lastPlayId: String, plays: [Play], isFinal: Bool, fetchedAt: Date) {
        self.eventID = eventID
        self.lastPlayId = lastPlayId
        self.plays = plays
        self.isFinal = isFinal
        self.fetchedAt = fetchedAt
    }
}
