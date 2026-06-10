import XCTest
@testable import Scoreline

/// Pins the WebSocket reconnect orchestration in GameViewModel: the
/// offline-deferral guard, attempt counting + backoff timer scheduling, and
/// the reset-on-path-restore behavior. The pure backoff curve itself is
/// covered by WebSocketBackoffTests.
@MainActor
final class WebSocketReconnectTests: XCTestCase {

    private var vm: GameViewModel!

    override func setUp() async throws {
        GameViewModel.isSnapshotTesting = true
        vm = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())
    }

    override func tearDown() async throws {
        // A fired reconnect timer would try to open a real socket — never let
        // one outlive a test.
        vm.restartTimer?.invalidate()
        vm.restartTimer = nil
        vm = nil
    }

    func testReconnectDeferredWhileOffline() {
        vm.hasNetworkPath = false

        vm.reconnectWebSocketOnly()

        XCTAssertEqual(vm.wsReconnectAttempts, 0,
                       "offline reconnects must not burn backoff attempts")
        XCTAssertNil(vm.restartTimer,
                     "no timer while offline — the path monitor forces reconnect on restore")
    }

    func testConsecutiveReconnectsFollowBackoffCurve() throws {
        vm.hasNetworkPath = true

        for attempt in 1...3 {
            vm.reconnectWebSocketOnly()
            XCTAssertEqual(vm.wsReconnectAttempts, attempt)
            let timer = try XCTUnwrap(vm.restartTimer)
            let expectedDelay = WebSocketBackoff.delaySeconds(forAttempt: attempt)
            // Non-repeating timers report timeInterval 0 — measure via fireDate.
            XCTAssertEqual(timer.fireDate.timeIntervalSinceNow, expectedDelay, accuracy: 1.0)
        }
    }

    func testPathLossSetsOfflineState() {
        vm.handlePathUpdate(satisfied: false)

        XCTAssertTrue(vm.isOffline)
        XCTAssertFalse(vm.hasNetworkPath)
        XCTAssertNil(vm.restartTimer)
    }

    func testPathRestoreResetsBackoffAndPendingTimer() {
        vm.hasNetworkPath = true
        vm.reconnectWebSocketOnly()
        vm.reconnectWebSocketOnly()
        XCTAssertEqual(vm.wsReconnectAttempts, 2)
        XCTAssertNotNil(vm.restartTimer)

        vm.handlePathUpdate(satisfied: false)
        vm.handlePathUpdate(satisfied: true)

        XCTAssertFalse(vm.isOffline)
        XCTAssertTrue(vm.hasNetworkPath)
        XCTAssertEqual(vm.wsReconnectAttempts, 0,
                       "restore resets the backoff so reconnect is immediate")
        XCTAssertNil(vm.restartTimer)
    }

    func testPathRestoreWithoutPriorLossDoesNotReset() {
        vm.hasNetworkPath = true
        vm.reconnectWebSocketOnly()
        XCTAssertEqual(vm.wsReconnectAttempts, 1)

        // Path callback fires with satisfied=true while already online —
        // must not clobber an in-progress backoff.
        vm.handlePathUpdate(satisfied: true)

        XCTAssertEqual(vm.wsReconnectAttempts, 1)
        XCTAssertNotNil(vm.restartTimer)
    }
}
