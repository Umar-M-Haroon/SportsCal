//
//  JolpicaNetworking.swift
//  SportsCalServer
//
//  Created by Umar Haroon on 3/5/26.
//

import Foundation
import Vapor
import SportsCalModel
import Logging

/// Fetches F1 data from the Jolpica API (community successor to Ergast).
/// Base URL: https://api.jolpi.ca/ergast/f1/
/// Rate limits: 4 req/s burst, 500 req/hr sustained. No auth required.
class JolpicaNetworking {
    private static let logger = Logger(label: "com.sportscal.jolpica")
    private static let baseURL = "https://api.jolpi.ca/ergast/f1"

    // MARK: - Response Types

    private struct JolpicaResponse<T: Decodable>: Decodable {
        let MRData: MRData<T>
    }

    private struct MRData<T: Decodable>: Decodable {
        let series: String?
        let total: String?
    }

    // MARK: - Circuit Types

    private struct CircuitTableResponse: Decodable {
        let MRData: CircuitMRData
    }
    private struct CircuitMRData: Decodable {
        let RaceTable: RaceTable
    }
    private struct RaceTable: Decodable {
        let season: String?
        let Races: [JolpicaRace]
    }
    private struct JolpicaRace: Decodable {
        let round: String
        let raceName: String
        let Circuit: JolpicaCircuit
    }
    private struct JolpicaCircuit: Decodable {
        let circuitId: String
        let circuitName: String
        let Location: CircuitLocation
    }
    private struct CircuitLocation: Decodable {
        let lat: String
        let long: String
        let locality: String
        let country: String
    }

    // MARK: - Standings Types

    private struct DriverStandingsResponse: Decodable {
        let MRData: DriverStandingsMRData
    }
    private struct DriverStandingsMRData: Decodable {
        let StandingsTable: DriverStandingsTable
    }
    private struct DriverStandingsTable: Decodable {
        let StandingsLists: [DriverStandingsList]
    }
    private struct DriverStandingsList: Decodable {
        let season: String?
        let round: String?
        let DriverStandings: [JolpicaDriverStanding]
    }
    private struct JolpicaDriverStanding: Decodable {
        let position: String
        let points: String
        let wins: String
        let Driver: JolpicaDriver
        let Constructors: [JolpicaConstructor]
    }
    private struct JolpicaDriver: Decodable {
        let driverId: String
        let givenName: String
        let familyName: String
        let nationality: String?
    }

    private struct ConstructorStandingsResponse: Decodable {
        let MRData: ConstructorStandingsMRData
    }
    private struct ConstructorStandingsMRData: Decodable {
        let StandingsTable: ConstructorStandingsTable
    }
    private struct ConstructorStandingsTable: Decodable {
        let StandingsLists: [ConstructorStandingsList]
    }
    private struct ConstructorStandingsList: Decodable {
        let season: String?
        let round: String?
        let ConstructorStandings: [JolpicaConstructorStanding]
    }
    private struct JolpicaConstructorStanding: Decodable {
        let position: String
        let points: String
        let wins: String
        let Constructor: JolpicaConstructor
    }
    private struct JolpicaConstructor: Decodable {
        let constructorId: String
        let name: String
        let nationality: String?
    }

    // MARK: - Public API

    /// Fetches circuit info for all races in a season.
    /// Returns a dictionary mapping race name → F1CircuitInfo for easy lookup.
    static func getCircuits(client: some Client, season: Int) async -> [String: F1CircuitInfo] {
        let url = "\(baseURL)/\(season).json?limit=30"
        do {
            let response = try await client.get(URI(string: url))
            let decoded = try response.content.decode(CircuitTableResponse.self)
            var circuits: [String: F1CircuitInfo] = [:]
            for race in decoded.MRData.RaceTable.Races {
                let circuit = race.Circuit
                let info = F1CircuitInfo(
                    circuitName: circuit.circuitName,
                    locality: circuit.Location.locality,
                    country: circuit.Location.country,
                    latitude: circuit.Location.lat,
                    longitude: circuit.Location.long
                )
                // Map by race name (e.g. "Australian Grand Prix") for matching with ESPN data
                circuits[race.raceName] = info
            }
            logger.info("Jolpica circuits fetched", metadata: [
                "season": "\(season)",
                "count": "\(circuits.count)"
            ])
            return circuits
        } catch {
            logger.error("Jolpica circuits fetch failed", metadata: [
                "season": "\(season)",
                "error": "\(error)"
            ])
            return [:]
        }
    }

    /// Fetches current driver standings.
    static func getDriverStandings(client: some Client, season: Int) async -> [F1DriverStanding] {
        let url = "\(baseURL)/\(season)/driverstandings.json"
        do {
            let response = try await client.get(URI(string: url))
            let decoded = try response.content.decode(DriverStandingsResponse.self)
            guard let list = decoded.MRData.StandingsTable.StandingsLists.first else { return [] }
            let standings = list.DriverStandings.compactMap { standing -> F1DriverStanding? in
                guard let pos = Int(standing.position),
                      let pts = Double(standing.points),
                      let wins = Int(standing.wins) else { return nil }
                let name = "\(standing.Driver.givenName) \(standing.Driver.familyName)"
                let constructor = standing.Constructors.first?.name ?? ""
                return F1DriverStanding(
                    position: pos, driverName: name, constructorName: constructor,
                    points: pts, wins: wins, nationality: standing.Driver.nationality
                )
            }
            logger.info("Jolpica driver standings fetched", metadata: [
                "season": "\(season)",
                "count": "\(standings.count)"
            ])
            return standings
        } catch {
            logger.error("Jolpica driver standings fetch failed", metadata: [
                "season": "\(season)",
                "error": "\(error)"
            ])
            return []
        }
    }

    /// Fetches current constructor standings.
    static func getConstructorStandings(client: some Client, season: Int) async -> [F1ConstructorStanding] {
        let url = "\(baseURL)/\(season)/constructorstandings.json"
        do {
            let response = try await client.get(URI(string: url))
            let decoded = try response.content.decode(ConstructorStandingsResponse.self)
            guard let list = decoded.MRData.StandingsTable.StandingsLists.first else { return [] }
            let standings = list.ConstructorStandings.compactMap { standing -> F1ConstructorStanding? in
                guard let pos = Int(standing.position),
                      let pts = Double(standing.points),
                      let wins = Int(standing.wins) else { return nil }
                return F1ConstructorStanding(
                    position: pos, constructorName: standing.Constructor.name,
                    points: pts, wins: wins, nationality: standing.Constructor.nationality
                )
            }
            logger.info("Jolpica constructor standings fetched", metadata: [
                "season": "\(season)",
                "count": "\(standings.count)"
            ])
            return standings
        } catch {
            logger.error("Jolpica constructor standings fetch failed", metadata: [
                "season": "\(season)",
                "error": "\(error)"
            ])
            return []
        }
    }
}
