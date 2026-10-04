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

/// Ownership-checked release and the waiting variant used by the schedule write lock.
final class JobLockOwnershipTests: XCTestCase {
    private var clock: MutableClock!
    private var kv: InMemoryKeyValueStore!
    private let logger = Logger(label: "test.joblock.ownership")

    override func setUp() async throws {
        clock = MutableClock()
        kv = InMemoryKeyValueStore(clock: clock)
    }

    /// The body outruns the TTL: our lock expires, another instance claims it, and our
    /// release must NOT delete their lock (a blind DEL would let a third run start).
    func test_ttlExpiresMidRun_releaseDoesNotDeleteNewOwnersLock() async throws {
        let store = kv!
        let clock = clock!
        try await JobLock.withLock(store, name: "espn-fetch", ttl: 50, instanceID: "self", logger: logger) {
            clock.advance(by: 51)
            let peerWon = try await store.setIfAbsent("JobLock-espn-fetch", value: "peer", ttl: 50)
            XCTAssertTrue(peerWon, "after expiry a peer can claim the lock")
        }
        let holder = try await store.getString("JobLock-espn-fetch")
        XCTAssertEqual(holder, "peer", "our release must leave the peer's lock in place")
    }

    func test_ttlExpiresMidRun_atomicPath_doesNotDeleteNewOwnersLock() async throws {
        let store = RedisCapableKV(inner: kv)
        let clock = clock!
        try await JobLock.withLock(store, name: "espn-fetch", ttl: 50, instanceID: "self", logger: logger) {
            clock.advance(by: 51)
            _ = try await store.setIfAbsent("JobLock-espn-fetch", value: "peer", ttl: 50)
        }
        XCTAssertEqual(store.compareAndDeleteCalls, 1, "release goes through compare-and-delete when available")
        let holder = try await store.getString("JobLock-espn-fetch")
        XCTAssertEqual(holder, "peer")
    }

    func test_release_isAwaited_andFreesLock() async throws {
        try await JobLock.withLock(kv, name: "apns-job", ttl: 50, instanceID: "self", logger: logger) {}
        let holder = try await kv.getString("JobLock-apns-job")
        XCTAssertNil(holder, "release completes before withLock returns")
    }

    func test_release_onThrow_freesLock() async throws {
        struct Boom: Error {}
        do {
            try await JobLock.withLock(kv, name: "apns-job", ttl: 50, instanceID: "self", logger: logger) {
                throw Boom()
            }
            XCTFail("should rethrow")
        } catch is Boom {}
        let holder = try await kv.getString("JobLock-apns-job")
        XCTAssertNil(holder)
    }

    func test_withLockWaiting_acquiresOnceHolderReleases() async throws {
        _ = try await kv.setIfAbsent("JobLock-schedule-write", value: "peer", ttl: 60)
        let store = kv!
        Task {
            try await Task.sleep(nanoseconds: 150_000_000)
            _ = try await store.delete(["JobLock-schedule-write"])
        }
        let result: Int? = try await JobLock.withLockWaiting(
            kv, name: "schedule-write", ttl: 60, instanceID: "self", logger: logger,
            maxWait: 5, retryInterval: 0.05
        ) { 42 }
        XCTAssertEqual(result, 42, "a waiter runs once the holder releases, instead of dropping its work")
    }

    func test_withLockWaiting_timesOut_withoutRunningBody() async throws {
        _ = try await kv.setIfAbsent("JobLock-schedule-write", value: "peer", ttl: 60)
        var ran = false
        let result: Bool? = try await JobLock.withLockWaiting(
            kv, name: "schedule-write", ttl: 60, instanceID: "self", logger: logger,
            maxWait: 0.2, retryInterval: 0.05
        ) {
            ran = true
            return true
        }
        XCTAssertNil(result)
        XCTAssertFalse(ran)
        let holder = try await kv.getString("JobLock-schedule-write")
        XCTAssertEqual(holder, "peer", "a timed-out waiter never touches the holder's lock")
    }
}
