//
//  MacWidgetDataStoreTests.swift
//  Tests macOS
//
//  Hosted in the sandboxed mac app, so this exercises the exact path the
//  macOS widget depends on: writing/reading the shared snapshot through the
//  App Group container under the App Sandbox. If the group entitlement or
//  container access is broken on macOS, this fails before a user ever adds
//  the widget.
//

import XCTest
import SportsCalModel
@testable import Scoreline

@MainActor
final class MacWidgetDataStoreTests: XCTestCase {

    func testAppGroupContainerIsReachable() throws {
        let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal"
        )
        XCTAssertNotNil(url, "App Group container unavailable — widget data path is dead on macOS")
    }

    func testWidgetSnapshotRoundTrip() throws {
        // Unsigned runs (CODE_SIGNING_ALLOWED=NO from the CLI) carry no App
        // Group entitlement, so the container path isn't the real one. The
        // signed run — Xcode GUI or CI — is where this test has meaning.
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil,
            "host app is not sandboxed (unsigned run) — App Group round-trip needs a signed build"
        )
        let games = RealisticFixtures.populatedViewModel().totalGames ?? []
        WidgetDataStore.writeSnapshot(games: games, teams: [])
        let snapshot = WidgetDataStore.readSnapshot()
        XCTAssertNotNil(snapshot, "Snapshot written by the app could not be read back")
    }
}
