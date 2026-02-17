//
//  V2Wrappers.swift
//  SportsCalModel
//
//  Wrapper models for TheSportsDB v2 API responses
//  v2 uses different field names than v1
//

import Foundation

// MARK: - V2 Live Score Response
public struct V2LiveScoreResponse: Codable {
    public let livescore: [Game]

    enum CodingKeys: String, CodingKey {
        case livescore
    }

    /// Convert to v1 LiveEvent format
    public func toLiveEvent() -> LiveEvent {
        return LiveEvent(events: livescore)
    }
}

// MARK: - V2 Teams Response
public struct V2TeamsResponse: Codable, Hashable {
    public let list: [Team]

    enum CodingKeys: String, CodingKey {
        case list
    }

    /// Convert to v1 Teams format
    public func toTeams() -> Teams {
        return Teams(teams: list)
    }
}

// MARK: - V2 Schedule Response
public struct V2ScheduleResponse: Codable, Hashable {
    public let schedule: [Game]

    enum CodingKeys: String, CodingKey {
        case schedule
    }

    /// Convert to v1 LiveEvent format (same structure)
    public func toLiveEvent() -> LiveEvent {
        return LiveEvent(events: schedule)
    }
}

// MARK: - V2 No Data Response
public struct V2NoDataResponse: Codable {
    public let message: String

    enum CodingKeys: String, CodingKey {
        case message = "Message"
    }
}
