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

    func testChannelFieldKeysCounterPerChannel() async throws {
        let clock = MutableClock()
        let kv = InMemoryKeyValueStore(clock: clock)
        let telemetry = RedisTelemetry(kv: kv, clock: clock)

        await telemetry.info("client.paywall_shown", ["channel": "appstore"])
        await telemetry.info("client.paywall_shown", ["channel": "debug"])
        await telemetry.info("client.paywall_shown", ["channel": "appstore"])

        let day = TelemetryKeys.epochDay(clock.now)
        let snapshot = kv.rawSnapshot
        XCTAssertEqual(snapshot["telemetry:client.paywall_shown:appstore:\(day)"], "2")
        XCTAssertEqual(snapshot["telemetry:client.paywall_shown:debug:\(day)"], "1")
        XCTAssertNil(snapshot["telemetry:client.paywall_shown:\(day)"],
                     "channel-tagged events must not also write the legacy key")
    }

    func testClientCountersBreakoutsAreAllowListed() async throws {
        let clock = MutableClock()
        let kv = InMemoryKeyValueStore(clock: clock)
        let counters = ClientTelemetryCounters(kv: kv, clock: clock)

        await counters.record(event: "paywall_shown", channel: "appstore", platform: "ios",
                              installID: "A", fields: ["trigger": "post_onboarding"])
        await counters.record(event: "paywall_shown", channel: "appstore", platform: "ios",
                              installID: "A", fields: ["trigger": "made-up-by-a-leaked-key"])
        await counters.record(event: "gate_hit", channel: "testflight", platform: "macos",
                              installID: "B", fields: ["feature": "goalAlerts", "other": "x"])

        let day = TelemetryKeys.epochDay(clock.now)
        let snapshot = kv.rawSnapshot
        XCTAssertEqual(snapshot["telemetry:client.paywall_shown:appstore:trigger=post_onboarding:\(day)"], "1")
        XCTAssertEqual(snapshot["telemetry:client.paywall_shown:appstore:trigger=other:\(day)"], "1",
                       "unknown values collapse to `other` so cardinality stays bounded")
        XCTAssertEqual(snapshot["telemetry:client.gate_hit:testflight:feature=goalAlerts:\(day)"], "1")
        XCTAssertFalse(snapshot.keys.contains { $0.contains("other=x") }, "non-allow-listed fields aren't broken out")
    }

    func testAppActiveFeedsPerChannelPlatformDAU() async throws {
        let clock = MutableClock()
        let kv = InMemoryKeyValueStore(clock: clock)
        let counters = ClientTelemetryCounters(kv: kv, clock: clock)
        let day = TelemetryKeys.epochDay(clock.now)

        for id in ["A", "B", "A"] {
            await counters.record(event: "app_active", channel: "appstore", platform: "ios", installID: id, fields: [:])
        }
        await counters.record(event: "app_active", channel: "appstore", platform: "macos", installID: "C", fields: [:])
        await counters.record(event: "app_active", channel: "debug", platform: "ios", installID: "DEV", fields: [:])
        clock.advance(by: 86_400)
        await counters.record(event: "app_active", channel: "appstore", platform: "ios", installID: "A", fields: [:])
        await counters.record(event: "app_active", channel: "appstore", platform: "ios", installID: "D", fields: [:])

        let iosDay1 = TelemetryKeys.dau(channel: "appstore", platform: "ios", day: day)
        let iosDay2 = TelemetryKeys.dau(channel: "appstore", platform: "ios", day: day + 1)
        let macDay1 = TelemetryKeys.dau(channel: "appstore", platform: "macos", day: day)
        let dauIOS = try await kv.hllCount([iosDay1])
        let dauAll = try await kv.hllCount([iosDay1, macDay1])
        let twoDay = try await kv.hllCount([iosDay1, iosDay2, macDay1])
        XCTAssertEqual(dauIOS, 2, "repeat pings from one install count once")
        XCTAssertEqual(dauAll, 3, "PFCOUNT over platforms unions them")
        XCTAssertEqual(twoDay, 4, "multi-day union = WAU/MAU; A counted once")
        XCTAssertEqual(iosDay1, "telemetry:dau:appstore:ios:\(day)")
        XCTAssertNotNil(kv.ttl(iosDay1), "HLL keys must carry a TTL")
        XCTAssertLessThanOrEqual(kv.ttl(iosDay1) ?? .infinity, ClientTelemetryCounters.uniqueRetention)
    }

    func testFunnelEventsFeedUniqueInstallHLL() async throws {
        let clock = MutableClock()
        let kv = InMemoryKeyValueStore(clock: clock)
        let counters = ClientTelemetryCounters(kv: kv, clock: clock)
        let day = TelemetryKeys.epochDay(clock.now)

        for id in ["A", "A", "A", "B"] {
            await counters.record(event: "paywall_shown", channel: "appstore", platform: "ios", installID: id, fields: [:])
        }
        await counters.record(event: "rating_prompt_shown", channel: "appstore", platform: "ios", installID: "A", fields: [:])
        await counters.record(event: "paywall_shown", channel: "appstore", platform: "ios", installID: nil, fields: [:])

        let key = TelemetryKeys.unique("client.paywall_shown", channel: "appstore", day: day)
        XCTAssertEqual(key, "telemetry:uniq:client.paywall_shown:appstore:\(day)")
        let uniques = try await kv.hllCount([key])
        XCTAssertEqual(uniques, 2)
        XCTAssertNil(kv.rawSnapshot[TelemetryKeys.unique("client.rating_prompt_shown", channel: "appstore", day: day)],
                     "only allow-listed funnel events get an HLL")
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
