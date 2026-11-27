//
//  InjuryReport.swift
//  SportsCalModel
//
//  Created by Umar Haroon on 4/19/26.
//

import Foundation

public struct InjuryReport: Codable, Equatable, Hashable {
    public let playerName: String
    public let position: String?
    public let status: String
    public let detail: String?
    public let comment: String?
    public let headshot: String?
    public let returnDate: String?
    public let date: String?

    public init(
        playerName: String,
        position: String? = nil,
        status: String,
        detail: String? = nil,
        comment: String? = nil,
        headshot: String? = nil,
        returnDate: String? = nil,
        date: String? = nil
    ) {
        self.playerName = playerName
        self.position = position
        self.status = status
        self.detail = detail
        self.comment = comment
        self.headshot = headshot
        self.returnDate = returnDate
        self.date = date
    }
}

/// One injured player, league-wide: what the `/injuries` feed serves so the app can
/// answer "what's X out with, and when is he back?" without opening a game.
///
/// Fields follow ESPN's injury report. `returnDate` is ESPN's *estimate* (a
/// `yyyy-MM-dd` day), often just the next game for day-to-day players and a
/// placeholder for long-term ones, so the app always shows it as approximate and
/// leans on `summary`/`details` for the reporter's own wording ("will miss at least
/// four weeks").
public struct PlayerInjury: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// ESPN's injury entry ID (stable while the entry is open).
    public let id: String
    /// ESPN athlete ID, when the entry links to a player card.
    public let athleteID: String?
    public let playerName: String
    public let position: String?
    public let headshot: String?
    /// Lowercase ESPN league slug: "nba", "nfl", "nhl", "mlb".
    public let league: String
    public let teamName: String
    public let teamAbbreviation: String?
    /// "Out", "Day-To-Day", "Questionable", "Doubtful", "Injured Reserve", "Suspension".
    public let status: String
    /// Where: "Hip", "Knee", "Upper Body".
    public let bodyPart: String?
    /// What: "Inflammation", "Strain", "Surgery". Nil or "Not Specified" when unknown.
    public let injury: String?
    /// "Left", "Right", or nil / "Not Specified".
    public let side: String?
    /// ESPN's estimated return day, `yyyy-MM-dd`.
    public let returnDate: String?
    /// The one-line note ("Landale (hip) is out for Friday's game").
    public let summary: String?
    /// The longer reporter note, usually where the timeline is ("miss at least four weeks").
    public let details: String?
    /// When ESPN last updated the entry (ISO-8601, minute precision).
    public let updated: String?

    public init(id: String, athleteID: String? = nil, playerName: String, position: String? = nil,
                headshot: String? = nil, league: String, teamName: String, teamAbbreviation: String? = nil,
                status: String, bodyPart: String? = nil, injury: String? = nil, side: String? = nil,
                returnDate: String? = nil, summary: String? = nil, details: String? = nil,
                updated: String? = nil) {
        self.id = id
        self.athleteID = athleteID
        self.playerName = playerName
        self.position = position
        self.headshot = headshot
        self.league = league
        self.teamName = teamName
        self.teamAbbreviation = teamAbbreviation
        self.status = status
        self.bodyPart = bodyPart
        self.injury = injury
        self.side = side
        self.returnDate = returnDate
        self.summary = summary
        self.details = details
        self.updated = updated
    }

    /// The per-game shape attached to schedule events (`homeInjuries`/`awayInjuries`).
    public var report: InjuryReport {
        InjuryReport(playerName: playerName, position: position, status: status,
                     detail: injury.flatMap { $0 == "Not Specified" ? nil : $0 } ?? bodyPart,
                     comment: summary ?? details, headshot: headshot,
                     returnDate: returnDate, date: updated)
    }
}

/// Every open injury across the supported leagues.
public struct InjuryFeed: Codable, Equatable, Sendable {
    public let updated: Date?
    public let injuries: [PlayerInjury]

    public init(updated: Date?, injuries: [PlayerInjury]) {
        self.updated = updated
        self.injuries = injuries
    }
}
