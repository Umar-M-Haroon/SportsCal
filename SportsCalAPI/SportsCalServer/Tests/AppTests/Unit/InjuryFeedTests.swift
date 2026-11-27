import XCTest
import Foundation
@testable import App
import SportsCalModel

/// ESPN `/injuries` responses (Nov 26 2026, trimmed to a few teams) → `PlayerInjury`.
final class InjuryFeedTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Unit
            .deletingLastPathComponent()      // AppTests
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    func testNBAEntriesKeepWhatWhereAndWhen() throws {
        let injuries = try InjuriesNetworking.parse(fixture("nba_injuries_sample.json"), league: "nba")
        XCTAssertEqual(injuries.count, 4)
        let landale = try XCTUnwrap(injuries.first { $0.playerName == "Jock Landale" })
        XCTAssertEqual(landale.league, "nba")
        XCTAssertEqual(landale.teamName, "Atlanta Hawks")
        XCTAssertEqual(landale.teamAbbreviation, "ATL")
        XCTAssertEqual(landale.athleteID, "3146557")
        XCTAssertEqual(landale.status, "Out")
        XCTAssertEqual(landale.bodyPart, "Hip")
        XCTAssertEqual(landale.injury, "Inflammation")
        XCTAssertEqual(landale.side, "Right")
        XCTAssertEqual(landale.returnDate, "2026-11-29")
        XCTAssertNotNil(landale.summary)
        XCTAssertNotNil(landale.details)
    }

    func testNFLDropsActivePlayersAndUnspecifiedFields() throws {
        let injuries = try InjuriesNetworking.parse(fixture("nfl_injuries_sample.json"), league: "nfl")
        XCTAssertFalse(injuries.contains { $0.status == "Active" })
        XCTAssertFalse(injuries.contains { $0.playerName == "Kedon Slovis" })
        let sharar = try XCTUnwrap(injuries.first { $0.playerName == "Karson Sharar" })
        XCTAssertEqual(sharar.bodyPart, "Groin")
        XCTAssertNil(sharar.injury, "'Not Specified' reads as unknown")
        XCTAssertNil(sharar.side)
        XCTAssertNil(sharar.summary, "a bare 'questionable' isn't a note")
    }

    func testReportsByTeamKeepsTheGamePageShape() throws {
        let injuries = try InjuriesNetworking.parse(fixture("nba_injuries_sample.json"), league: "nba")
        let byTeam = InjuriesNetworking.reportsByTeam(injuries)
        XCTAssertEqual(byTeam["atlanta hawks"]?.count, 3)
        XCTAssertEqual(byTeam["atlanta hawks"]?.first { $0.playerName == "Jock Landale" }?.detail, "Inflammation")
    }

    func testAthleteIDFromPlayerCardLink() {
        XCTAssertEqual(InjuriesNetworking.athleteID(fromLink: "https://www.espn.com/nba/player/_/id/3146557/jock-landale"), "3146557")
        XCTAssertNil(InjuriesNetworking.athleteID(fromLink: "https://www.espn.com/nba/team/_/name/atl"))
    }
}
