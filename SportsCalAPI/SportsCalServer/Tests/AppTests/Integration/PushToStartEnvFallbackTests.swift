@testable import App
import XCTest
import Logging
import SportsCalModel

/// Covers the APNS environment fallback: a device that registered under the wrong
/// gateway (e.g. a sandbox push token labeled production because the client's hint
/// comes from `#if DEBUG` rather than the entitlement) gets `badDeviceToken` on the
/// labeled gateway. The send must retry the opposite gateway so the activity still
/// arrives — and only treat the token as dead when BOTH gateways reject it.
final class PushToStartEnvFallbackTests: XCTestCase {

    private var kv: InMemoryKeyValueStore!
    private var apns: MockAPNSClient!
    private var clock: MutableClock!
    private let logger = Logger(label: "test.env-fallback")

    override func setUp() async throws {
        clock = MutableClock()
        kv = InMemoryKeyValueStore(clock: clock)
        apns = MockAPNSClient()
    }

    private func install(token: String = "t1", eventIDs: [String] = ["e1"]) -> PushToStartInstall {
        PushToStartInstall(installID: "i1", token: token, favorites: [], eventIDs: eventIDs, environment: .production)
    }

    private func seedInstall(_ install: PushToStartInstall) async throws {
        try await kv.setJSON("PushToStartByInstall-\(install.installID)", value: install, ttl: nil)
        try await kv.setString("PushToStartTokenIndex-\(install.token)", value: install.installID, ttl: nil)
    }

    private func badToken(times: Int) {
        apns.queueError(APNSSendError(reason: .badDeviceToken, underlying: "test"), for: "t1", times: times)
    }

    private func send() async {
        let game = TestGameFactory.make(idEvent: "e1", strHomeTeam: "Mexico", strAwayTeam: "Croatia", strStatus: "in")
        await ESPNFetchJob.sendStartsForAlreadyLiveGames(
            install: install(),
            liveGames: [game],
            environment: .production,
            kv: kv,
            apns: apns,
            clock: clock,
            isDebug: false,
            logger: logger
        )
    }

    func test_badDeviceTokenOnProduction_retriesSandbox_andDelivers() async throws {
        try await seedInstall(install())
        badToken(times: 1) // production rejects, sandbox (no queued error) accepts

        await send()

        XCTAssertEqual(apns.recorded.count, 1, "exactly one delivery — the sandbox retry")
        XCTAssertEqual(apns.recorded.first?.environment, .sandbox, "delivered on the opposite gateway")
        XCTAssertEqual(apns.recorded.first?.kind, .start)
        // Token was NOT dead — install must survive so future sends still target it.
        let stillRegistered = try await kv.exists("PushToStartByInstall-i1")
        XCTAssertTrue(stillRegistered, "a recoverable env mismatch must not delete the install")
    }

    func test_badDeviceTokenOnBothGateways_marksStale_andClearsClaims() async throws {
        try await seedInstall(install())
        badToken(times: 2) // both production and sandbox reject → genuinely dead

        await send()

        XCTAssertTrue(apns.recorded.isEmpty, "no successful delivery")
        let installGone = try await kv.exists("PushToStartByInstall-i1") == false
        let indexGone = try await kv.exists("PushToStartTokenIndex-t1") == false
        XCTAssertTrue(installGone, "dead token's install record is removed")
        XCTAssertTrue(indexGone, "dead token's reverse index is removed")
        // The dedup claim for this token must be cleared so a re-registration of the
        // same token isn't blocked from retrying for the 8h claim TTL.
        let remainingClaims = try await kv.scanKeys(matching: "SentPushToStart-t1-*")
        XCTAssertTrue(remainingClaims.isEmpty, "stale token's dedup claims are cleared")
    }
}
