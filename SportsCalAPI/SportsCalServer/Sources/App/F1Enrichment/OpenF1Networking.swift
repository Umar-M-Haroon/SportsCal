//
//  OpenF1Networking.swift
//  SportsCalServer
//
//  Created by Umar Haroon on 3/5/26.
//

import Foundation
import Vapor
import SportsCalModel
import Logging

/// Fetches F1 data from the OpenF1 API (circuit images, sessions, laps, stints, pits).
/// Base URL: https://api.openf1.org/v1
/// Rate limits: 3 req/s, 30 req/min (free tier). No auth required.
class OpenF1Networking {
    private static let logger = Logger(label: "com.sportscal.openf1")
    private static let baseURL = "https://api.openf1.org/v1"

    // MARK: - Meeting (circuit images)

    struct Meeting: Decodable {
        let meeting_key: Int?
        let meeting_name: String?
        let location: String?
        let country_name: String?
        let circuit_short_name: String?
        let circuit_image: String?
    }

    // MARK: - Sessions

    struct Session: Decodable {
        let session_key: Int
        let session_type: String?
        let session_name: String?
        let date_start: String?
        let date_end: String?
        let meeting_key: Int?
        let circuit_short_name: String?
        let country_name: String?
        let location: String?
        let year: Int?
    }

    // MARK: - Drivers

    struct Driver: Decodable {
        let driver_number: Int?
        let full_name: String?
        let first_name: String?
        let last_name: String?
        let name_acronym: String?
        let team_name: String?
        let team_colour: String?
        let headshot_url: String?
    }

    // MARK: - Laps

    struct Lap: Decodable {
        let driver_number: Int?
        let lap_number: Int?
        let lap_duration: Double?
        let is_pit_out_lap: Bool?
    }

    // MARK: - Stints

    struct StintDTO: Decodable {
        let driver_number: Int?
        let stint_number: Int?
        let lap_start: Int?
        let lap_end: Int?
        let compound: String?
        let tyre_age_at_start: Int?
    }

    // MARK: - Pit

    struct PitDTO: Decodable {
        let driver_number: Int?
        let lap_number: Int?
        let pit_duration: Double?
    }

    /// Fetches meetings for a season. Returns mapping of meeting_name → circuit_image URL.
    /// This gives us track layout images that no other free API provides.
    static func getCircuitImages(client: some Client, year: Int) async -> [String: String] {
        let url = "\(baseURL)/meetings?year=\(year)"
        do {
            let response = try await client.get(URI(string: url))
            let meetings = try response.content.decode([Meeting].self)
            var imageMap: [String: String] = [:]
            for meeting in meetings {
                if let name = meeting.meeting_name, let imageURL = meeting.circuit_image, !imageURL.isEmpty {
                    imageMap[name] = imageURL
                }
            }
            logger.info("OpenF1 circuit images fetched", metadata: [
                "year": "\(year)",
                "count": "\(imageMap.count)"
            ])
            return imageMap
        } catch {
            logger.error("OpenF1 circuit images fetch failed", metadata: [
                "year": "\(year)",
                "error": "\(error)"
            ])
            return [:]
        }
    }

    /// Fetches all Race/Sprint sessions for a given year, sorted newest-first.
    static func getRaceSessions(client: some Client, year: Int) async -> [Session] {
        let url = "\(baseURL)/sessions?year=\(year)&session_type=Race"
        do {
            let response = try await client.get(URI(string: url))
            let sessions = try response.content.decode([Session].self)
            let sorted = sessions.sorted { ($0.date_start ?? "") > ($1.date_start ?? "") }
            logger.info("OpenF1 race sessions fetched", metadata: [
                "year": "\(year)", "count": "\(sorted.count)"
            ])
            return sorted
        } catch {
            logger.error("OpenF1 sessions fetch failed", metadata: ["error": "\(error)"])
            return []
        }
    }

    /// Builds per-driver telemetry for one session by fetching drivers, laps, stints, and pits concurrently.
    /// Returns nil if the session produced no data (e.g. future session).
    static func getRaceTiming(client: some Client, session: Session) async -> F1RaceTiming? {
        let sessionKey = session.session_key
        async let driversTask = fetchDrivers(client: client, sessionKey: sessionKey)
        async let lapsTask = fetchLaps(client: client, sessionKey: sessionKey)
        async let stintsTask = fetchStints(client: client, sessionKey: sessionKey)
        async let pitsTask = fetchPitStops(client: client, sessionKey: sessionKey)

        let drivers = await driversTask
        let laps = await lapsTask
        let stints = await stintsTask
        let pits = await pitsTask

        guard !drivers.isEmpty else {
            logger.notice("OpenF1 session has no driver data, skipping telemetry", metadata: [
                "sessionKey": "\(sessionKey)"
            ])
            return nil
        }

        var telemetry: [F1TelemetryDriver] = []
        for driver in drivers {
            guard let num = driver.driver_number else { continue }
            let driverLaps = laps.filter { $0.driver_number == num }
            let timedLaps = driverLaps.compactMap { lap -> (Int, Double)? in
                guard let n = lap.lap_number, let d = lap.lap_duration, d > 0 else { return nil }
                return (n, d)
            }
            let fastest = timedLaps.min(by: { $0.1 < $1.1 })
            let driverStints = stints
                .filter { $0.driver_number == num }
                .sorted { ($0.stint_number ?? 0) < ($1.stint_number ?? 0) }
                .compactMap { s -> F1Stint? in
                    guard let sn = s.stint_number, let ls = s.lap_start,
                          let le = s.lap_end, let c = s.compound else { return nil }
                    return F1Stint(stintNumber: sn, lapStart: ls, lapEnd: le, compound: c, tyreAgeAtStart: s.tyre_age_at_start)
                }
            let driverPits = pits
                .filter { $0.driver_number == num }
                .sorted { ($0.lap_number ?? 0) < ($1.lap_number ?? 0) }
                .compactMap { p -> F1PitStop? in
                    guard let lap = p.lap_number else { return nil }
                    return F1PitStop(lapNumber: lap, pitDuration: p.pit_duration)
                }

            telemetry.append(F1TelemetryDriver(
                driverNumber: num,
                name: driver.full_name ?? [driver.first_name, driver.last_name].compactMap { $0 }.joined(separator: " "),
                nameAcronym: driver.name_acronym ?? "",
                teamName: driver.team_name ?? "",
                teamColour: driver.team_colour,
                headshotURL: driver.headshot_url,
                fastestLapTime: fastest?.1,
                fastestLapNumber: fastest?.0,
                totalLaps: driverLaps.count,
                stints: driverStints,
                pitStops: driverPits
            ))
        }

        logger.info("OpenF1 race timing built", metadata: [
            "sessionKey": "\(sessionKey)",
            "drivers": "\(telemetry.count)",
            "laps": "\(laps.count)",
            "stints": "\(stints.count)",
            "pits": "\(pits.count)"
        ])

        return F1RaceTiming(
            sessionKey: sessionKey,
            sessionType: session.session_name ?? session.session_type ?? "Race",
            drivers: telemetry.sorted { ($0.totalLaps, $0.driverNumber) > ($1.totalLaps, $1.driverNumber) }
        )
    }

    private static func fetchDrivers(client: some Client, sessionKey: Int) async -> [Driver] {
        let url = "\(baseURL)/drivers?session_key=\(sessionKey)"
        return (try? await client.get(URI(string: url)).content.decode([Driver].self)) ?? []
    }

    private static func fetchLaps(client: some Client, sessionKey: Int) async -> [Lap] {
        let url = "\(baseURL)/laps?session_key=\(sessionKey)"
        return (try? await client.get(URI(string: url)).content.decode([Lap].self)) ?? []
    }

    private static func fetchStints(client: some Client, sessionKey: Int) async -> [StintDTO] {
        let url = "\(baseURL)/stints?session_key=\(sessionKey)"
        return (try? await client.get(URI(string: url)).content.decode([StintDTO].self)) ?? []
    }

    private static func fetchPitStops(client: some Client, sessionKey: Int) async -> [PitDTO] {
        let url = "\(baseURL)/pit?session_key=\(sessionKey)"
        return (try? await client.get(URI(string: url)).content.decode([PitDTO].self)) ?? []
    }
}
