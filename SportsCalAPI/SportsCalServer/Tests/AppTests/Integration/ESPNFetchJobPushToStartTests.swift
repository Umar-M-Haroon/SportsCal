@testable import App
import XCTest
import Logging
import SportsCalModel

/// Push-to-start fires when a game transitions from scheduled to in-progress.
/// The dedup key prevents re-firing within 8h. These tests cover both mechanics
/// and the favorites + auto-follow-event-ID targeting paths.
///
/// Storage is install-keyed: `PushToStartByInstall-{installID}` holds the
/// token + favorites + eventIDs together so an APNS token rotation can't leave
/// an orphan registration shadowing the new token.
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

    /// Writes an install record under the production keyspace.
    @discardableResult
    private func seedInstall(
        installID: String,
        token: String,
        favorites: [String] = [],
        eventIDs: [String] = [],
        environment: APNSEnvironment = .production
    ) async throws -> PushToStartInstall {
        let install = PushToStartInstall(
            installID: installID,
            token: token,
            favorites: favorites,
            eventIDs: eventIDs,
            environment: environment
        )
        let prefix = environment == .sandbox ? "debug-PushToStartByInstall-" : "PushToStartByInstall-"
        try await kv.setJSON(prefix + installID, value: install, ttl: nil)
        let indexPrefix = environment == .sandbox ? "debug-PushToStartTokenIndex-" : "PushToStartTokenIndex-"
        try await kv.setString(indexPrefix + token, value: installID, ttl: nil)
        return install
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
        try await seedInstall(installID: "i1", token: "t1", favorites: ["Lakers"])
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.kind, .start)
        XCTAssertEqual(apns.recorded.first?.deviceToken, "t1")
        XCTAssertEqual(apns.recorded.first?.attributes?.eventID, "e1")
    }

    func test_sendsPushToStart_whenAwayTeamIsFavorite() async throws {
        try await seedInstall(installID: "i1", token: "t1", favorites: ["Warriors"])
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        XCTAssertEqual(apns.recorded.count, 1)
    }

    func test_doesNotSend_whenNoTeamMatchesFavorites() async throws {
        try await seedInstall(installID: "i1", token: "t1", favorites: ["Knicks", "Bulls"])
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        XCTAssertTrue(apns.recorded.isEmpty)
    }

    // MARK: - Auto-follow event-ID targeting

    func test_sendsPushToStart_viaAutoFollowEventID() async throws {
        try await seedInstall(installID: "i1", token: "t1", eventIDs: ["e1", "e2"])
        let game = TestGameFactory.make(idEvent: "e2", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.attributes?.eventID, "e2")
    }

    func test_bothFavoritesAndEventIDForSameGame_sendsOnce() async throws {
        // If a user has the team favorited AND the event auto-followed, the
        // per-install matchedEventIDs set must coalesce — exactly one push.
        try await seedInstall(installID: "i1", token: "t1", favorites: ["Lakers"], eventIDs: ["e1"])
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        XCTAssertEqual(apns.recorded.count, 1, "Per-install dedup should coalesce favorites + eventID into one push")
    }

    // MARK: - Atomic dedup (SETNX)

    func test_rerunningOnSameGame_doesNotReSend_whenClaimExists() async throws {
        try await seedInstall(installID: "i1", token: "t1", favorites: ["Lakers"])
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])
        await runPhase(newlyStarted: [game])
        await runPhase(newlyStarted: [game])

        XCTAssertEqual(apns.recorded.count, 1, "Claim should prevent re-sends within the TTL window")
    }

    func test_dedupKeyExpires_reEnablesNextSend() async throws {
        try await seedInstall(installID: "i1", token: "t1", favorites: ["Lakers"])
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])
        XCTAssertEqual(apns.recorded.count, 1)

        // Fast-forward past the 8h claim window
        clock.advance(by: 60 * 60 * 9)
        apns.reset()

        await runPhase(newlyStarted: [game])

        XCTAssertEqual(apns.recorded.count, 1, "After claim TTL expires, push should fire again")
    }

    func test_concurrentInstances_onlyOneSends() async throws {
        // Two server replicas processing the same fetch cycle: atomic SETNX
        // guarantees exactly one wins. This is the multi-instance dedup story
        // — the bug we're fixing was the same game showing up as two activities
        // because both replicas independently issued APNS start pushes.
        try await seedInstall(installID: "i1", token: "t1", favorites: ["Lakers"])
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        async let a: () = runPhase(newlyStarted: [game])
        async let b: () = runPhase(newlyStarted: [game])
        _ = await (a, b)

        XCTAssertEqual(apns.recorded.count, 1, "Atomic SETNX must allow exactly one of two concurrent runs to send")
    }

    // MARK: - Stale-token cleanup on send failure

    func test_unregisteredResponse_clearsInstallAndTokenIndex() async throws {
        let install = try await seedInstall(installID: "i1", token: "t1", favorites: ["Lakers"], eventIDs: ["e1"])
        apns.queueError(APNSSendError(reason: .unregistered, underlying: nil), for: install.token)
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        let snapshot = kv.rawSnapshot
        XCTAssertNil(snapshot["PushToStartByInstall-i1"], "Install record should be deleted on stale-token")
        XCTAssertNil(snapshot["PushToStartTokenIndex-t1"], "Reverse index should be deleted on stale-token")
    }

    // MARK: - Multi-environment dispatch

    /// A single server serves both Xcode dev devices (sandbox installs stored
    /// under `debug-PushToStartByInstall-`) and TestFlight / App Store users
    /// (production installs under `PushToStartByInstall-`). The job must scan
    /// both keyspaces and dispatch each token through the matching APNS gateway.
    func test_dispatchesBothEnvironments_perTokenGateway() async throws {
        try await seedInstall(installID: "prod-install", token: "prodToken", favorites: ["Lakers"], environment: .production)
        try await seedInstall(installID: "sandbox-install", token: "sandboxToken", favorites: ["Lakers"], environment: .sandbox)
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Lakers", strAwayTeam: "Warriors", strStatus: "in")

        await runPhase(newlyStarted: [game])

        XCTAssertEqual(apns.recorded.count, 2)
        let byToken = Dictionary(uniqueKeysWithValues: apns.recorded.map { ($0.deviceToken, $0.environment) })
        XCTAssertEqual(byToken["prodToken"], .production)
        XCTAssertEqual(byToken["sandboxToken"], .sandbox)
    }
}
