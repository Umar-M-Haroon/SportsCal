//
//  MacViewSnapshotTests.swift
//  Tests macOS
//
//  Hero macOS snapshots for Figma AI design review.
//  3 views: ContentView main window + MenuBarContentView + MacSettingsView
//

#if canImport(SnapshotTesting) && os(macOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import Scoreline
import SportsCalModel

@MainActor
final class MacViewSnapshotTests: XCTestCase {

    private func wrap<V: View>(_ view: V) -> some View {
        let vm = RealisticFixtures.populatedViewModel()
        return view
            .environment(vm)
            .environment(Fixtures.favorites())
            .environment(Fixtures.storage())
            .environment(Fixtures.engagementTracker())
            .environment(Fixtures.subscriptionManager())
    }

    // MARK: - Main window

    func test_mac_contentView() throws {
        // The day strip renders real calendar dates and the board shows a
        // spinner mid-rotation, so this render is time-relative. Record-only
        // hero (same convention as the iOS DayPage snapshot).
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1",
            "time-relative render; run with TEST_RUNNER_RECORD_SNAPSHOTS=1"
        )
        let view = wrap(ContentView())
        assertMacReviewSnapshots(
            of: view,
            named: "hero-Mac-ContentView",
            size: CGSize(width: 1000, height: 720)
        )
    }

    // MARK: - Menu bar popover

    func test_mac_menuBarContent() {
        let view = wrap(MenuBarContentView())
        assertMacReviewSnapshots(
            of: view,
            named: "hero-Mac-MenuBarContent",
            size: CGSize(width: 380, height: 560)
        )
    }

    // MARK: - Calendar grid popover

    func test_mac_calendarGrid() {
        // Fixed date (2026-02-11 12:00 UTC): a month far enough in the past
        // that neither the real "today" highlight nor the fixture games
        // (anchored near now) can enter the rendered grid window.
        let fixed = Date(timeIntervalSince1970: 1_770_811_200)
        let view = wrap(MacCalendarGridView(selectedDate: .constant(fixed)))
        assertMacReviewSnapshots(
            of: view,
            named: "hero-Mac-CalendarGrid",
            size: CGSize(width: 360, height: 440)
        )
    }

    // MARK: - Settings window

    func test_mac_settings() throws {
        // The date-format rows preview today's date, so this render changes
        // daily. Record-only, like test_mac_contentView.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1",
            "time-relative render; run with TEST_RUNNER_RECORD_SNAPSHOTS=1"
        )
        let view = wrap(MacSettingsView())
        assertMacReviewSnapshots(
            of: view,
            named: "hero-Mac-Settings",
            size: CGSize(width: 640, height: 520)
        )
    }
}
#endif
