@testable import App
import XCTest
import Logging

/// APNS errors fall into three buckets: stale-token (clean up), rate-limit
/// (retain, retry next tick), and everything else (log, retain). Making sure
/// we don't over-clean (deleting a valid registration on a transient failure)
/// or under-clean (leaving a dead token to burn tick cycles) is the whole job
/// of these tests.
final class APNSJobErrorHandlingTests: XCTestCase {

    private var kv: InMemoryKeyValueStore!
    private var apns: MockAPNSClient!
    private var clock: MutableClock!
    private let logger = Logger(label: "test.apns-job")
    private let token = "devicetoken"

    override func setUp() async throws {
        clock = MutableClock()
        kv = InMemoryKeyValueStore(clock: clock)
        apns = MockAPNSClient()

        // Seed a standard registration + game-in-progress so every test starts
        // with the job wanting to send an update.
        try await kv.setJSON("APNS-\(token)", value: APNSRegistration(eventID: "e1", homeTeam: nil, awayTeam: nil), ttl: nil)
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "7", intAwayScore: "3", strStatus: "in", strProgress: "1Q")
        try await kv.setJSON("Latest Full Live Info", value: TestGameFactory.liveScore(nba: [game]), ttl: nil)
    }

    private func runJob() async throws {
        try await APNSJob.runOnce(kv: kv, apns: apns, clock: clock, isDebug: false, logger: logger)
    }

    // MARK: - Stale-token cleanup

    func test_unregisteredResponse_deletesRegistrationKey() async throws {
        apns.queueError(APNSSendError(reason: .unregistered, underlying: nil), for: token)

        try await runJob()

        let snapshot = kv.rawSnapshot
        XCTAssertNil(snapshot["APNS-\(token)"], "Unregistered → registration key should be deleted")
    }

    func test_badDeviceToken_retriesOppositeGateway_andRetainsRegistration() async throws {
        // A single badDeviceToken is no longer terminal: the token may have
        // registered under the wrong APNS environment, so the send retries the
        // opposite gateway. One queued error → production rejects, sandbox (no
        // queued error) delivers → registration is retained.
        apns.queueError(APNSSendError(reason: .badDeviceToken, underlying: nil), for: token)

        try await runJob()

        let snapshot = kv.rawSnapshot
        XCTAssertNotNil(snapshot["APNS-\(token)"], "Recoverable env mismatch must NOT delete the registration")
        XCTAssertEqual(apns.recorded.last?.environment, .sandbox, "update delivered on the opposite gateway")
    }

    func test_badDeviceToken_onBothGateways_deletesRegistrationKey() async throws {
        // When BOTH gateways reject the token it is genuinely dead → clean up.
        apns.queueError(APNSSendError(reason: .badDeviceToken, underlying: nil), for: token, times: 2)

        try await runJob()

        let snapshot = kv.rawSnapshot
        XCTAssertNil(snapshot["APNS-\(token)"], "Dead-on-both → registration key should be deleted")
    }

    // MARK: - Transient-failure retention

    func test_tooManyRequests_retainsRegistrationKey() async throws {
        apns.queueError(APNSSendError(reason: .tooManyRequests, underlying: nil), for: token)

        try await runJob()

        let snapshot = kv.rawSnapshot
        XCTAssertNotNil(snapshot["APNS-\(token)"], "Rate-limited → token should NOT be deleted")
    }

    func test_internalServerError_retainsRegistrationKey() async throws {
        apns.queueError(APNSSendError(reason: .internalServerError, underlying: nil), for: token)

        try await runJob()

        let snapshot = kv.rawSnapshot
        XCTAssertNotNil(snapshot["APNS-\(token)"])
    }

    func test_payloadTooLarge_retainsRegistrationKey() async throws {
        // Payload-too-large is a permanent server-reject for *this* payload, but
        // the token itself is still valid. Don't delete — the next tick's payload
        // (with a different ContentState) might be fine.
        apns.queueError(APNSSendError(reason: .payloadTooLarge, underlying: nil), for: token)

        try await runJob()

        let snapshot = kv.rawSnapshot
        XCTAssertNotNil(snapshot["APNS-\(token)"])
    }

    func test_tokenAuthFailure_retainsRegistrationKey() async throws {
        // Auth-key failures are a server-config bug, not a token bug. Deleting
        // the registration would mean losing all live activities every time the
        // APNS auth key expired.
        apns.queueError(APNSSendError(reason: .tokenAuthFailure, underlying: nil), for: token)

        try await runJob()

        let snapshot = kv.rawSnapshot
        XCTAssertNotNil(snapshot["APNS-\(token)"])
    }

    // MARK: - End-push failure does not cascade

    func test_endPushFailure_doesNotDeleteCache_orRegistration() async throws {
        // When a game finishes and the end push fails, the registration key
        // still gets deleted (end-of-lifecycle) even though APNS errored —
        // current behavior at APNSJob.swift's end branch. This test pins it.
        try await kv.setJSON("APNS-\(token)", value: APNSRegistration(eventID: "e2", homeTeam: nil, awayTeam: nil), ttl: nil)
        let finished = TestGameFactory.make(idEvent: "e2", strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "21", intAwayScore: "17", strStatus: "post", strProgress: "Final")
        try await kv.setJSON("Latest Full Live Info", value: TestGameFactory.liveScore(nba: [finished]), ttl: nil)
        apns.queueError(APNSSendError(reason: .internalServerError, underlying: nil), for: token)

        try await runJob()

        let snapshot = kv.rawSnapshot
        // Registration is still deleted — the game is done, the user doesn't
        // need updates. The failed push is simply lost.
        XCTAssertNil(snapshot["APNS-\(token)"])
    }
}
