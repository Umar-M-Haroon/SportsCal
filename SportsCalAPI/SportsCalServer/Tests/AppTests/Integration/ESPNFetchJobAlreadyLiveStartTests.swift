@testable import App
import XCTest
import Logging
import SportsCalModel

/// `sendStartsForAlreadyLiveGames` closes the transition-only gap: push-to-start
/// normally fires only when a game flips scheduled → in-progress, so a user who
/// follows a match (or taps "Follow World Cup") while it is ALREADY live would
/// get nothing until the next kickoff. The register route calls this inline so
/// those followers get a Live Activity immediately.
///
/// The shared `SentPushToStart-{token}-{eventID}` claim must dedupe this against
/// the scheduled transition path so a follower never gets two activities.
final class ESPNFetchJobAlreadyLiveStartTests: XCTestCase {

    private var kv: InMemoryKeyValueStore!
    private var apns: MockAPNSClient!
    private var clock: MutableClock!
    private let logger = Logger(label: "test.already-live")

    override func setUp() async throws {
        clock = MutableClock()
        kv = InMemoryKeyValueStore(clock: clock)
        apns = MockAPNSClient()
    }

    private func install(
        installID: String = "i1",
        token: String = "t1",
        favorites: [String] = [],
        eventIDs: [String] = [],
        environment: APNSEnvironment = .production
    ) -> PushToStartInstall {
        PushToStartInstall(
            installID: installID,
            token: token,
            favorites: favorites,
            eventIDs: eventIDs,
            environment: environment
        )
    }

    private func sendAlreadyLive(
        install: PushToStartInstall,
        liveGames: [Game],
        environment: APNSEnvironment = .production,
        isDebug: Bool = false
    ) async {
        await ESPNFetchJob.sendStartsForAlreadyLiveGames(
            install: install,
            liveGames: liveGames,
            environment: environment,
            kv: kv,
            apns: apns,
            clock: clock,
            isDebug: isDebug,
            logger: logger
        )
    }

    /// Seeds an install into the production keyspace so the scheduled transition
    /// path (`runPushToStartPhase`) can read it — used by the dedup test.
    private func seedInstall(_ install: PushToStartInstall) async throws {
        let prefix = install.environment == .sandbox ? "debug-PushToStartByInstall-" : "PushToStartByInstall-"
        try await kv.setJSON(prefix + install.installID, value: install, ttl: nil)
        let indexPrefix = install.environment == .sandbox ? "debug-PushToStartTokenIndex-" : "PushToStartTokenIndex-"
        try await kv.setString(indexPrefix + install.token, value: install.installID, ttl: nil)
    }

    // MARK: - Targeting

    func test_sendsStart_forAlreadyLiveGame_matchingEventID() async throws {
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Mexico", strAwayTeam: "Croatia", strStatus: "in")

        await sendAlreadyLive(install: install(eventIDs: ["e1", "e2"]), liveGames: [game])

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.kind, .start)
        XCTAssertEqual(apns.recorded.first?.deviceToken, "t1")
        XCTAssertEqual(apns.recorded.first?.attributes?.eventID, "e1")
    }

    func test_sendsStart_forAlreadyLiveGame_matchingFavorite() async throws {
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Mexico", strAwayTeam: "Croatia", strStatus: "in")

        await sendAlreadyLive(install: install(favorites: ["Croatia"]), liveGames: [game])

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.attributes?.eventID, "e1")
    }

    // MARK: - Live-only filter

    func test_doesNotSend_forScheduledGame_evenIfFollowed() async throws {
        // A followed match that hasn't kicked off yet must NOT get a start —
        // that's the scheduled transition path's job once it goes live.
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Mexico", strAwayTeam: "Croatia", strStatus: "pre")

        await sendAlreadyLive(install: install(eventIDs: ["e1"]), liveGames: [game])

        XCTAssertTrue(apns.recorded.isEmpty, "Scheduled (pre) games are not started by the already-live path")
    }

    func test_doesNotSend_forFinishedGame_evenIfFollowed() async throws {
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Mexico", strAwayTeam: "Croatia", strStatus: "post")

        await sendAlreadyLive(install: install(eventIDs: ["e1"]), liveGames: [game])

        XCTAssertTrue(apns.recorded.isEmpty, "Finished games are not started by the already-live path")
    }

    func test_doesNotSend_whenNoMatch() async throws {
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Mexico", strAwayTeam: "Croatia", strStatus: "in")

        await sendAlreadyLive(install: install(favorites: ["Brazil"], eventIDs: ["other"]), liveGames: [game])

        XCTAssertTrue(apns.recorded.isEmpty)
    }

    func test_doesNotSend_whenInstallHasNoFollows() async throws {
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Mexico", strAwayTeam: "Croatia", strStatus: "in")

        await sendAlreadyLive(install: install(), liveGames: [game])

        XCTAssertTrue(apns.recorded.isEmpty, "No favorites and no event IDs → nothing to start")
    }

    // MARK: - Per-install dedup

    func test_favoriteAndEventIDForSameGame_sendsOnce() async throws {
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Mexico", strAwayTeam: "Croatia", strStatus: "in")

        await sendAlreadyLive(install: install(favorites: ["Mexico"], eventIDs: ["e1"]), liveGames: [game])

        XCTAssertEqual(apns.recorded.count, 1, "A game matched via both favorites and eventID must start exactly once")
    }

    func test_repeatedRegistration_doesNotReSend() async throws {
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Mexico", strAwayTeam: "Croatia", strStatus: "in")
        let i = install(eventIDs: ["e1"])

        await sendAlreadyLive(install: i, liveGames: [game])
        await sendAlreadyLive(install: i, liveGames: [game])

        XCTAssertEqual(apns.recorded.count, 1, "The SentPushToStart claim must prevent a re-register from re-starting")
    }

    // MARK: - Cross-path dedup with the scheduled transition job

    func test_dedupesAgainstTransitionPath() async throws {
        // A user registers while the game is already live (already-live path fires
        // one start), then the scheduled job runs against the same install. The
        // shared claim must block the transition path from a second start.
        let i = install(favorites: ["Mexico"])
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Mexico", strAwayTeam: "Croatia", strStatus: "in")

        await sendAlreadyLive(install: i, liveGames: [game])
        XCTAssertEqual(apns.recorded.count, 1)

        try await seedInstall(i)
        await ESPNFetchJob.runPushToStartPhase(
            newlyStarted: [game],
            kv: kv,
            apns: apns,
            clock: clock,
            isDebug: false,
            logger: logger
        )

        XCTAssertEqual(apns.recorded.count, 1, "Transition path must not double-fire after an already-live start")
    }

    // MARK: - Environment gateway

    func test_dispatchesThroughMatchingGateway() async throws {
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Mexico", strAwayTeam: "Croatia", strStatus: "in")

        await sendAlreadyLive(
            install: install(token: "sandboxToken", eventIDs: ["e1"], environment: .sandbox),
            liveGames: [game],
            environment: .sandbox,
            isDebug: true
        )

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.environment, .sandbox)
        XCTAssertEqual(apns.recorded.first?.deviceToken, "sandboxToken")
    }
}
