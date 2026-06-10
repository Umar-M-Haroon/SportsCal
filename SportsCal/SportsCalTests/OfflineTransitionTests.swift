import XCTest
@testable import Scoreline

/// Pins the offline→online state surface (C3): the stale-data banner and
/// full-screen offline placeholder conditions that ContentView renders, and
/// that going offline/online never opens a socket from a test process.
@MainActor
final class OfflineTransitionTests: XCTestCase {

    override func setUp() async throws {
        GameViewModel.isSnapshotTesting = true
    }

    private func emptyViewModel() -> GameViewModel {
        GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())
    }

    func testStaleBannerShownWhenOfflineWithCachedGames() {
        let vm = RealisticFixtures.populatedViewModel()
        vm.isOffline = true

        XCTAssertTrue(vm.showsStaleBanner)
        XCTAssertFalse(vm.showsOfflinePlaceholder)
    }

    func testOfflinePlaceholderShownWhenOfflineWithNoGames() {
        let vm = emptyViewModel()
        vm.isOffline = true

        XCTAssertFalse(vm.showsStaleBanner)
        XCTAssertTrue(vm.showsOfflinePlaceholder)
    }

    func testStaleBannerShownOnFetchFailureEvenWhenOnline() {
        let vm = RealisticFixtures.populatedViewModel()
        vm.isOffline = false
        vm.networkState = .failed

        XCTAssertTrue(vm.showsStaleBanner)
        XCTAssertFalse(vm.showsOfflinePlaceholder)
    }

    func testNoBannerWhenOnlineAndLoaded() {
        let vm = RealisticFixtures.populatedViewModel()
        vm.isOffline = false
        vm.networkState = .loaded

        XCTAssertFalse(vm.showsStaleBanner)
        XCTAssertFalse(vm.showsOfflinePlaceholder)
    }

    func testOfflineToOnlineTransitionClearsBanner() {
        let vm = RealisticFixtures.populatedViewModel()
        vm.handlePathUpdate(satisfied: false)
        XCTAssertTrue(vm.isOffline)
        XCTAssertTrue(vm.showsStaleBanner)

        vm.handlePathUpdate(satisfied: true)
        XCTAssertFalse(vm.isOffline)
        XCTAssertFalse(vm.showsStaleBanner, "fixture VM is .loaded, so restore clears the banner")
        vm.restartTimer?.invalidate()
        vm.restartTimer = nil
    }

    func testEnsureWebSocketConnectedNeverOpensSocketWithoutSession() {
        // The fixture has live events, so shouldWebSocketBeActive() is true —
        // but a test-built VM has no webSocketSession and must not fall back
        // to a real connection.
        let vm = RealisticFixtures.populatedViewModel()
        vm.ensureWebSocketConnected()

        XCTAssertNil(vm.webSocketTask)
        vm.restartTimer?.invalidate()
        vm.restartTimer = nil
    }
}
