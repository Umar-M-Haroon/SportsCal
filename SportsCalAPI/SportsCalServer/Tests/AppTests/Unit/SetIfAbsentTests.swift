@testable import App
import XCTest

/// `setIfAbsent` is the foundation of every dedup / leader-election path in
/// the server. Under contention it must allow exactly one caller to win — if
/// two are racing into the same key, both seeing `false` and proceeding is the
/// exact bug we're trying to eliminate (duplicate Live Activities).
final class SetIfAbsentTests: XCTestCase {

    private var kv: InMemoryKeyValueStore!
    private var clock: MutableClock!

    override func setUp() async throws {
        clock = MutableClock()
        kv = InMemoryKeyValueStore(clock: clock)
    }

    func test_firstCallSucceeds_secondCallFails() async throws {
        let first = try await kv.setIfAbsent("k", value: "v1", ttl: 60)
        let second = try await kv.setIfAbsent("k", value: "v2", ttl: 60)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let value = try await kv.getString("k")
        XCTAssertEqual(value, "v1", "Loser must not overwrite the winner's value")
    }

    func test_ttlExpiry_reopensKey() async throws {
        let initial = try await kv.setIfAbsent("k", value: "v1", ttl: 60)
        XCTAssertTrue(initial)
        clock.advance(by: 61)
        let afterExpiry = try await kv.setIfAbsent("k", value: "v2", ttl: 60)
        XCTAssertTrue(afterExpiry, "After TTL expires, a new caller should win")
        let value = try await kv.getString("k")
        XCTAssertEqual(value, "v2")
    }

    func test_concurrentClaims_exactlyOneWins() async throws {
        // Burst 100 concurrent claimants at the same key. Exactly one should
        // see `true`. This is the load-bearing assertion the multi-instance
        // dedup story rests on.
        let attempts = 100
        let result = await withTaskGroup(of: Bool.self) { group in
            for i in 0..<attempts {
                group.addTask {
                    (try? await self.kv.setIfAbsent("k", value: "v\(i)", ttl: 60)) ?? false
                }
            }
            var winners = 0
            for await ok in group where ok { winners += 1 }
            return winners
        }
        XCTAssertEqual(result, 1, "Exactly one caller must win the claim under contention")
    }

    func test_delete_reopensKey() async throws {
        let initial = try await kv.setIfAbsent("k", value: "v1", ttl: 60)
        XCTAssertTrue(initial)
        _ = try await kv.delete(["k"])
        let after = try await kv.setIfAbsent("k", value: "v2", ttl: 60)
        XCTAssertTrue(after, "After delete, a new caller should win")
    }
}
