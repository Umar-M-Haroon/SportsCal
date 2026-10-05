import XCTest
import Foundation
@testable import App
import SportsCalModel

/// IndyCar / IMSA / WEC: TheSportsDB weekend grouping and Al Kamel parsing, against
/// files recorded on 2026-10-05.
final class MotorsportSeriesTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)"))
    }

    private func event(_ id: String, _ name: String, _ time: String, venue: String = "Track") -> TSDBRacingEvent {
        TSDBRacingEvent(idEvent: id, strEvent: name, strTimestamp: time, dateEvent: nil, strVenue: venue, strCountry: nil, intRound: nil)
    }

    // MARK: - Weekends

    func testSessionsGroupUnderTheirRace() {
        let weekends = MotorsportWeekends.group([
            event("1", "6 Hours of Spa Francorchamps Free Practice 1", "2026-05-07T09:00:00"),
            event("2", "6 Hours of Spa Francorchamps Qualifying - LMGT3", "2026-05-08T12:30:00"),
            event("3", "6 Hours of Spa Francorchamps Hyperpole - Hypercar", "2026-05-08T13:45:00"),
            event("4", "6 Hours of Spa Francorchamps", "2026-05-09T00:00:00"),
            event("5", "24 Hours of Le Mans Hyperpole 1 - LMP2 & LMGT3", "2026-06-11T18:00:00", venue: "Sarthe"),
            event("6", "24 Hours of Le Mans Hyperpole Qualifying – Hypercar", "2026-06-10T17:30:00", venue: "Sarthe"),
            event("7", "24 Hours of Le Mans", "2026-06-13T14:00:00", venue: "Sarthe"),
            event("8", "110th Running of the Indianapolis 500 Qualifying 2", "2026-05-17T20:30:00", venue: "IMS"),
            event("9", "110th Running of the Indianapolis 500 Fast Friday", "2026-05-15T16:00:00", venue: "IMS"),
            event("10", "110th Running of the Indianapolis 500", "2026-05-24T16:00:00", venue: "IMS"),
            event("11", "Imola Prologue Morning Session", "2026-04-14T07:00:00"),
            event("12", "Roar Before The Rolex 24", "2026-01-18T00:00:00"),
        ])
        XCTAssertEqual(weekends.map(\.race.strEvent), ["6 Hours of Spa Francorchamps", "110th Running of the Indianapolis 500", "24 Hours of Le Mans"],
                       "sessions, prologues and test days are never races")
        XCTAssertEqual(weekends[0].sessions.map(\.name), ["Free Practice 1", "Qualifying LMGT3", "Hyperpole Hypercar"])
        XCTAssertEqual(weekends[0].sessions.map(\.type), ["practice", "qual", "qual"])
        XCTAssertEqual(weekends[1].sessions.map(\.name), ["Fast Friday", "Qualifying 2"], "the Indy 500's week of May")
        XCTAssertEqual(weekends[2].sessions.count, 2)
    }

    // MARK: - Al Kamel

    func testIMSARaceResults() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(try fixture("imsa_race_results.json"))
        let (entries, duration) = try AlKamelParse.imsaEntries(data, isRace: true)
        XCTAssertEqual(duration, 36000, "Petit Le Mans runs ten hours")
        XCTAssertEqual(entries.count, 12)
        let winner = try XCTUnwrap(entries.first)
        XCTAssertEqual(winner.number, "6")
        XCTAssertEqual(winner.vehicleClass, "GTP")
        XCTAssertEqual(winner.vehicle, "Porsche 963")
        XCTAssertEqual(winner.drivers.count, 3)
        XCTAssertNil(winner.gapFirst, "the leader's '-' is no gap")
        XCTAssertNotNil(winner.pitStops)
        XCTAssertTrue(entries.last?.retired ?? false, "not_finished marks a retirement")

        let rows = MotorsportGameBuilder.enduranceEntries(entries, isRace: true)
        XCTAssertEqual(rows.first { $0.stockCar?.carNumber == "04" }?.stockCar?.classPosition, 1, "LMP2's leader is first in class")
        XCTAssertEqual(rows.last?.gap, "Retired")
        XCTAssertEqual(rows.first?.name.components(separatedBy: " / ").count, 3, "the crew, by surname")
    }

    func testIMSAByClassFileIsReordered() throws {
        let (entries, _) = try AlKamelParse.imsaEntries(try fixture("imsa_quali_by_class.json"), isRace: false)
        XCTAssertEqual(entries.map(\.position), Array(1...entries.count), "overall order rebuilt from the per-class lists")
        let times = entries.map { AlKamelParse.seconds($0.time) }
        XCTAssertEqual(times, times.sorted(), "fastest first")
    }

    func testWECRaceCSV() throws {
        let entries = AlKamelParse.wecEntries(try fixture("wec_race_classification.csv"), isRace: true)
        let winner = try XCTUnwrap(entries.first)
        XCTAssertEqual(winner.number, "8")
        XCTAssertEqual(winner.vehicleClass, "HYPERCAR")
        XCTAssertEqual(winner.manufacturer, "Toyota")
        XCTAssertEqual(winner.drivers, ["Sébastien Buemi", "Brendon Hartley", "Ryo Hirakawa"], "surnames title-cased")
        XCTAssertEqual(winner.time, "6:01:01.299")
        XCTAssertEqual(entries[1].gapFirst, "+0.591")
        XCTAssertGreaterThan(Set(entries.compactMap(\.vehicleClass)).count, 1)
    }

    func testWECHyperpoleCSV() throws {
        let entries = AlKamelParse.wecEntries(try fixture("wec_hyperpole_classification.csv"), isRace: false)
        let pole = try XCTUnwrap(entries.first)
        XCTAssertEqual(pole.number, "15")
        XCTAssertEqual(pole.time, "3:22.564")
        XCTAssertNil(pole.gapFirst)
        XCTAssertEqual(pole.drivers, ["Kevin Magnussen", "Raffaele Marciello", "Dries Vanthoor"])
    }

    func testResultFilePrefersLatestHourAndFinalMark() {
        let files = [
            "Results/26_2026/21_Road Atlanta/01_IMSA WeatherTech SportsCar Championship/202610031210_Race/09_Hour 9/04_Results by Hour_Race_Unofficial.JSON",
            "Results/26_2026/21_Road Atlanta/01_IMSA WeatherTech SportsCar Championship/202610031210_Race/10_Hour 10/04_Results by Hour_Race_Unofficial.JSON",
            "Results/26_2026/21_Road Atlanta/01_IMSA WeatherTech SportsCar Championship/202610031210_Race/10_Hour 10/03_Results_Race_Provisional.JSON",
            "Results/26_2026/21_Road Atlanta/01_IMSA WeatherTech SportsCar Championship/202610031210_Race/10_Hour 10/05_Results by Class_Race_Provisional.JSON",
        ]
        let pick = AlKamelService.resultFile(.imsa, files: files)
        XCTAssertEqual(pick?.path.hasSuffix("03_Results_Race_Provisional.JSON"), true)
        XCTAssertEqual(pick?.hour, 10)
        XCTAssertEqual(pick?.isFinal, true)

        let midRace = AlKamelService.resultFile(.imsa, files: Array(files.prefix(2)))
        XCTAssertEqual(midRace?.hour, 10)
        XCTAssertEqual(midRace?.isFinal, false, "an hourly classification is a race in progress")

        let wec = AlKamelService.resultFile(.wec, files: [
            "Results/15_2026/06_FUJI SPEEDWAY/679_FIA WEC/202609271100_Race/05_Hour 5/03_Classification_Race_Hour 5.CSV",
            "Results/15_2026/06_FUJI SPEEDWAY/679_FIA WEC/202609271100_Race/06_Hour 6/03_Classification_Race_Hour 6._FinalCSV",
            "Results/15_2026/06_FUJI SPEEDWAY/679_FIA WEC/202609271100_Race/06_Hour 6/05_ClassificationByCategory_Race_Hour 6.CSV",
        ])
        XCTAssertEqual(wec?.hour, 6)
        XCTAssertEqual(wec?.isFinal, true, "WEC's misspelt '._FinalCSV' still counts")
    }

    func testLocalFolderTimesShiftToUTC() {
        // Petit Le Mans: folder 12:10 local, TheSportsDB 16:10Z → UTC−4.
        let local = AlKamelParse.sessionFolder("202610031210_Race")?.start
        let utc = MotorsportWeekends.utcDate("2026-10-03T16:10:00")
        XCTAssertEqual(MotorsportGameBuilder.utcOffset(series: .imsa, tsdbRace: utc, localRace: local), -4 * 3600)
        // Midnight on TheSportsDB means "time not announced": fall back to Eastern.
        let midnight = MotorsportWeekends.utcDate("2026-10-03T00:00:00")
        XCTAssertEqual(MotorsportGameBuilder.utcOffset(series: .imsa, tsdbRace: midnight, localRace: local), -4 * 3600)
    }

    func testRaceLengthFromName() {
        XCTAssertEqual(MotorsportGameBuilder.weekendDuration("Mobil 1 Twelve Hours of Sebring"), 12 * 3600)
        XCTAssertEqual(MotorsportGameBuilder.weekendDuration("Rolex 24 At DAYTONA"), 24 * 3600)
        XCTAssertEqual(MotorsportGameBuilder.weekendDuration("6 Hours of Fuji"), 6 * 3600)
        XCTAssertEqual(MotorsportGameBuilder.weekendDuration("Motul Petit Le Mans"), 10 * 3600)
        XCTAssertNil(MotorsportGameBuilder.weekendDuration("Acura Grand Prix of Long Beach"))
    }
}
