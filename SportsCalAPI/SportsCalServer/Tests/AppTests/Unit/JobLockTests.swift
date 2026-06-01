@testable import App
import XCTest
import Logging

/// Leader-election for scheduled jobs: only the first replica through wins;
/// the rest skip the tick. On a crash, the TTL guarantees self-healing on the
/// next cycle so a wedged replica can't permanently silence the job.
final class JobLockTests: XCTestCase {

    private var kv: InMemoryKeyValueStore!
    private var clock: MutableClock!
    private let logger = Logger(label: "test.joblock")

    override func setUp() async throws {
        clock = MutableClock()
        kv = InMemoryKeyValueStore(clock: clock)
    }

    func test_uncontested_runsBody_andReleases() async throws {
        var ran = false
        let result: Bool? = try await JobLock.withLock(kv, name: "espn-fetch", ttl: 50, instanceID: "i1", logger: logger) {
            ran = true
            return true
        }
        XCTAssertTrue(ran)
        XCTAssertEqual(result, true)

        // Best-effort release is fire-and-forget; give it a beat to land before
        // asserting the lock is free again.
        try await Task.sleep(nanoseconds: 100_000_000)
        let nextRunWon: Bool? = try await JobLock.withLock(kv, name: "espn-fetch", ttl: 50, instanceID: "i2", logger: logger) {
            return true
        }
        XCTAssertEqual(nextRunWon, true, "Lock should be released after the body completes")
    }

    func test_alreadyHeld_skipsBody() async throws {
        // Seed the lock as if a peer instance already claimed it.
        _ = try await kv.setIfAbsent("JobLock-espn-fetch", value: "peer", ttl: 50)

        var ran = false
        let result: Bool? = try await JobLock.withLock(kv, name: "espn-fetch", ttl: 50, instanceID: "self", logger: logger) {
            ran = true
            return true
        }
        XCTAssertFalse(ran, "Body must not run when the lock is held by another instance")
        XCTAssertNil(result)
    }

    func test_ttlExpiry_freesLock() async throws {
        _ = try await kv.setIfAbsent("JobLock-espn-fetch", value: "peer", ttl: 50)
        clock.advance(by: 51)
        var ran = false
        _ = try await JobLock.withLock(kv, name: "espn-fetch", ttl: 50, instanceID: "self", logger: logger) {
            ran = true
        }
        XCTAssertTrue(ran, "After lock TTL expires, the next caller should win")
    }
}
