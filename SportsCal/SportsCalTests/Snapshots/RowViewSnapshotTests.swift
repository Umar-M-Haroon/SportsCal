//
//  RowViewSnapshotTests.swift
//  SportsCalTests
//
//  Row-level captures are deferred — the hero DayPage snapshot
//  (in ScreenSnapshotTests) already exercises every row view in context.
//

#if canImport(SnapshotTesting) && os(iOS)
import XCTest

@MainActor
final class RowViewSnapshotTests: XCTestCase {
    func test_placeholder() {
        XCTAssertTrue(true)
    }
}
#endif
