//
//  BoardSnapshotTests.swift
//  SportsCalTests
//
//  Snapshot tests for the multi-sport board layout.
//  NOTE: SportColumnView / GameBoardLayout are generic structs with
//  @ViewBuilder stored properties, which complicates memberwise init from
//  outside the module. Skipped for now — covered indirectly through
//  ContentView in ScreenSnapshotTests.
//

#if canImport(SnapshotTesting) && os(iOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import Scoreline
import SportsCalModel

@MainActor
final class BoardSnapshotTests: XCTestCase {
    // Intentionally empty — board layout snapshots deferred.
    // See note above.
    func test_placeholder() {
        XCTAssertTrue(true)
    }
}
#endif
