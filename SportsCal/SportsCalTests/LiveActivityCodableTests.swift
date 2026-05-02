#if canImport(ActivityKit) && os(iOS)
import XCTest
import ActivityKit
@testable import Scoreline

/// Codability of the client-side ActivityAttributes. If these stop round-tripping
/// cleanly, ActivityKit's push token pipeline silently drops updates — there's
/// no user-visible error, just "my Lock Screen stopped working". Pin it down.
final class LiveActivityCodableTests: XCTestCase {

    func test_attributes_roundTrip() throws {
        let attrs = LiveSportActivityAttributes(homeTeam: "Lakers", awayTeam: "Warriors", eventID: "evt-1")
        let data = try JSONEncoder().encode(attrs)
        let decoded = try JSONDecoder().decode(LiveSportActivityAttributes.self, from: data)
        XCTAssertEqual(decoded.homeTeam, attrs.homeTeam)
        XCTAssertEqual(decoded.awayTeam, attrs.awayTeam)
        XCTAssertEqual(decoded.eventID, attrs.eventID)
    }

    func test_contentState_roundTrip_withAllFields() throws {
        let state = LiveSportActivityAttributes.ContentState(
            homeScore: 21,
            awayScore: 17,
            status: "in",
            progress: "2:14 - 3rd",
            lastPlay: "Durant 3-pointer"
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(LiveSportActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func test_contentState_roundTrip_withNilOptionals() throws {
        let state = LiveSportActivityAttributes.ContentState(
            homeScore: 0,
            awayScore: 0,
            status: nil,
            progress: nil,
            lastPlay: nil
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(LiveSportActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func test_contentState_scoreChange_notEqual() {
        let a = LiveSportActivityAttributes.ContentState(homeScore: 7, awayScore: 3, status: "in", progress: "1Q", lastPlay: nil)
        let b = LiveSportActivityAttributes.ContentState(homeScore: 10, awayScore: 3, status: "in", progress: "1Q", lastPlay: nil)
        XCTAssertNotEqual(a, b)
    }

    func test_contentState_sameFields_isEqual() {
        let a = LiveSportActivityAttributes.ContentState(homeScore: 7, awayScore: 3, status: "in", progress: "1Q", lastPlay: "FG")
        let b = LiveSportActivityAttributes.ContentState(homeScore: 7, awayScore: 3, status: "in", progress: "1Q", lastPlay: "FG")
        XCTAssertEqual(a, b)
    }

    /// Server contract: the server encodes `ContentState` with the same field
    /// names (homeScore/awayScore/status/progress). lastPlay is client-only
    /// today; the server's ContentState struct omits it. Verify that a server
    /// payload *without* lastPlay still decodes cleanly on the client.
    func test_contentState_decodesServerPayload_withoutLastPlay() throws {
        let serverJSON = #"""
        {"homeScore":21,"awayScore":17,"status":"in","progress":"Final"}
        """#
        let decoded = try JSONDecoder().decode(LiveSportActivityAttributes.ContentState.self, from: Data(serverJSON.utf8))
        XCTAssertEqual(decoded.homeScore, 21)
        XCTAssertEqual(decoded.awayScore, 17)
        XCTAssertEqual(decoded.status, "in")
        XCTAssertEqual(decoded.progress, "Final")
        XCTAssertNil(decoded.lastPlay, "Server-originated payloads omit lastPlay; client decoder must accept that")
    }
}
#endif
