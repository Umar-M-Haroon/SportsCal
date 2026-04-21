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

    public init(driverStandings: [F1DriverStanding] = [], constructorStandings: [F1ConstructorStanding] = []) {
        self.driverStandings = driverStandings
        self.constructorStandings = constructorStandings
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
