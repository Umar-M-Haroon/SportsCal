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
        let date_start: String?
    }

    // MARK: - Position / race control / weather

    struct PositionDTO: Decodable {
        let driver_number: Int?
        let date: String?
        let position: Int?
    }

    struct RaceControlDTO: Decodable {
        let lap_number: Int?
        let category: String?
        let flag: String?
        let message: String?
    }

    struct WeatherDTO: Decodable {
        let air_temperature: Double?
        let track_temperature: Double?
        let rainfall: Double?
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

    struct CircuitImage {
        let meetingName: String
        let location: String?
        let imageURL: String
    }

    /// Fetches meetings for a season with their circuit_image URLs.
    /// This gives us track layout images that no other free API provides.
    /// Not keyed by meeting_name: names repeat (2026 has two "Bahrain Grand Prix"
    /// meetings, Sakhir and Kuala Lumpur), so callers match on location first.
    static func getCircuitImages(client: some Client, year: Int) async -> [CircuitImage] {
        let url = "\(baseURL)/meetings?year=\(year)"
        do {
            let response = try await client.get(URI(string: url))
            let meetings = try response.content.decode([Meeting].self)
            let images: [CircuitImage] = meetings.compactMap { meeting in
                guard let name = meeting.meeting_name, let imageURL = meeting.circuit_image, !imageURL.isEmpty else { return nil }
                return CircuitImage(meetingName: name, location: meeting.location, imageURL: imageURL)
            }
            logger.info("OpenF1 circuit images fetched", metadata: [
                "year": "\(year)",
                "count": "\(images.count)"
            ])
            return images
        } catch {
            logger.error("OpenF1 circuit images fetch failed", metadata: [
                "year": "\(year)",
                "error": "\(error)"
            ])
            return []
        }
    }

    // MARK: - Drivers (team colours, codes)

    private struct OpenF1Driver: Decodable {
        let full_name: String?
        let first_name: String?
        let last_name: String?
        let name_acronym: String?
        let team_name: String?
        let team_colour: String?
    }

    struct DriverDirectory {
        /// Team name → official broadcast hex colour.
        let teamColors: [String: String]
        /// `F1Standings.driverKey(full name)` → three-letter code.
        let driverCodes: [String: String]
    }

    /// Drivers for the most recent session: the current grid with official team colours
    /// and three-letter codes. ESPN's own vehicle.teamColor is unreliable (Williams is
    /// white, Alpine yellow), so these are what the app paints with.
    static func getDriverDirectory(client: some Client) async -> DriverDirectory {
        let url = "\(baseURL)/drivers?session_key=latest"
        do {
            let response = try await client.get(URI(string: url))
            let drivers = try response.content.decode([OpenF1Driver].self)
            var teamColors: [String: String] = [:]
            var driverCodes: [String: String] = [:]
            for driver in drivers {
                if let team = driver.team_name, let colour = driver.team_colour, colour.count == 6 {
                    teamColors[team] = colour.uppercased()
                }
                // full_name is "Lando NORRIS"; first/last are properly cased.
                let name = [driver.first_name, driver.last_name].compactMap { $0 }.joined(separator: " ")
                if !name.isEmpty, let code = driver.name_acronym, !code.isEmpty {
                    driverCodes[F1Standings.driverKey(name)] = code
                }
            }
            logger.info("OpenF1 drivers fetched", metadata: [
                "teams": "\(teamColors.count)",
                "drivers": "\(driverCodes.count)"
            ])
            return DriverDirectory(teamColors: teamColors, driverCodes: driverCodes)
        } catch {
            logger.error("OpenF1 drivers fetch failed", metadata: ["error": "\(error)"])
            return DriverDirectory(teamColors: [:], driverCodes: [:])
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

        return buildRaceTiming(session: session, drivers: await driversTask, laps: await lapsTask,
                               stints: await stintsTask, pits: await pitsTask)
    }

    /// Full post-session story for the race page: timing plus lap chart, safety car
    /// periods and weather. Requests run one at a time with a short gap to stay inside
    /// the free tier's 3 req/s; callers should space sessions out (30 req/min cap).
    static func getSessionDetail(client: some Client, session: Session) async -> F1SessionDetail? {
        let key = session.session_key
        let pace: UInt64 = 400_000_000
        let drivers = await fetchDrivers(client: client, sessionKey: key)
        guard !drivers.isEmpty else { return nil }
        try? await Task.sleep(nanoseconds: pace)
        let laps = await fetchLaps(client: client, sessionKey: key)
        try? await Task.sleep(nanoseconds: pace)
        let stints = await fetchStints(client: client, sessionKey: key)
        try? await Task.sleep(nanoseconds: pace)
        let pits = await fetchPitStops(client: client, sessionKey: key)
        try? await Task.sleep(nanoseconds: pace)
        let positions = await fetch([PositionDTO].self, "\(baseURL)/position?session_key=\(key)", client: client)
        try? await Task.sleep(nanoseconds: pace)
        let raceControl = await fetch([RaceControlDTO].self, "\(baseURL)/race_control?session_key=\(key)", client: client)
        try? await Task.sleep(nanoseconds: pace)
        let weather = await fetch([WeatherDTO].self, "\(baseURL)/weather?session_key=\(key)", client: client)

        guard !laps.isEmpty, !positions.isEmpty else {
            logger.notice("OpenF1 session detail incomplete, will retry", metadata: [
                "sessionKey": "\(key)", "laps": "\(laps.count)", "positions": "\(positions.count)"
            ])
            return nil
        }

        typealias B = F1SessionDetailBuilder
        let positionSamples = positions.compactMap { p -> B.PositionSample? in
            guard let n = p.driver_number, let pos = p.position, let d = p.date.flatMap(DateParsers.parse) else { return nil }
            return B.PositionSample(driverNumber: n, date: d, position: pos)
        }
        let lapSamples = laps.compactMap { l -> B.LapSample? in
            guard let n = l.driver_number, let lap = l.lap_number else { return nil }
            return B.LapSample(driverNumber: n, lapNumber: lap, dateStart: l.date_start.flatMap(DateParsers.parse), duration: l.lap_duration)
        }
        let totalLaps = lapSamples.map(\.lapNumber).max() ?? 0
        let lapPositions = drivers.compactMap { driver -> F1LapPositions? in
            guard let number = driver.driver_number else { return nil }
            let line = B.lapPositions(driverNumber: number, positions: positionSamples, laps: lapSamples)
            guard !line.isEmpty else { return nil }
            return F1LapPositions(
                driverNumber: number,
                acronym: driver.name_acronym ?? "",
                name: [driver.first_name, driver.last_name].compactMap { $0 }.joined(separator: " "),
                teamColour: driver.team_colour,
                positions: line
            )
        }
        let messages = raceControl.compactMap { m -> B.RaceControlMessage? in
            guard let category = m.category, let message = m.message else { return nil }
            return B.RaceControlMessage(lapNumber: m.lap_number, category: category, flag: m.flag, message: message)
        }

        return F1SessionDetail(
            sessionKey: key,
            sessionName: session.session_name ?? "Race",
            dateStart: session.date_start ?? "",
            totalLaps: totalLaps,
            timing: buildRaceTiming(session: session, drivers: drivers, laps: laps, stints: stints, pits: pits),
            // Classification order: most laps completed, then where they finished.
            lapPositions: lapPositions.sorted {
                ($0.positions.count, -($0.positions.last ?? 99)) > ($1.positions.count, -($1.positions.last ?? 99))
            },
            neutralizations: B.neutralizations(from: messages, totalLaps: totalLaps),
            redFlagLaps: B.redFlagLaps(from: messages),
            weather: B.weatherSummary(
                air: weather.compactMap(\.air_temperature),
                track: weather.compactMap(\.track_temperature),
                rainfall: weather.compactMap(\.rainfall)
            )
        )
    }

    private static func fetch<T: Decodable>(_ type: [T].Type, _ url: String, client: some Client) async -> [T] {
        (try? await client.get(URI(string: url)).content.decode([T].self)) ?? []
    }

    private static func buildRaceTiming(session: Session, drivers: [Driver], laps: [Lap],
                                        stints: [StintDTO], pits: [PitDTO]) -> F1RaceTiming? {
        let sessionKey = session.session_key
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
