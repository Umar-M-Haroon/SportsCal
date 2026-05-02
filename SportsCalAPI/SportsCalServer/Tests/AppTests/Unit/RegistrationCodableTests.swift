@testable import App
import XCTest

final class RegistrationCodableTests: XCTestCase {

    // MARK: - APNSRegistration

    func test_apnsRegistration_roundTrip_withTeams() throws {
        let original = APNSRegistration(eventID: "e1", homeTeam: "Lakers", awayTeam: "Warriors")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(APNSRegistration.self, from: data)
        XCTAssertEqual(decoded.eventID, original.eventID)
        XCTAssertEqual(decoded.homeTeam, original.homeTeam)
        XCTAssertEqual(decoded.awayTeam, original.awayTeam)
    }

    func test_apnsRegistration_roundTrip_withNilTeams() throws {
        let original = APNSRegistration(eventID: "e1", homeTeam: nil, awayTeam: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(APNSRegistration.self, from: data)
        XCTAssertEqual(decoded.eventID, original.eventID)
        XCTAssertNil(decoded.homeTeam)
        XCTAssertNil(decoded.awayTeam)
    }

    // MARK: - PushToStartRegistration

    func test_pushToStartRegistration_decodesFromClient() throws {
        let json = #"""
        {"token":"abc123","favorites":["Lakers","Warriors"],"eventIDs":["evt-1","evt-2"]}
        """#
        let decoded = try JSONDecoder().decode(PushToStartRegistration.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.token, "abc123")
        XCTAssertEqual(decoded.favorites, ["Lakers", "Warriors"])
        XCTAssertEqual(decoded.eventIDs, ["evt-1", "evt-2"])
    }

    func test_pushToStartRegistration_decodesWithoutOptionalEventIDs() throws {
        let json = #"""
        {"token":"abc123","favorites":["Lakers"]}
        """#
        let decoded = try JSONDecoder().decode(PushToStartRegistration.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.token, "abc123")
        XCTAssertNil(decoded.eventIDs)
    }

    // MARK: - LiveSportAttributes

    func test_liveSportAttributes_roundTrip() throws {
        let original = LiveSportAttributes(homeTeam: "Lakers", awayTeam: "Warriors", eventID: "e1")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LiveSportAttributes.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
