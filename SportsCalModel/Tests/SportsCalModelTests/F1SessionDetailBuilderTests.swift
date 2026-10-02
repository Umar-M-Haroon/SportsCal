import XCTest
@testable import SportsCalModel

final class F1SessionDetailBuilderTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }
    private typealias B = F1SessionDetailBuilder

    func testLapPositions_samplesPositionAtEachLapEnd() {
        let positions = [
            B.PositionSample(driverNumber: 1, date: at(-600), position: 3), // grid
            B.PositionSample(driverNumber: 1, date: at(50), position: 2),   // during lap 1
            B.PositionSample(driverNumber: 1, date: at(250), position: 1),  // during lap 3
        ]
        let laps = [
            B.LapSample(driverNumber: 1, lapNumber: 1, dateStart: nil, duration: nil), // lap 1 often has no start
            B.LapSample(driverNumber: 1, lapNumber: 2, dateStart: at(100), duration: 90),
            B.LapSample(driverNumber: 1, lapNumber: 3, dateStart: at(190), duration: 90),
        ]
        // Lap 1 ends when lap 2 starts (t=100) → P2. Lap 2 ends t=190 → P2. Lap 3 ends t=280 → P1.
        XCTAssertEqual(B.lapPositions(driverNumber: 1, positions: positions, laps: laps), [3, 2, 2, 1])
    }

    func testLapPositions_emptyWithoutPositionData() {
        XCTAssertEqual(B.lapPositions(driverNumber: 9, positions: [], laps: []), [])
    }

    func testNeutralizations_pairsDeployAndEnd() {
        let messages = [
            B.RaceControlMessage(lapNumber: 31, category: "SafetyCar", flag: nil, message: "SAFETY CAR DEPLOYED"),
            B.RaceControlMessage(lapNumber: 35, category: "SafetyCar", flag: nil, message: "SAFETY CAR IN THIS LAP"),
            B.RaceControlMessage(lapNumber: 40, category: "SafetyCar", flag: nil, message: "VIRTUAL SAFETY CAR DEPLOYED"),
            B.RaceControlMessage(lapNumber: 41, category: "SafetyCar", flag: nil, message: "VIRTUAL SAFETY CAR ENDING"),
            B.RaceControlMessage(lapNumber: 50, category: "SafetyCar", flag: nil, message: "SAFETY CAR DEPLOYED"),
        ]
        XCTAssertEqual(B.neutralizations(from: messages, totalLaps: 51), [
            F1Neutralization(kind: .safetyCar, startLap: 31, endLap: 35),
            F1Neutralization(kind: .virtualSafetyCar, startLap: 40, endLap: 41),
            F1Neutralization(kind: .safetyCar, startLap: 50, endLap: 51),
        ])
    }

    func testRedFlagLaps() {
        let messages = [
            B.RaceControlMessage(lapNumber: 12, category: "Flag", flag: "RED", message: "RED FLAG"),
            B.RaceControlMessage(lapNumber: 12, category: "Flag", flag: "RED", message: "RED FLAG"),
            B.RaceControlMessage(lapNumber: 5, category: "Flag", flag: "YELLOW", message: "YELLOW IN TRACK SECTOR 4"),
        ]
        XCTAssertEqual(B.redFlagLaps(from: messages), [12])
    }

    func testWeatherSummary() {
        let summary = B.weatherSummary(air: [33.4, 33.7], track: [61.6, 58.0], rainfall: [0, 0])
        XCTAssertEqual(summary, F1WeatherSummary(airTempMin: 33.4, airTempMax: 33.7, trackTempMin: 58.0, trackTempMax: 61.6, rainfall: false))
        XCTAssertNil(B.weatherSummary(air: [], track: [], rainfall: []))
    }

    func testDateParsers_handlesOpenF1MicrosecondTimestamps() throws {
        let date = try XCTUnwrap(DateParsers.parse("2026-09-26T10:07:06.143000+00:00"))
        let whole = try XCTUnwrap(DateParsers.parse("2026-09-26T10:07:06+00:00"))
        XCTAssertEqual(date.timeIntervalSince(whole), 0.143, accuracy: 0.0001)
    }
}
