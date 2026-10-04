@testable import App
import XCTest
import Logging
import SportsCalModel

/// APNSJob reads registrations from a SET index instead of SCANning every minute.
final class APNSRegistrationIndexTests: XCTestCase {
    private let logger = Logger(label: "test.apns-index")

    private func liveGame(_ eventID: String) -> Game {
        TestGameFactory.make(
            idEvent: eventID, strHomeTeam: "H", strAwayTeam: "A",
            intHomeScore: "1", intAwayScore: "0", strStatus: "in", strProgress: "1Q"
        )
    }

    func test_backfillsIndexFromScan_thenUsesIndex() async throws {
        let clock = MutableClock()
        let kv = RedisCapableKV(inner: InMemoryKeyValueStore(clock: clock))
        let apns = MockAPNSClient()
        // Registered before the index existed (or by a writer that doesn't maintain it).
        try await kv.setJSON("APNS-tok1", value: APNSRegistration(eventID: "e1"), ttl: nil)
        try await kv.setJSON("debug-APNS-tok2", value: APNSRegistration(eventID: "e2"), ttl: nil)
        try await kv.setJSON("Latest Full Live Info", value: TestGameFactory.liveScore(nba: [liveGame("e1"), liveGame("e2")]), ttl: nil)

        try await APNSJob.runOnce(kv: kv, apns: apns, clock: clock, isDebug: false, logger: logger)

        XCTAssertEqual(apns.recorded.count, 2)
        let prodIndex = try await kv.setMembers("APNSRegistrationIndex")
        let sandboxIndex = try await kv.setMembers("debug-APNSRegistrationIndex")
        XCTAssertEqual(prodIndex, ["APNS-tok1"])
        XCTAssertEqual(sandboxIndex, ["debug-APNS-tok2"])
    }

    func test_indexedRegistration_isDispatched_withoutReconcileScan() async throws {
        let clock = MutableClock()
        let kv = RedisCapableKV(inner: InMemoryKeyValueStore(clock: clock))
        let apns = MockAPNSClient()
        // Reconcile already ran this interval: only the index is consulted.
        _ = try await kv.setIfAbsent("APNSRegistrationIndexReconciled", value: "1", ttl: 600)
        _ = try await kv.setIfAbsent("debug-APNSRegistrationIndexReconciled", value: "1", ttl: 600)
        try await kv.setJSON("APNS-indexed", value: APNSRegistration(eventID: "e1"), ttl: nil)
        await APNSRegistrationIndex.add("APNS-indexed", kv: kv)
        try await kv.setJSON("APNS-unindexed", value: APNSRegistration(eventID: "e1"), ttl: nil)
        try await kv.setJSON("Latest Full Live Info", value: TestGameFactory.liveScore(nba: [liveGame("e1")]), ttl: nil)

        try await APNSJob.runOnce(kv: kv, apns: apns, clock: clock, isDebug: false, logger: logger)

        XCTAssertEqual(apns.recorded.count, 1, "only the indexed registration is read between reconciles")
    }

    func test_expiredRegistration_isDroppedFromIndex() async throws {
        let clock = MutableClock()
        let kv = RedisCapableKV(inner: InMemoryKeyValueStore(clock: clock))
        let apns = MockAPNSClient()
        try await kv.setJSON("APNS-gone", value: APNSRegistration(eventID: "e1"), ttl: 60)
        await APNSRegistrationIndex.add("APNS-gone", kv: kv)
        clock.advance(by: 61)
        try await kv.setJSON("Latest Full Live Info", value: TestGameFactory.liveScore(nba: [liveGame("e1")]), ttl: nil)

        try await APNSJob.runOnce(kv: kv, apns: apns, clock: clock, isDebug: false, logger: logger)

        XCTAssertEqual(apns.recorded.count, 0)
        let members = try await kv.setMembers("APNSRegistrationIndex")
        XCTAssertEqual(members, [])
    }

    func test_addRemove_routeByKeyPrefix() async throws {
        let kv = RedisCapableKV()
        await APNSRegistrationIndex.add("APNS-a", kv: kv)
        await APNSRegistrationIndex.add("debug-APNS-b", kv: kv)
        await APNSRegistrationIndex.add("PushToStart-c", kv: kv) // not a registration key: ignored
        var prod = try await kv.setMembers("APNSRegistrationIndex")
        let sandbox = try await kv.setMembers("debug-APNSRegistrationIndex")
        XCTAssertEqual(prod, ["APNS-a"])
        XCTAssertEqual(sandbox, ["debug-APNS-b"])

        await APNSRegistrationIndex.remove("APNS-a", kv: kv)
        prod = try await kv.setMembers("APNSRegistrationIndex")
        XCTAssertEqual(prod, [])
    }

    func test_storeWithoutSets_fallsBackToScan() async throws {
        let clock = MutableClock()
        let kv = InMemoryKeyValueStore(clock: clock)
        try await kv.setJSON("APNS-x", value: APNSRegistration(eventID: "e1"), ttl: nil)
        let keys = try await APNSRegistrationIndex.registrationKeys(environment: .production, kv: kv, logger: logger)
        XCTAssertEqual(keys, ["APNS-x"])
    }
}
