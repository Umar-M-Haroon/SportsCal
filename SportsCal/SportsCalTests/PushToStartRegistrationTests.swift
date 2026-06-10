import XCTest
@testable import Scoreline

/// Pins the client half of the push-to-start handshake: the registration
/// decision (PushToStartRegistrationPlanner) and the wire format of the
/// registration request that the server's `PushToStartRegistration` decoder
/// and install-keyed dedup depend on. The server half is pinned by
/// RegistrationCodableTests + RoutesTests in the Vapor package.
final class PushToStartRegistrationTests: XCTestCase {

    // MARK: - Planner

    func testNilWhenNothingToRegister() {
        XCTAssertNil(PushToStartRegistrationPlanner.payload(
            autoFollowFavorites: true, favoriteTeams: [], autoFollowEventIDs: []))
        XCTAssertNil(PushToStartRegistrationPlanner.payload(
            autoFollowFavorites: false, favoriteTeams: ["Lakers"], autoFollowEventIDs: []))
    }

    func testFavoritesSuppressedWhenToggleOff_eventIDsStillRegister() {
        let payload = PushToStartRegistrationPlanner.payload(
            autoFollowFavorites: false,
            favoriteTeams: ["Lakers"],
            autoFollowEventIDs: ["evt1"]
        )
        XCTAssertEqual(payload, PushToStartPayload(favorites: [], eventIDs: ["evt1"]))
    }

    func testFavoritesAndEventsBothIncluded() {
        let payload = PushToStartRegistrationPlanner.payload(
            autoFollowFavorites: true,
            favoriteTeams: ["Lakers", "Celtics"],
            autoFollowEventIDs: ["evt2", "evt1"]
        )
        XCTAssertEqual(payload, PushToStartPayload(
            favorites: ["Celtics", "Lakers"],
            eventIDs: ["evt1", "evt2"]
        ))
    }

    func testFavoritesOnly() {
        let payload = PushToStartRegistrationPlanner.payload(
            autoFollowFavorites: true,
            favoriteTeams: ["Lakers"],
            autoFollowEventIDs: []
        )
        XCTAssertEqual(payload, PushToStartPayload(favorites: ["Lakers"], eventIDs: []))
    }

    // MARK: - Request wire format

    private func bodyJSON(of request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testRegistrationRequestShape() throws {
        let request = try NetworkHandler.pushToStartRegistrationRequest(
            token: "tok-A", favorites: ["Lakers"], eventIDs: ["evt1"])

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(request.url!.path.hasSuffix("/pushToStart/register"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-API-Key"))

        // Test bundles build DEBUG → development entitlement → sandbox tokens.
        // The server routes to the matching APNS gateway off this header.
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-APNS-Env"), "sandbox")

        let body = try bodyJSON(of: request)
        XCTAssertEqual(body["token"] as? String, "tok-A")
        XCTAssertEqual(body["favorites"] as? [String], ["Lakers"])
        XCTAssertEqual(body["eventIDs"] as? [String], ["evt1"])
    }

    func testEventIDsKeyAbsentWhenEmpty() throws {
        // The server decodes `eventIDs` as optional; an empty array and an
        // absent key are both valid, but absence is the pinned legacy shape.
        let request = try NetworkHandler.pushToStartRegistrationRequest(
            token: "tok-A", favorites: ["Lakers"], eventIDs: [])

        let body = try bodyJSON(of: request)
        XCTAssertNil(body["eventIDs"])
        XCTAssertEqual(body["favorites"] as? [String], ["Lakers"])
    }

    func testInstallIDHeaderIsStableAcrossRequests() throws {
        // The server keys all push-to-start state by install ID; a value that
        // changed between requests would orphan registrations (C7).
        let first = try NetworkHandler.pushToStartRegistrationRequest(
            token: "tok-A", favorites: ["Lakers"], eventIDs: [])
        let second = try NetworkHandler.pushToStartRegistrationRequest(
            token: "tok-B", favorites: ["Lakers"], eventIDs: [])

        let firstID = try XCTUnwrap(first.value(forHTTPHeaderField: "X-Install-ID"))
        let secondID = try XCTUnwrap(second.value(forHTTPHeaderField: "X-Install-ID"))
        XCTAssertFalse(firstID.isEmpty)
        XCTAssertEqual(firstID, secondID)
    }
}
