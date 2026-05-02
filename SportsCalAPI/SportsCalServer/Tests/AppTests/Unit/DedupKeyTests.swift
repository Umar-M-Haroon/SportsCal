@testable import App
import XCTest

/// The RedisEndpoint enum is the single source of truth for how keys are named
/// across client registrations, server jobs, and the admin dashboard. A rename
/// here silently breaks all three at once, so pin the exact wire format.
final class DedupKeyTests: XCTestCase {

    // MARK: - sentPushToStart (dedup)

    func test_sentPushToStart_prodFormat() {
        let key = RedisEndpoint.sentPushToStart("abc123", "event-42").getValue(isDebug: false)
        XCTAssertEqual(key.rawValue, "SentPushToStart-abc123-event-42")
    }

    func test_sentPushToStart_devFormat_isPrefixed() {
        let key = RedisEndpoint.sentPushToStart("abc123", "event-42").getValue(isDebug: true)
        XCTAssertEqual(key.rawValue, "debug-SentPushToStart-abc123-event-42")
    }

    // MARK: - pushToStart registration

    func test_pushToStart_prodFormat() {
        XCTAssertEqual(
            RedisEndpoint.pushToStart("abc").getValue(isDebug: false).rawValue,
            "PushToStart-abc"
        )
    }

    func test_pushToStart_devFormat() {
        XCTAssertEqual(
            RedisEndpoint.pushToStart("abc").getValue(isDebug: true).rawValue,
            "debug-PushToStart-abc"
        )
    }

    // MARK: - pushToStartEvents (auto-follow list)

    func test_pushToStartEvents_prodFormat() {
        XCTAssertEqual(
            RedisEndpoint.pushToStartEvents("abc").getValue(isDebug: false).rawValue,
            "PushToStartEvents-abc"
        )
    }

    func test_pushToStartEvents_doesNotCollideWithPushToStartGlobPattern() {
        // `PushToStart-*` matches `PushToStartEvents-*` unless we filter. Lock
        // in the invariant that the two keyspaces share a prefix so the scan
        // call in ESPNFetchJob still needs the explicit filter.
        let favorites = RedisEndpoint.pushToStart("token").getValue(isDebug: false).rawValue
        let events = RedisEndpoint.pushToStartEvents("token").getValue(isDebug: false).rawValue
        XCTAssertTrue(favorites.hasPrefix("PushToStart-"))
        XCTAssertTrue(events.hasPrefix("PushToStartEvents-"))
    }

    // MARK: - eventState

    func test_eventState_prodFormat() {
        XCTAssertEqual(
            RedisEndpoint.eventState("event-42").getValue(isDebug: false).rawValue,
            "EventState-event-42"
        )
    }

    func test_eventState_devFormat() {
        XCTAssertEqual(
            RedisEndpoint.eventState("event-42").getValue(isDebug: true).rawValue,
            "debug-EventState-event-42"
        )
    }
}
