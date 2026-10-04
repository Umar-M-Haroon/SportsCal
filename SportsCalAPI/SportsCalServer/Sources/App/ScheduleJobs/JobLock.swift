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
        let key = lockKey(name)
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
        return try await runAndRelease(kv, key: key, name: name, instanceID: instanceID, logger: logger, body: body)
    }

    /// Like `withLock`, but when the lock is held it polls for up to `maxWait` instead of
    /// skipping. For short critical sections (the shared `latestSchedule` write) where
    /// dropping the work would lose data: a job that just spent a minute fetching should
    /// wait a few seconds for a peer's write to finish, not throw its result away.
    /// Returns nil only if the lock could not be taken within `maxWait` (or Redis failed).
    @discardableResult
    static func withLockWaiting<T>(
        _ kv: KeyValueStore,
        name: String,
        ttl: TimeInterval,
        instanceID: String,
        logger: Logger,
        maxWait: TimeInterval,
        retryInterval: TimeInterval = 0.25,
        body: () async throws -> T
    ) async throws -> T? {
        let key = lockKey(name)
        let deadline = Date().addingTimeInterval(maxWait)
        var attempts = 0
        while true {
            attempts += 1
            let claimed: Bool
            do {
                claimed = try await kv.setIfAbsent(key, value: instanceID, ttl: ttl)
            } catch {
                logger.warning("JobLock \(name) claim failed with Redis error: \(String(reflecting: error))")
                claimed = false
            }
            if claimed {
                if attempts > 1 {
                    logger.debug("JobLock \(name) acquired after \(attempts) attempts")
                }
                return try await runAndRelease(kv, key: key, name: name, instanceID: instanceID, logger: logger, body: body)
            }
            guard Date() < deadline else {
                logger.warning("JobLock \(name) not acquired within \(Int(maxWait))s — giving up this run")
                return nil
            }
            try await Task.sleep(nanoseconds: UInt64(retryInterval * 1_000_000_000))
        }
    }

    static func lockKey(_ name: String) -> String {
        RedisEndpoint.jobLock(name).getValue(isDebug: false).rawValue
    }

    private static func runAndRelease<T>(
        _ kv: KeyValueStore,
        key: String,
        name: String,
        instanceID: String,
        logger: Logger,
        body: () async throws -> T
    ) async throws -> T {
        let result: T
        do {
            result = try await body()
        } catch {
            await release(kv, key: key, name: name, instanceID: instanceID, logger: logger)
            throw error
        }
        await release(kv, key: key, name: name, instanceID: instanceID, logger: logger)
        return result
    }

    /// Releases the lock ONLY if this instance still owns it. If the body outran the TTL,
    /// the lock expired and another instance may have claimed it since — a blind DELETE
    /// would release *their* lock and let a third run start concurrently. Best-effort: on
    /// failure the TTL backstops the release.
    static func release(_ kv: KeyValueStore, key: String, name: String, instanceID: String, logger: Logger) async {
        do {
            if let cas = kv as? CompareAndDeleteStore {
                // Atomic GET+DEL in Redis (Lua).
                let deleted = try await cas.deleteIfValue(key, equals: instanceID)
                if !deleted {
                    logger.warning("JobLock \(name) expired before release (body outran ttl) — not deleting another owner's lock")
                }
            } else if try await kv.getString(key) == instanceID {
                // Non-atomic fallback for stores without scripting (test fakes).
                _ = try await kv.delete([key])
            } else {
                logger.warning("JobLock \(name) expired before release (body outran ttl) — not deleting another owner's lock")
            }
        } catch {
            logger.debug("JobLock \(name) release failed (TTL will expire it): \(error)")
        }
    }
}
