import XCTest
@testable import Scoreline

/// Pins the WebSocket reconnect backoff curve. A regression here would either
/// hammer the server (too-short delays) or leave live scores silent for too
/// long (too-long delays) after a dropped connection.
final class WebSocketBackoffTests: XCTestCase {
    func test_sequence_isQuadratic() {
        XCTAssertEqual(WebSocketBackoff.delaySeconds(forAttempt: 1), 2)
        XCTAssertEqual(WebSocketBackoff.delaySeconds(forAttempt: 2), 8)
        XCTAssertEqual(WebSocketBackoff.delaySeconds(forAttempt: 3), 18)
        XCTAssertEqual(WebSocketBackoff.delaySeconds(forAttempt: 4), 32)
        XCTAssertEqual(WebSocketBackoff.delaySeconds(forAttempt: 5), 50)
    }

    func test_capsAtSixtySeconds() {
        XCTAssertEqual(WebSocketBackoff.delaySeconds(forAttempt: 6), 60)
        XCTAssertEqual(WebSocketBackoff.delaySeconds(forAttempt: 7), 60)
        XCTAssertEqual(WebSocketBackoff.delaySeconds(forAttempt: 100), 60)
    }

    func test_attemptZero_isZero() {
        XCTAssertEqual(WebSocketBackoff.delaySeconds(forAttempt: 0), 0)
    }
}
