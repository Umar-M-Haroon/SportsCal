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

    // MARK: - pushToStartByInstall (install-keyed registration)

    func test_pushToStartByInstall_prodFormat() {
        XCTAssertEqual(
            RedisEndpoint.pushToStartByInstall("install-uuid").getValue(isDebug: false).rawValue,
            "PushToStartByInstall-install-uuid"
        )
    }

    func test_pushToStartByInstall_devFormat() {
        XCTAssertEqual(
            RedisEndpoint.pushToStartByInstall("install-uuid").getValue(isDebug: true).rawValue,
            "debug-PushToStartByInstall-install-uuid"
        )
    }

    func test_pushToStartTokenIndex_prodFormat() {
        XCTAssertEqual(
            RedisEndpoint.pushToStartTokenIndex("token").getValue(isDebug: false).rawValue,
            "PushToStartTokenIndex-token"
        )
    }

    // MARK: - eventStateClaim (atomic update dedup)

    func test_eventStateClaim_prodFormat() {
        XCTAssertEqual(
            RedisEndpoint.eventStateClaim("event-42", "abc123").getValue(isDebug: false).rawValue,
            "EventStateClaim-event-42-abc123"
        )
    }

    // MARK: - jobLock

    func test_jobLock_prodFormat() {
        XCTAssertEqual(
            RedisEndpoint.jobLock("espn-fetch").getValue(isDebug: false).rawValue,
            "JobLock-espn-fetch"
        )
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
