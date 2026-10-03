//
//  F1SessionDetail.swift
//  SportsCalModel
//

import Foundation

/// Post-session race story for one Race or Sprint, served on demand by
/// `GET /f1/session` rather than inside the schedule (which must stay small).
/// Built from OpenF1 once the session has finished, then cached indefinitely.
public struct F1SessionDetail: Codable, Equatable, Hashable {
    public let sessionKey: Int
    public let sessionName: String
    /// OpenF1 `date_start`, ISO 8601.
    public let dateStart: String
    public let totalLaps: Int
    public let timing: F1RaceTiming?
    /// One line per driver for the lap chart.
    public let lapPositions: [F1LapPositions]
    public let neutralizations: [F1Neutralization]
    public let redFlagLaps: [Int]
    public let weather: F1WeatherSummary?

    public init(sessionKey: Int, sessionName: String, dateStart: String, totalLaps: Int,
                timing: F1RaceTiming?, lapPositions: [F1LapPositions], neutralizations: [F1Neutralization],
                redFlagLaps: [Int], weather: F1WeatherSummary?) {
        self.sessionKey = sessionKey
        self.sessionName = sessionName
        self.dateStart = dateStart
        self.totalLaps = totalLaps
        self.timing = timing
        self.lapPositions = lapPositions
        self.neutralizations = neutralizations
        self.redFlagLaps = redFlagLaps
        self.weather = weather
    }
}

public struct F1LapPositions: Codable, Equatable, Hashable {
    public let driverNumber: Int
    public let acronym: String
    public let name: String
    public let teamColour: String?
    /// `positions[0]` is the starting position; `positions[n]` the position after lap n.
    /// Shorter than `totalLaps + 1` when the driver retired.
    public let positions: [Int]

    public init(driverNumber: Int, acronym: String, name: String, teamColour: String?, positions: [Int]) {
        self.driverNumber = driverNumber
        self.acronym = acronym
        self.name = name
        self.teamColour = teamColour
        self.positions = positions
    }
}

public struct F1Neutralization: Codable, Equatable, Hashable {
    public enum Kind: String, Codable, Hashable {
        case safetyCar
        case virtualSafetyCar
    }

    public let kind: Kind
    public let startLap: Int
    public let endLap: Int

    public init(kind: Kind, startLap: Int, endLap: Int) {
        self.kind = kind
        self.startLap = startLap
        self.endLap = endLap
    }
}

public struct F1WeatherSummary: Codable, Equatable, Hashable {
    public let airTempMin: Double
    public let airTempMax: Double
    public let trackTempMin: Double
    public let trackTempMax: Double
    public let rainfall: Bool

    public init(airTempMin: Double, airTempMax: Double, trackTempMin: Double, trackTempMax: Double, rainfall: Bool) {
        self.airTempMin = airTempMin
        self.airTempMax = airTempMax
        self.trackTempMin = trackTempMin
        self.trackTempMax = trackTempMax
        self.rainfall = rainfall
    }
}

// MARK: - Builders (pure; the server feeds them OpenF1 rows)

public enum F1SessionDetailBuilder {
    public struct PositionSample {
        public let driverNumber: Int
        public let date: Date
        public let position: Int
        public init(driverNumber: Int, date: Date, position: Int) {
            self.driverNumber = driverNumber
            self.date = date
            self.position = position
        }
    }

    public struct LapSample {
        public let driverNumber: Int
        public let lapNumber: Int
        public let dateStart: Date?
        public let duration: Double?
        public init(driverNumber: Int, lapNumber: Int, dateStart: Date?, duration: Double?) {
            self.driverNumber = driverNumber
            self.lapNumber = lapNumber
            self.dateStart = dateStart
            self.duration = duration
        }
    }

    public struct RaceControlMessage {
        public let lapNumber: Int?
        public let category: String
        public let flag: String?
        public let message: String
        public init(lapNumber: Int?, category: String, flag: String?, message: String) {
            self.lapNumber = lapNumber
            self.category = category
            self.flag = flag
            self.message = message
        }
    }

    /// Position after each lap = the driver's last position change at or before the
    /// moment that lap ended (next lap's start, else start + duration).
    /// Index 0 is the first recorded position (the grid).
    public static func lapPositions(
        driverNumber: Int,
        positions: [PositionSample],
        laps: [LapSample]
    ) -> [Int] {
        let changes = positions.filter { $0.driverNumber == driverNumber }.sorted { $0.date < $1.date }
        guard let grid = changes.first?.position else { return [] }
        let driverLaps = laps.filter { $0.driverNumber == driverNumber }.sorted { $0.lapNumber < $1.lapNumber }
        let starts = Dictionary(driverLaps.compactMap { lap in lap.dateStart.map { (lap.lapNumber, $0) } },
                                uniquingKeysWith: { first, _ in first })

        var result = [grid]
        for lap in driverLaps where lap.lapNumber >= 1 {
            let end = starts[lap.lapNumber + 1]
                ?? lap.dateStart.flatMap { start in lap.duration.map { start.addingTimeInterval($0) } }
            guard let end else { continue }
            let position = changes.last { $0.date <= end }?.position ?? result.last ?? grid
            // Pad any lap missing timing so index n stays "after lap n".
            while result.count < lap.lapNumber { result.append(result.last ?? grid) }
            if result.count == lap.lapNumber { result.append(position) }
        }
        return result
    }

    /// Safety car / VSC periods from race control. SC runs from "DEPLOYED" to "IN THIS LAP";
    /// VSC from "DEPLOYED" to "ENDING". An unclosed period runs to `totalLaps`.
    public static func neutralizations(from messages: [RaceControlMessage], totalLaps: Int) -> [F1Neutralization] {
        var periods: [F1Neutralization] = []
        var open: (kind: F1Neutralization.Kind, lap: Int)?
        for message in messages where message.category == "SafetyCar" {
            let text = message.message.uppercased()
            guard let lap = message.lapNumber else { continue }
            let kind: F1Neutralization.Kind = text.contains("VIRTUAL") ? .virtualSafetyCar : .safetyCar
            if text.contains("DEPLOYED") {
                if let current = open { periods.append(F1Neutralization(kind: current.kind, startLap: current.lap, endLap: lap)) }
                open = (kind, lap)
            } else if text.contains("IN THIS LAP") || text.contains("ENDING"), let current = open {
                periods.append(F1Neutralization(kind: current.kind, startLap: current.lap, endLap: max(lap, current.lap)))
                open = nil
            }
        }
        if let current = open {
            periods.append(F1Neutralization(kind: current.kind, startLap: current.lap, endLap: max(totalLaps, current.lap)))
        }
        return periods
    }

    public static func redFlagLaps(from messages: [RaceControlMessage]) -> [Int] {
        Array(Set(messages.filter { $0.flag?.uppercased() == "RED" }.compactMap(\.lapNumber))).sorted()
    }

    public static func weatherSummary(air: [Double], track: [Double], rainfall: [Double]) -> F1WeatherSummary? {
        guard let airMin = air.min(), let airMax = air.max(),
              let trackMin = track.min(), let trackMax = track.max() else { return nil }
        return F1WeatherSummary(airTempMin: airMin, airTempMax: airMax, trackTempMin: trackMin,
                                trackTempMax: trackMax, rainfall: rainfall.contains { $0 > 0 })
    }
}
