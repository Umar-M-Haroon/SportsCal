@testable import App
import XCTVapor

/// Covers the persisted-telemetry path: RedisTelemetry writes per-day counters,
/// and KeyValueStore.increment arms a TTL that can't get stuck (the failure mode
/// that bricked the write rate-limit).
final class TelemetryTests: XCTestCase {

    func testRecordsPerDayCountersByEventAndLevel() async throws {
        let clock = MutableClock()
        let kv = InMemoryKeyValueStore(clock: clock)
        let telemetry = RedisTelemetry(kv: kv, clock: clock)

        await telemetry.info("push.sent")
        await telemetry.info("push.sent")
        await telemetry.warning("ratelimit.rejected")

        let day = Int(clock.now.timeIntervalSince1970) / 86_400
        let snapshot = kv.rawSnapshot
        XCTAssertEqual(snapshot["telemetry:push.sent:\(day)"], "2")
        XCTAssertEqual(snapshot["telemetry:ratelimit.rejected:\(day)"], "1")
    }

    func testCountersBucketByDay() async throws {
        let clock = MutableClock()
        let kv = InMemoryKeyValueStore(clock: clock)
        let telemetry = RedisTelemetry(kv: kv, clock: clock)

        await telemetry.info("push.sent")
        let day1 = Int(clock.now.timeIntervalSince1970) / 86_400
        clock.advance(by: 86_400) // next day
        await telemetry.info("push.sent")
        let day2 = Int(clock.now.timeIntervalSince1970) / 86_400

        let snapshot = kv.rawSnapshot
        XCTAssertEqual(snapshot["telemetry:push.sent:\(day1)"], "1")
        XCTAssertEqual(snapshot["telemetry:push.sent:\(day2)"], "1")
    }

    func testIncrementArmsTTLOnCreation() async throws {
        let clock = MutableClock()
        let kv = InMemoryKeyValueStore(clock: clock)
        let count = try await kv.increment("counter", ttl: 100)
        XCTAssertEqual(count, 1)
        XCTAssertNotNil(kv.ttl("counter"), "first increment must arm a TTL")
    }

    func testIncrementKeepsExistingTTL() async throws {
        // EXPIRE … NX semantics: a later increment with a larger ttl must NOT
        // extend the window — the counter resets cleanly at the original expiry.
        let clock = MutableClock()
        let kv = InMemoryKeyValueStore(clock: clock)
        _ = try await kv.increment("counter", ttl: 100)
        _ = try await kv.increment("counter", ttl: 9_999)
        let ttl = try XCTUnwrap(kv.ttl("counter"))
        XCTAssertLessThanOrEqual(ttl, 100, "TTL must not be extended by later increments")
    }
}
