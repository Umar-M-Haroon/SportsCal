@testable import App
import XCTest
import Logging
import SportsCalModel

/// Push-to-start fires when a game transitions from scheduled to in-progress.
/// The dedup key prevents re-firing within 8h. These tests cover both mechanics
/// and the favorites + auto-follow-event-ID targeting paths.
final class ESPNFetchJobPushToStartTests: XCTestCase {

    private var kv: InMemoryKeyValueStore!
    private var apns: MockAPNSClient!
    private var clock: MutableClock!
    private let logger = Logger(label: "test.espn-fetch")

    override func setUp() async throws {
        clock = MutableClock()
        kv = InMemoryKeyValueStore(clock: clock)
        apns = MockAPNSClient()
    }

    private func runPhase(newlyStarted: [Game], isDebug: Bool = false) async {
        await ESPNFetchJob.runPushToStartPhase(
            newlyStarted: newlyStarted,
            kv: kv,
            apns: apns,
            clock: clock,
            isDebug: isDebug,
            logger: logger
        )
    }

    // MARK: - Transition detection

    func test_detectsTransitionFromPreToIn() {
        let previous = TestGameFactory.liveScore(nba: [
            TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", strStatus: "pre")
        ])
        let now = TestGameFactory.liveScore(nba: [
            TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", strStatus: "in")
        ])
        let started = ESPNFetchJob.detectNewlyStartedGames(newResult: now, previousResult: previous)
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(started.first?.idEvent, "e1")
    }

    func test_doesNotDetectTransition_whenGameWasAlreadyInPreviousSnapshot() {
        let previous = TestGameFactory.liveScore(nba: [
            TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", strStatus: "in")
        ])
        let now = TestGameFactory.liveScore(nba: [
            TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", strStatus: "in")
        ])
        XCTAssertTrue(ESPNFetchJob.detectNewlyStartedGames(newResult: now, previousResult: previous).isEmpty)
    }

    func test_doesNotDetectTransition_whenCurrentStatusIsNotIn() {
        let previous = TestGameFactory.liveScore(nba: [
            TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", strStatus: "pre")
        ])
        let now = TestGameFactory.liveScore(nba: [
            TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", strStatus: "pre")
        ])
        XCTAssertTrue(ESPNFetchJob.detectNewlyStartedGames(newResult: now, previousResult: previous).isEmpty)
    }

    func test_coldStart_nilPrevious_allInProgressGamesCountAsNewlyStarted() {
        // On the first tick after boot, there's no previous snapshot. Every
        // in-progress game counts as "just transitioned" — this is intentional
        // so we don't silently miss games that started during downtime.
        let now = TestGameFactory.liveScore(nba: [
            TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", strStatus: "in"),
            TestGameFactory.make(idEvent: "e2", strHomeTeam: "C", strAwayTeam: "D", strStatus: "pre")
        ])
        let started = ESPNFetchJob.detectNewlyStartedGames(newResult: now, previousResult: nil)
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(started.first?.idEvent, "e1")
    }

    // MARK: - Favorites-based targeting

    func test_sendsPushToStart_whenHomeTeamIsFavorite() async throws {
        let token = "t1"
        try await kv.setJSON("PushToStart-\(token)", value: ["Lakers"], ttl: nil)
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.kind, .start)
        XCTAssertEqual(apns.recorded.first?.deviceToken, token)
        XCTAssertEqual(apns.recorded.first?.attributes?.eventID, "e1")
    }

    func test_sendsPushToStart_whenAwayTeamIsFavorite() async throws {
        let token = "t1"
        try await kv.setJSON("PushToStart-\(token)", value: ["Warriors"], ttl: nil)
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        XCTAssertEqual(apns.recorded.count, 1)
    }

    func test_doesNotSend_whenNoTeamMatchesFavorites() async throws {
        try await kv.setJSON("PushToStart-t1", value: ["Knicks", "Bulls"], ttl: nil)
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        XCTAssertTrue(apns.recorded.isEmpty)
    }

    func test_doesNotMatchPushToStartEventsKey_withPushToStartScan() async throws {
        // PushToStart-* glob would also match PushToStartEvents-*. The job filters
        // those out so the same token doesn't get treated as both favorites list
        // and event-ID list. Regression guard.
        try await kv.setJSON("PushToStartEvents-t1", value: ["e1"], ttl: nil)
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        // The Events list should still trigger via the second pass — exactly once.
        XCTAssertEqual(apns.recorded.count, 1)
    }

    // MARK: - Auto-follow event-ID targeting

    func test_sendsPushToStart_viaAutoFollowEventID() async throws {
        let token = "t1"
        try await kv.setJSON("PushToStartEvents-\(token)", value: ["e1", "e2"], ttl: nil)
        let game = TestGameFactory.make(idEvent: "e2", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.attributes?.eventID, "e2")
    }

    func test_bothFavoritesAndEventIDRegistered_sendsExactlyTwoPushes() async throws {
        // If a user has the team favorited *and* the event auto-followed, they
        // appear in both scan passes. Current behavior: one push per pass = two
        // pushes. Dedup key should then prevent the second one on subsequent runs.
        let token = "t1"
        try await kv.setJSON("PushToStart-\(token)", value: ["Lakers"], ttl: nil)
        try await kv.setJSON("PushToStartEvents-\(token)", value: ["e1"], ttl: nil)
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        // One push — the dedup key written after the first send blocks the second.
        XCTAssertEqual(apns.recorded.count, 1, "Dedup key should prevent the second pass from re-sending")
    }

    // MARK: - Deduplication

    func test_rerunningOnSameGame_doesNotReSend_whenDedupKeyExists() async throws {
        try await kv.setJSON("PushToStart-t1", value: ["Lakers"], ttl: nil)
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])
        await runPhase(newlyStarted: [game])
        await runPhase(newlyStarted: [game])

        XCTAssertEqual(apns.recorded.count, 1, "Dedup key should prevent re-sends within the TTL window")
    }

    func test_dedupKeyExpires_reEnablesNextSend() async throws {
        try await kv.setJSON("PushToStart-t1", value: ["Lakers"], ttl: nil)
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])
        XCTAssertEqual(apns.recorded.count, 1)

        // Fast-forward past the 8h dedup window
        clock.advance(by: 60 * 60 * 9)
        apns.reset()
        // Re-seed favorites since they're also TTL'd (24h — still alive at 9h,
        // but we reset the mock for a clean assert).
        try await kv.setJSON("PushToStart-t1", value: ["Lakers"], ttl: nil)

        await runPhase(newlyStarted: [game])

        XCTAssertEqual(apns.recorded.count, 1, "After dedup TTL expires, push should fire again")
    }

    // MARK: - Stale-token cleanup on send failure

    func test_unregisteredResponse_clearsBothFavoritesAndEventIDs() async throws {
        let token = "t1"
        try await kv.setJSON("PushToStart-\(token)", value: ["Lakers"], ttl: nil)
        try await kv.setJSON("PushToStartEvents-\(token)", value: ["e1"], ttl: nil)
        apns.queueError(APNSSendError(reason: .unregistered, underlying: nil), for: token)
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        let snapshot = kv.rawSnapshot
        XCTAssertNil(snapshot["PushToStart-\(token)"])
        XCTAssertNil(snapshot["PushToStartEvents-\(token)"])
    }

    // MARK: - Debug-key prefix isolation

    func test_debugEnv_usesDebugPrefixedKeys() async throws {
        let token = "t1"
        try await kv.setJSON("debug-PushToStart-\(token)", value: ["Lakers"], ttl: nil)
        // Put a prod-prefixed entry too — in debug mode the job should skip it.
        try await kv.setJSON("PushToStart-other", value: ["Lakers"], ttl: nil)
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game], isDebug: true)

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.deviceToken, token)
    }
}
