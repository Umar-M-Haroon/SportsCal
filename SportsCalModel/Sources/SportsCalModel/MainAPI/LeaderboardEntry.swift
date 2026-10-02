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
    public let isCut: Bool?
    public let movement: Int?
    public let flagURL: String?
    public let flagAlt: String?
    public let teeTime: String?
    public let roundDetails: [GolfRoundDetail]?

    public init(name: String, score: String, position: Int, headshot: String? = nil, thruHole: String? = nil, rounds: [String] = [], constructor: String? = nil, gap: String? = nil, isCut: Bool? = nil, movement: Int? = nil, flagURL: String? = nil, flagAlt: String? = nil, teeTime: String? = nil, roundDetails: [GolfRoundDetail]? = nil) {
        self.name = name
        self.score = score
        self.position = position
        self.headshot = headshot
        self.thruHole = thruHole
        self.rounds = rounds
        self.constructor = constructor
        self.gap = gap
        self.isCut = isCut
        self.movement = movement
        self.flagURL = flagURL
        self.flagAlt = flagAlt
        self.teeTime = teeTime
        self.roundDetails = roundDetails
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

    /// When the session starts. ESPN sends minute precision ("2026-10-04T07:00Z"),
    /// which `ISO8601DateFormatter` rejects outright — parse through `DateParsers`,
    /// never a bare ISO formatter, or every session date silently comes back nil.
    public var startDate: Date? {
        date.flatMap(DateParsers.parse)
    }

    /// Full human name. ESPN sends sprint sessions as bare "SS"/"SR" codes with
    /// the same code as the name, so derive from the type rather than trusting `sessionName`.
    public var displayName: String {
        switch sessionType.lowercased() {
        case "fp1": "Free Practice 1"
        case "fp2": "Free Practice 2"
        case "fp3": "Free Practice 3"
        case "qual", "qualifying": "Qualifying"
        case "ss", "sq", "sprint qualifying", "sprint shootout": "Sprint Qualifying"
        case "sr", "sprint": "Sprint"
        case "race", "r": "Race"
        default: sessionName.isEmpty ? sessionType : sessionName
        }
    }

    /// Compact label for pills and tabs ("FP1", "Quali", "Sprint Q").
    public var shortName: String {
        switch sessionType.lowercased() {
        case "qual", "qualifying": "Quali"
        case "ss", "sq", "sprint qualifying", "sprint shootout": "Sprint Q"
        case "sr", "sprint": "Sprint"
        case "": sessionName.isEmpty ? "?" : sessionName
        default: sessionType
        }
    }

    /// Ranks by how much the session decides the weekend (race > sprint > quali > practice).
    public var importance: Int {
        switch sessionType.lowercased() {
        case "race", "r": 6
        case "sr", "sprint": 5
        case "qual", "qualifying": 4
        case "ss", "sq", "sprint qualifying", "sprint shootout": 3
        case "fp3": 2
        case "fp2": 1
        default: 0
        }
    }

    /// Practice and qualifying formats are ranked by best lap, not race time.
    public var isTimedLapSession: Bool {
        switch sessionType.lowercased() {
        case "race", "r", "sr", "sprint": false
        default: true
        }
    }
}

public extension Array where Element == EventSession {
    /// The session whose order set `session`'s grid: Qualifying for the Race,
    /// Sprint Qualifying for the Sprint. Nil for practice/qualifying sessions.
    func gridSession(for session: EventSession) -> EventSession? {
        let sourceTypes: Set<String>
        switch session.sessionType.lowercased() {
        case "race", "r": sourceTypes = ["qual", "qualifying"]
        case "sr", "sprint": sourceTypes = ["ss", "sq", "sprint qualifying", "sprint shootout"]
        default: return nil
        }
        return first { sourceTypes.contains($0.sessionType.lowercased()) }
    }

    /// Places gained (+) or lost (−) versus qualifying, keyed by driver name. Approximate
    /// by design: grid penalties and pit-lane starts aren't in the feed, so this is
    /// "vs qualifying", not "vs grid". Empty until qualifying has finished.
    func positionsGainedVsQualifying(in session: EventSession) -> [String: Int] {
        guard let grid = gridSession(for: session), grid.status == "post" else { return [:] }
        let qualifying = Dictionary(
            grid.leaderboard.filter { $0.position > 0 }.map { ($0.name, $0.position) },
            uniquingKeysWith: { first, _ in first }
        )
        var gained: [String: Int] = [:]
        for entry in session.leaderboard where entry.position > 0 {
            if let start = qualifying[entry.name] {
                gained[entry.name] = start - entry.position
            }
        }
        return gained
    }
}
