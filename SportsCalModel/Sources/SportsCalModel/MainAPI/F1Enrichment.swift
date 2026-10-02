//
//  F1Enrichment.swift
//  SportsCalModel
//
//  Created by Umar Haroon on 3/5/26.
//

import Foundation

// MARK: - F1 Standings

public struct F1Standings: Codable, Equatable, Hashable {
    public var driverStandings: [F1DriverStanding]
    public var constructorStandings: [F1ConstructorStanding]
    /// Round these standings are current through (Jolpica `StandingsList.round`).
    public var round: Int?
    /// Grands Prix / sprints still to run after `round`. Computed alongside the
    /// standings so title math never mixes a fresh calendar with stale points.
    public var remainingRaces: Int?
    public var remainingSprints: Int?
    /// The round after `round`, so title math can say what happens "this weekend".
    public var nextRoundName: String?
    public var nextRoundHasSprint: Bool?
    /// Official broadcast team colours from OpenF1, team name → hex ("McLaren": "F47600").
    /// Names vary by source ("Red Bull" / "Red Bull Racing"); look up via `teamColorHex(for:)`.
    public var teamColors: [String: String]?
    /// Driver full name (folded, lowercased) → three-letter code ("nico hulkenberg": "HUL").
    public var driverCodes: [String: String]?

    public init(driverStandings: [F1DriverStanding] = [], constructorStandings: [F1ConstructorStanding] = [],
                round: Int? = nil, remainingRaces: Int? = nil, remainingSprints: Int? = nil,
                nextRoundName: String? = nil, nextRoundHasSprint: Bool? = nil,
                teamColors: [String: String]? = nil, driverCodes: [String: String]? = nil) {
        self.driverStandings = driverStandings
        self.constructorStandings = constructorStandings
        self.round = round
        self.remainingRaces = remainingRaces
        self.remainingSprints = remainingSprints
        self.nextRoundName = nextRoundName
        self.nextRoundHasSprint = nextRoundHasSprint
        self.teamColors = teamColors
        self.driverCodes = driverCodes
    }

    /// Normalizes team names across ESPN / Jolpica / OpenF1 ("Haas F1 Team" == "Haas",
    /// "Red Bull Racing" == "Red Bull"). "Racing Bulls" keeps its name: only a trailing
    /// " racing" is dropped.
    public static func normalizedTeamName(_ name: String) -> String {
        var key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
        for suffix in [" f1 team", " racing", " formula 1 team"] where key.hasSuffix(suffix) {
            key.removeLast(suffix.count)
        }
        return key
    }

    public func teamColorHex(for teamName: String) -> String? {
        guard let teamColors else { return nil }
        let target = Self.normalizedTeamName(teamName)
        return teamColors.first { Self.normalizedTeamName($0.key) == target }?.value
    }

    public static func driverKey(_ fullName: String) -> String {
        fullName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    public func driverCode(for fullName: String) -> String? {
        guard let driverCodes else { return nil }
        if let code = driverCodes[Self.driverKey(fullName)] { return code }
        // ESPN sometimes adds/drops middle names ("Andrea Kimi Antonelli"): fall back to surname.
        let surname = Self.driverKey(fullName).split(separator: " ").last.map(String.init) ?? ""
        let hits = driverCodes.filter { $0.key.split(separator: " ").last.map(String.init) == surname }
        return hits.count == 1 ? hits.first?.value : nil
    }
}

public struct F1DriverStanding: Codable, Equatable, Hashable {
    public let position: Int
    public let driverName: String
    public let constructorName: String
    public let points: Double
    public let wins: Int
    public let nationality: String?

    public init(position: Int, driverName: String, constructorName: String, points: Double, wins: Int, nationality: String? = nil) {
        self.position = position
        self.driverName = driverName
        self.constructorName = constructorName
        self.points = points
        self.wins = wins
        self.nationality = nationality
    }
}

public struct F1ConstructorStanding: Codable, Equatable, Hashable {
    public let position: Int
    public let constructorName: String
    public let points: Double
    public let wins: Int
    public let nationality: String?

    public init(position: Int, constructorName: String, points: Double, wins: Int, nationality: String? = nil) {
        self.position = position
        self.constructorName = constructorName
        self.points = points
        self.wins = wins
        self.nationality = nationality
    }
}

// MARK: - F1 Race Timing (OpenF1 telemetry)

/// Per-race telemetry attached to a Race/Sprint Game. Populated from OpenF1 after
/// the session ends. Data is kept at the per-driver summary level rather than
/// lap-by-lap to keep the payload small enough to ship inside the main schedule.
public struct F1RaceTiming: Codable, Equatable, Hashable {
    public let sessionKey: Int
    public let sessionType: String
    public let drivers: [F1TelemetryDriver]

    public init(sessionKey: Int, sessionType: String, drivers: [F1TelemetryDriver]) {
        self.sessionKey = sessionKey
        self.sessionType = sessionType
        self.drivers = drivers
    }
}

public struct F1TelemetryDriver: Codable, Equatable, Hashable {
    public let driverNumber: Int
    public let name: String
    public let nameAcronym: String
    public let teamName: String
    public let teamColour: String?
    public let headshotURL: String?
    public let fastestLapTime: Double?
    public let fastestLapNumber: Int?
    public let totalLaps: Int
    public let stints: [F1Stint]
    public let pitStops: [F1PitStop]

    public init(driverNumber: Int, name: String, nameAcronym: String, teamName: String, teamColour: String? = nil, headshotURL: String? = nil, fastestLapTime: Double? = nil, fastestLapNumber: Int? = nil, totalLaps: Int = 0, stints: [F1Stint] = [], pitStops: [F1PitStop] = []) {
        self.driverNumber = driverNumber
        self.name = name
        self.nameAcronym = nameAcronym
        self.teamName = teamName
        self.teamColour = teamColour
        self.headshotURL = headshotURL
        self.fastestLapTime = fastestLapTime
        self.fastestLapNumber = fastestLapNumber
        self.totalLaps = totalLaps
        self.stints = stints
        self.pitStops = pitStops
    }
}

public struct F1Stint: Codable, Equatable, Hashable {
    public let stintNumber: Int
    public let lapStart: Int
    public let lapEnd: Int
    public let compound: String
    public let tyreAgeAtStart: Int?

    public init(stintNumber: Int, lapStart: Int, lapEnd: Int, compound: String, tyreAgeAtStart: Int? = nil) {
        self.stintNumber = stintNumber
        self.lapStart = lapStart
        self.lapEnd = lapEnd
        self.compound = compound
        self.tyreAgeAtStart = tyreAgeAtStart
    }
}

public struct F1PitStop: Codable, Equatable, Hashable {
    public let lapNumber: Int
    public let pitDuration: Double?

    public init(lapNumber: Int, pitDuration: Double? = nil) {
        self.lapNumber = lapNumber
        self.pitDuration = pitDuration
    }
}

// MARK: - F1 Circuit Info

public struct F1CircuitInfo: Codable, Equatable, Hashable {
    public let circuitName: String
    public let locality: String
    public let country: String
    public let circuitImageURL: String?
    public let latitude: String?
    public let longitude: String?

    public init(circuitName: String, locality: String, country: String, circuitImageURL: String? = nil, latitude: String? = nil, longitude: String? = nil) {
        self.circuitName = circuitName
        self.locality = locality
        self.country = country
        self.circuitImageURL = circuitImageURL
        self.latitude = latitude
        self.longitude = longitude
    }
}
