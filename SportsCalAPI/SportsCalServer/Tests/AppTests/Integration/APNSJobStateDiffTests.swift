@testable import App
import XCTest
import Logging
import SportsCalModel

/// Drives `APNSJob.runOnce` end-to-end with an in-memory KeyValueStore and
/// mocked APNS client. These tests cover the decision ladder — when does the
/// job send an update, when does it stay silent, when does it send an end, and
/// when does it clean up a stale token.
final class APNSJobStateDiffTests: XCTestCase {

    private var kv: InMemoryKeyValueStore!
    private var apns: MockAPNSClient!
    private var clock: MutableClock!
    private let logger = Logger(label: "test.apns-job")
    private let isDebug = false
    private let keyPrefix = "APNS-"
    private let liveScoreKey = "Latest Full Live Info"
    private let token = "devicetoken123"

    override func setUp() async throws {
        clock = MutableClock()
        kv = InMemoryKeyValueStore(clock: clock)
        apns = MockAPNSClient()
    }

    private func registrationKey(_ token: String) -> String { "\(keyPrefix)\(token)" }
    private func eventStateKey(_ eventID: String) -> String { "EventState-\(eventID)" }

    private func registerDevice(eventID: String, home: String? = nil, away: String? = nil) async throws {
        let registration = APNSRegistration(eventID: eventID, homeTeam: home, awayTeam: away)
        try await kv.setJSON(registrationKey(token), value: registration, ttl: nil)
    }

    private func seedLiveScore(_ games: [Game]) async throws {
        let score = TestGameFactory.liveScore(nba: games)
        try await kv.setJSON(liveScoreKey, value: score, ttl: nil)
    }

    private func seedLiveScore(_ score: LiveScore) async throws {
        try await kv.setJSON(liveScoreKey, value: score, ttl: nil)
    }

    private func runJob() async throws {
        try await APNSJob.runOnce(kv: kv, apns: apns, clock: clock, isDebug: isDebug, logger: logger)
    }

    // MARK: - No-push when unchanged

    func test_noNotificationSent_whenContentStateUnchanged() async throws {
        try await registerDevice(eventID: "e1")
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "7", intAwayScore: "3", strStatus: "in", strProgress: "2Q")
        try await seedLiveScore([game])

        // Prime the cache so the job sees "same state" on its first run.
        let state = ContentState(homeScore: 7, awayScore: 3, status: "in", progress: "2Q")
        try await kv.setJSON(eventStateKey("e1"), value: state, ttl: nil)

        try await runJob()

        XCTAssertTrue(apns.recorded.isEmpty, "Expected no pushes when state cache matches current state, got \(apns.recorded.count)")
    }

    func test_sendsUpdate_onHomeScoreIncrement() async throws {
        try await registerDevice(eventID: "e1")
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "10", intAwayScore: "3", strStatus: "in", strProgress: "2Q")
        try await seedLiveScore([game])
        // Cached state is lower — should trigger update.
        try await kv.setJSON(eventStateKey("e1"), value: ContentState(homeScore: 7, awayScore: 3, status: "in", progress: "2Q"), ttl: nil)

        try await runJob()

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.kind, .update)
        XCTAssertEqual(apns.recorded.first?.contentState?.homeScore, 10)
    }

    // MARK: - Goal alert (alerting push so the device vibrates on the lock screen)

    func test_soccerGoal_attachesAlert() async throws {
        // Soccer is in the alerting set: a goal should carry an alert title/body
        // so iOS surfaces a banner + haptic, not a silent redraw.
        try await registerDevice(eventID: "s1")
        let game = TestGameFactory.make(idEvent: "s1", idLeague: "4328", strHomeTeam: "Arsenal", strAwayTeam: "Chelsea", intHomeScore: "1", intAwayScore: "0", strStatus: "in", strProgress: "23'")
        try await seedLiveScore(TestGameFactory.liveScore(soccer: [game]))
        try await kv.setJSON(eventStateKey("s1"), value: ContentState(homeScore: 0, awayScore: 0, status: "in", progress: "22'"), ttl: nil)

        try await runJob()

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.kind, .update)
        XCTAssertEqual(apns.recorded.first?.alertTitle, "⚽️ Goal!")
        XCTAssertEqual(apns.recorded.first?.alertBody, "Arsenal 1 – 0 Chelsea")
    }

    func test_basketballScore_doesNotAttachAlert() async throws {
        // Basketball scores too often to alert on — the update still sends (so the
        // activity redraws) but it must be silent (no alert payload).
        try await registerDevice(eventID: "e1")
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "10", intAwayScore: "3", strStatus: "in", strProgress: "2Q")
        try await seedLiveScore([game])
        try await kv.setJSON(eventStateKey("e1"), value: ContentState(homeScore: 8, awayScore: 3, status: "in", progress: "2Q"), ttl: nil)

        try await runJob()

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.kind, .update)
        XCTAssertNil(apns.recorded.first?.alertTitle, "Basketball score change must stay silent")
    }

    func test_soccerFirstPush_noAlert_whenNoPriorState() async throws {
        // No cached prior state (fresh follow / server restart): we still push the
        // current state, but with no baseline we can't know a goal just happened —
        // so it must be a silent update, not a phantom vibration.
        try await registerDevice(eventID: "s1")
        let game = TestGameFactory.make(idEvent: "s1", idLeague: "4328", strHomeTeam: "Arsenal", strAwayTeam: "Chelsea", intHomeScore: "1", intAwayScore: "0", strStatus: "in", strProgress: "23'")
        try await seedLiveScore(TestGameFactory.liveScore(soccer: [game]))

        try await runJob()

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertNil(apns.recorded.first?.alertTitle, "First push with no baseline must not alert")
    }

    func test_sendsUpdate_onStatusChange() async throws {
        try await registerDevice(eventID: "e1")
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "7", intAwayScore: "3", strStatus: "in", strProgress: "halftime")
        try await seedLiveScore([game])
        try await kv.setJSON(eventStateKey("e1"), value: ContentState(homeScore: 7, awayScore: 3, status: "in", progress: "2Q"), ttl: nil)

        try await runJob()

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.contentState?.progress, "halftime")
    }

    // MARK: - End on final

    func test_sendsEnd_whenGameReachesFinal_andDeletesBothRedisKeys() async throws {
        try await registerDevice(eventID: "e1")
        // Status "post" makes `hasDoneStatus` true, triggering the end branch.
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "21", intAwayScore: "17", strStatus: "post", strProgress: "Final")
        try await seedLiveScore([game])
        try await kv.setJSON(eventStateKey("e1"), value: ContentState(homeScore: 21, awayScore: 10, status: "in", progress: "4Q"), ttl: nil)

        try await runJob()

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.kind, .end)
        let snapshot = kv.rawSnapshot
        XCTAssertNil(snapshot[registrationKey(token)], "APNS-{token} should be deleted after end push")
        XCTAssertNil(snapshot[eventStateKey("e1")], "EventState cache should be deleted after end push")
    }

    // MARK: - State cache write ordering

    func test_updatesStateCacheBeforeSending_so_failedPushDoesNotResend() async throws {
        // Current behavior: EventState cache is written *before* APNS send. That
        // means a crash between write and send leaves the cache updated and the
        // user never receives that particular update. We test this to document it;
        // changing the order would be an improvement but is a separate follow-up.
        try await registerDevice(eventID: "e1")
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "14", intAwayScore: "0", strStatus: "in", strProgress: "1Q")
        try await seedLiveScore([game])

        try await runJob()

        XCTAssertEqual(apns.recorded.count, 1)
        let cached = try await kv.getJSON(eventStateKey("e1"), as: ContentState.self)
        XCTAssertEqual(cached?.homeScore, 14)
    }

    // MARK: - Match by team-name fallback

    func test_matchesByTeamNames_whenEventIDMissing_stillSendsUpdate() async throws {
        // Registration says event "e-missing" but live data has "e-actual" with
        // the same teams. Team-name fallback should find the game.
        try await registerDevice(eventID: "e-missing", home: "Lakers", away: "Warriors")
        let game = TestGameFactory.make(idEvent: "e-actual", strHomeTeam: "Lakers", strAwayTeam: "Warriors", intHomeScore: "50", intAwayScore: "48", strStatus: "in", strProgress: "4Q")
        try await seedLiveScore([game])

        try await runJob()

        XCTAssertEqual(apns.recorded.count, 1, "Team-name fallback should have matched")
    }

    // MARK: - No keys, no work

    func test_noRegistrations_doesNothing() async throws {
        try await seedLiveScore([TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "1", intAwayScore: "0", strStatus: "in")])
        try await runJob()
        XCTAssertTrue(apns.recorded.isEmpty)
    }

    func test_nonNumericScore_skipsSilently() async throws {
        // Scheduled games have empty strings for scores — those must be ignored,
        // not crash or produce a push with 0-0.
        try await registerDevice(eventID: "e1")
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "", intAwayScore: "", strStatus: "pre")
        try await seedLiveScore([game])

        try await runJob()

        XCTAssertTrue(apns.recorded.isEmpty)
    }

    // MARK: - Multi-environment dispatch

    /// A single server must dispatch sandbox-token registrations through the
    /// development APNS gateway and production-token registrations through the
    /// production gateway. Without this, dev devices (whose tokens come from
    /// the `aps-environment = development` entitlement) get `BadDeviceToken`
    /// when the server is in `--env production`.
    func test_dispatchesBothEnvironments_perTokenGateway() async throws {
        // Use distinct events for each token to side-step the per-event state-
        // diff dedup (which is per-event, not per-token, and would otherwise
        // suppress the second token's push within the same cycle).
        let prodToken = "prodToken"
        let sandboxToken = "sandboxToken"
        try await kv.setJSON("APNS-\(prodToken)", value: APNSRegistration(eventID: "ePROD"), ttl: nil)
        try await kv.setJSON("debug-APNS-\(sandboxToken)", value: APNSRegistration(eventID: "eSANDBOX"), ttl: nil)

        let prodGame = TestGameFactory.make(idEvent: "ePROD", strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "10", intAwayScore: "3", strStatus: "in", strProgress: "2Q")
        let sandboxGame = TestGameFactory.make(idEvent: "eSANDBOX", strHomeTeam: "C", strAwayTeam: "D", intHomeScore: "5", intAwayScore: "1", strStatus: "in", strProgress: "1Q")
        try await seedLiveScore([prodGame, sandboxGame])
        try await kv.setJSON(eventStateKey("ePROD"), value: ContentState(homeScore: 7, awayScore: 3, status: "in", progress: "2Q"), ttl: nil)
        try await kv.setJSON(eventStateKey("eSANDBOX"), value: ContentState(homeScore: 0, awayScore: 0, status: "in", progress: "1Q"), ttl: nil)

        try await runJob()

        XCTAssertEqual(apns.recorded.count, 2)
        let byToken = Dictionary(uniqueKeysWithValues: apns.recorded.map { ($0.deviceToken, $0.environment) })
        XCTAssertEqual(byToken[prodToken], .production)
        XCTAssertEqual(byToken[sandboxToken], .sandbox)
    }

    // MARK: - TTL slide on update

    func test_successfulUpdate_slidesRegistrationTTLForward() async throws {
        // Registration starts with 1h left. After a successful update push, the
        // job should refresh it back toward the 12h ceiling so an active activity
        // never expires mid-game even if the client misses BGAppRefresh.
        let registration = APNSRegistration(eventID: "e1", homeTeam: nil, awayTeam: nil)
        try await kv.setJSON(registrationKey(token), value: registration, ttl: 60 * 60)
        let initialTTL = kv.ttl(registrationKey(token)) ?? 0
        XCTAssertLessThan(initialTTL, 60 * 60 + 1)

        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "10", intAwayScore: "3", strStatus: "in", strProgress: "2Q")
        try await seedLiveScore([game])
        try await kv.setJSON(eventStateKey("e1"), value: ContentState(homeScore: 7, awayScore: 3, status: "in", progress: "2Q"), ttl: nil)

        try await runJob()

        XCTAssertEqual(apns.recorded.count, 1)
        let refreshedTTL = kv.ttl(registrationKey(token)) ?? 0
        XCTAssertGreaterThan(refreshedTTL, 60 * 60 * 11, "TTL should have been slid forward to ~12h, got \(refreshedTTL)s")
    }
}
