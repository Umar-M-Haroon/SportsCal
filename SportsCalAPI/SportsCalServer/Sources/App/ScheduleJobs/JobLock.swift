import Foundation
import Vapor
import Logging

/// Process-startup UUID used as the value of every JobLock claim, so logs can
/// identify which replica won the lock for a given tick.
struct InstanceIDKey: StorageKey {
    typealias Value = String
}

extension Application {
    /// Stable per-process identifier. Generated lazily on first read and cached
    /// in storage so every scheduled-job tick within this process uses the same
    /// value (and a fresh process — including a restart of the same replica —
    /// gets a new one).
    var instanceID: String {
        if let existing = storage[InstanceIDKey.self] { return existing }
        let new = UUID().uuidString
        storage[InstanceIDKey.self] = new
        return new
    }
}

/// Best-effort distributed lock for scheduled jobs. Built on `setIfAbsent` so
/// that across N server replicas exactly one wins the tick. On crash, the TTL
/// guarantees the lock self-heals on the next cycle.
enum JobLock {
    /// Acquires the named lock, runs `body`, releases the lock. If the lock is
    /// already held, returns `nil` without running `body`.
    ///
    /// - Parameter ttl: must comfortably exceed the expected body runtime; a
    ///   crash before release leaves the lock pinned until this expires, so
    ///   pick a value that's safe to wait out before the next tick fires.
    @discardableResult
    static func withLock<T>(
        _ kv: KeyValueStore,
        name: String,
        ttl: TimeInterval,
        instanceID: String,
        logger: Logger,
        body: () async throws -> T
    ) async throws -> T? {
        let key = RedisEndpoint.jobLock(name).getValue(isDebug: false).rawValue
        // A Redis error is NOT contention — logging it as "held by another instance"
        // hid hours of pool exhaustion during the July 2026 outage. Skip either way
        // (can't guarantee exclusivity without the claim), but say what happened.
        let claimed: Bool
        do {
            claimed = try await kv.setIfAbsent(key, value: instanceID, ttl: ttl)
        } catch {
            logger.warning("Skipping \(name) — JobLock claim failed with Redis error: \(String(reflecting: error))")
            return nil
        }
        guard claimed else {
            logger.info("Skipping \(name) — JobLock held by another instance")
            return nil
        }
        defer {
            // Best-effort release. We don't await it because the body's return
            // value is what callers care about; TTL backstops a missed delete.
            Task { _ = try? await kv.delete([key]) }
        }
        return try await body()
    }
}
