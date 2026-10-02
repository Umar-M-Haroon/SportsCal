import XCTest
@testable import SportsCalModel

/// ESPN dates F1 sessions to the minute ("2026-10-04T07:00Z"). `ISO8601DateFormatter`
/// rejects that, which silently nil'd every session date and made a race weekend fall
/// back to its Friday practice date — "past" from Saturday on.
final class EventSessionDateTests: XCTestCase {
    func testStartDate_parsesMinutePrecisionESPNDates() throws {
        let session = EventSession(sessionType: "Race", sessionName: "Race", date: "2026-10-04T07:00Z")
        let date = try XCTUnwrap(session.startDate)
        XCTAssertEqual(date, ISO8601DateFormatter().date(from: "2026-10-04T07:00:00Z"))
    }

    func testStartDate_parsesFullISODates() {
        let session = EventSession(sessionType: "FP1", sessionName: "Free Practice 1", date: "2026-10-02T04:30:00Z")
        XCTAssertNotNil(session.startDate)
    }

    func testStartDate_nilWithoutDate() {
        XCTAssertNil(EventSession(sessionType: "Race", sessionName: "Race").startDate)
    }
}
