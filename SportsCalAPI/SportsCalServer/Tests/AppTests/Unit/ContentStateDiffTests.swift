@testable import App
import XCTest

/// Equality on ContentState drives the APNSJob no-push-when-unchanged decision.
/// A regression here (e.g., adding a non-Equatable field) silently produces
/// duplicate pushes or — worse — silently suppresses updates. Tests lock it down.
final class ContentStateDiffTests: XCTestCase {
    func test_equalStates_areEqual() {
        let a = ContentState(homeScore: 14, awayScore: 7, status: "in", progress: "10:00 - 2nd")
        let b = ContentState(homeScore: 14, awayScore: 7, status: "in", progress: "10:00 - 2nd")
        XCTAssertEqual(a, b)
    }

    func test_homeScoreDiff_isNotEqual() {
        let a = ContentState(homeScore: 14, awayScore: 7, status: "in", progress: "10:00 - 2nd")
        let b = ContentState(homeScore: 17, awayScore: 7, status: "in", progress: "10:00 - 2nd")
        XCTAssertNotEqual(a, b)
    }

    func test_awayScoreDiff_isNotEqual() {
        let a = ContentState(homeScore: 14, awayScore: 7, status: "in", progress: "10:00 - 2nd")
        let b = ContentState(homeScore: 14, awayScore: 10, status: "in", progress: "10:00 - 2nd")
        XCTAssertNotEqual(a, b)
    }

    func test_statusDiff_isNotEqual() {
        let a = ContentState(homeScore: 14, awayScore: 7, status: "in", progress: "10:00 - 2nd")
        let b = ContentState(homeScore: 14, awayScore: 7, status: "post", progress: "10:00 - 2nd")
        XCTAssertNotEqual(a, b)
    }

    func test_progressDiff_isNotEqual() {
        let a = ContentState(homeScore: 14, awayScore: 7, status: "in", progress: "10:00 - 2nd")
        let b = ContentState(homeScore: 14, awayScore: 7, status: "in", progress: "9:54 - 2nd")
        XCTAssertNotEqual(a, b)
    }

    func test_nilStatusVsNonNil_isNotEqual() {
        let a = ContentState(homeScore: 0, awayScore: 0, status: nil, progress: nil)
        let b = ContentState(homeScore: 0, awayScore: 0, status: "pre", progress: nil)
        XCTAssertNotEqual(a, b)
    }

    func test_bothNil_areEqual() {
        let a = ContentState(homeScore: 0, awayScore: 0, status: nil, progress: nil)
        let b = ContentState(homeScore: 0, awayScore: 0, status: nil, progress: nil)
        XCTAssertEqual(a, b)
    }

    func test_codableRoundTrip_preservesAllFields() throws {
        let original = ContentState(homeScore: 21, awayScore: 17, status: "in", progress: "2:14 - 3rd")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContentState.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_codableRoundTrip_nilOptionalsPreserved() throws {
        let original = ContentState(homeScore: 0, awayScore: 0, status: nil, progress: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContentState.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
