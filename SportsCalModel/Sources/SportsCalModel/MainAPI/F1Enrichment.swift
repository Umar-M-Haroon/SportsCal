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
