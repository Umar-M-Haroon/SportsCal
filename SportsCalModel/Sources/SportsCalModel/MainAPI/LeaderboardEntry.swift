//
//  LeaderboardEntry.swift
//  SportsCalModel
//
//  Created by Umar Haroon on 2/12/26.
//

import Foundation

// MARK: - LeaderboardEntry
public struct LeaderboardEntry: Codable, Equatable, Hashable {
    public let name: String
    public let score: String
    public let position: Int
    public let headshot: String?
    public let thruHole: String?
    public let rounds: [String]
    public let constructor: String?
    public let gap: String?

    public init(name: String, score: String, position: Int, headshot: String? = nil, thruHole: String? = nil, rounds: [String] = [], constructor: String? = nil, gap: String? = nil) {
        self.name = name
        self.score = score
        self.position = position
        self.headshot = headshot
        self.thruHole = thruHole
        self.rounds = rounds
        self.constructor = constructor
        self.gap = gap
    }
}

// MARK: - EventSession
public struct EventSession: Codable, Equatable, Hashable {
    public let sessionType: String
    public let sessionName: String
    public let status: String?
    public let progress: String?
    public let date: String?
    public let leaderboard: [LeaderboardEntry]

    public init(sessionType: String, sessionName: String, status: String? = nil, progress: String? = nil, date: String? = nil, leaderboard: [LeaderboardEntry] = []) {
        self.sessionType = sessionType
        self.sessionName = sessionName
        self.status = status
        self.progress = progress
        self.date = date
        self.leaderboard = leaderboard
    }
}
