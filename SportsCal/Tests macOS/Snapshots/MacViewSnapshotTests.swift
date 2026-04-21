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

    func test_mac_contentView() {
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

    // MARK: - Settings window

    func test_mac_settings() {
        let view = wrap(MacSettingsView())
        assertMacReviewSnapshots(
            of: view,
            named: "hero-Mac-Settings",
            size: CGSize(width: 640, height: 520)
        )
    }
}
#endif
