// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let competition = try? newJSONDecoder().decode(Competition.self, from: jsonData)

import Foundation

// MARK: - Competition
public struct Competition: Codable {
    public var id, uid, date: String
    public var attendance: Int?
    public var type: CompetitionType?
    public var timeValid, neutralSite, conferenceCompetition, recent: Bool?
    public var venue: Venue?
    public var competitors: [Competitor]?
    public var situation: Situation?
    public var status: Status?
    public var broadcasts: [Broadcast]?
    public var format: Format?
    public var startDate: String?
    public var geoBroadcasts: [GeoBroadcast]?
    public var tickets: [Ticket]?
    public var leg: CompetitionLeg?
    public var series: CompetitionSeries?
    public var notes: [CompetitionNote]?
    /// Tennis: round metadata (e.g. "Quarterfinal"). Present on ESPN tennis competitions.
    public var round: CompetitionRound?

    public init(id: String, uid: String, date: String, attendance: Int? = nil, type: CompetitionType? = nil, timeValid: Bool? = nil, neutralSite: Bool? = nil, conferenceCompetition: Bool? = nil, recent: Bool? = nil, venue: Venue? = nil, competitors: [Competitor]? = nil, situation: Situation? = nil, status: Status? = nil, broadcasts: [Broadcast]? = nil, format: Format? = nil, startDate: String? = nil, geoBroadcasts: [GeoBroadcast]? = nil, tickets: [Ticket]? = nil, leg: CompetitionLeg? = nil, series: CompetitionSeries? = nil, notes: [CompetitionNote]? = nil, round: CompetitionRound? = nil) {
        self.id = id
        self.uid = uid
        self.date = date
        self.attendance = attendance
        self.type = type
        self.timeValid = timeValid
        self.neutralSite = neutralSite
        self.conferenceCompetition = conferenceCompetition
        self.recent = recent
        self.venue = venue
        self.competitors = competitors
        self.situation = situation
        self.status = status
        self.broadcasts = broadcasts
        self.format = format
        self.startDate = startDate
        self.geoBroadcasts = geoBroadcasts
        self.tickets = tickets
        self.leg = leg
        self.series = series
        self.notes = notes
        self.round = round
    }
}

// MARK: - CompetitionRound
public struct CompetitionRound: Codable {
    public var id: String?
    public var displayName: String?
}

// MARK: - CompetitionLeg
public struct CompetitionLeg: Codable {
    public var value: Int
    public var displayValue: String
}

// MARK: - CompetitionSeries
public struct CompetitionSeries: Codable {
    public var type: String?
    public var title: String?
    public var summary: String?
    public var totalCompetitions: Int?
    public var completed: Bool?
    public var competitors: [SeriesCompetitor]?
}

// MARK: - SeriesCompetitor
public struct SeriesCompetitor: Codable {
    public var id: String?
    public var uid: String?
    public var winner: Bool?
    /// Series wins for this competitor (NBA/NHL/MLB). Nil for soccer knockouts.
    public var wins: Int?
    public var ties: Int?
    /// Aggregate goals for soccer knockout ties (UCL etc.). Nil for North American series.
    public var aggregateScore: Double?
}

// MARK: - CompetitionNote
public struct CompetitionNote: Codable {
    public var text: String?
    public var headline: String?
    public var type: String?
}
