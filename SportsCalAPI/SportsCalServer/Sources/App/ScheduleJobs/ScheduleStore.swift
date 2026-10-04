//
//  ScheduleStore.swift
//
//  The one way to write `latestSchedule`. Six jobs read-modify-write the same ~12MB
//  blob (ScheduleUpdateJob, ESPNFetchJob, and the injuries / F1 / golf / World Cup
//  enrichment jobs); without coordination the last writer silently discarded every
//  change made after it read. `update` serialises the final step: take the shared
//  `schedule-write` JobLock, re-read the latest blob, apply this job's change, write.
//
//  Callers do their slow network fetching BEFORE calling `update`; the lock covers
//  only decode → apply → encode → write, so it is held for a second or two at most.
//

import Foundation
import Vapor
import Redis
import SportsCalModel
import Logging

enum ScheduleStore {
    static let lockName = "schedule-write"
    /// Generous for a 12MB decode + encode + SET; a crash pins the lock at most this long.
    static let lockTTL: TimeInterval = 60
    /// How long a writer waits for a peer's write before giving up this run.
    static let maxWait: TimeInterval = 45

    /// A schedule read together with the version it was read at. A writer that already
    /// decoded the schedule (ESPNFetchJob needs it to bridge IDs) passes this to `update`,
    /// which then skips the re-decode when nobody has written since.
    struct Snapshot {
        let schedule: LiveScore?
        let version: Int?
    }

    enum Outcome: Equatable {
        /// The transform produced a different schedule and it was written.
        case written
        /// The transform returned nil, or the same schedule — nothing to write.
        case unchanged
        /// The lock could not be taken within `maxWait`. Nothing was written; the caller
        /// should not mark its work as done so the next run retries.
        case lockTimeout
    }

    static func scheduleKey(isDebug: Bool) -> RedisKey {
        RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: isDebug)
    }

    static func versionKey(isDebug: Bool) -> RedisKey {
        RedisEndpoint.ESPN.scheduleVersion.getValue(isDebug: isDebug)
    }

    /// Reads the version FIRST, then the schedule: a write landing between the two leaves
    /// a newer schedule paired with an older version, which only costs a harmless re-read.
    static func read(app: Application, isDebug: Bool) async throws -> Snapshot {
        var version = try? await currentVersion(app: app, isDebug: isDebug)
        if version == nil {
            // Seed the counter so the basis can be reused even before the first write
            // through `update` (otherwise an unchanging schedule never gets a version).
            _ = try? await app.redis.setnx(versionKey(isDebug: isDebug), to: 0).get()
            version = try? await currentVersion(app: app, isDebug: isDebug)
        }
        let schedule = try await app.redis.get(scheduleKey(isDebug: isDebug), asJSON: LiveScore.self)
        return Snapshot(schedule: schedule, version: version)
    }

    /// Re-reads the latest schedule under the shared write lock, hands it to `transform`
    /// (nil when no schedule is cached), and writes the result if it changed.
    ///
    /// - Parameter basis: a snapshot the caller already decoded. Reused instead of
    ///   re-decoding when the version is unchanged.
    /// - Parameter transform: returns the schedule to write, or nil to write nothing.
    ///   Runs under the lock: keep it to pure computation and cheap cache reads.
    @discardableResult
    static func update(
        app: Application,
        isDebug: Bool,
        logger: Logger,
        writer: String,
        basis: Snapshot? = nil,
        transform: (LiveScore?) async throws -> LiveScore?
    ) async throws -> Outcome {
        let key = scheduleKey(isDebug: isDebug)
        let outcome: Outcome? = try await JobLock.withLockWaiting(
            app.kv,
            name: lockName,
            ttl: lockTTL,
            instanceID: app.instanceID,
            logger: logger,
            maxWait: maxWait
        ) {
            let current: LiveScore?
            let version = try? await currentVersion(app: app, isDebug: isDebug)
            // Reuse the caller's decode only if nobody wrote since (same version) and the
            // key wasn't deleted out from under it (admin cache flush doesn't bump it).
            let keyExists = ((try? await app.redis.exists(key).get()) ?? 0) > 0
            if let basis, let basisVersion = basis.version, basisVersion == version,
               (basis.schedule != nil) == keyExists {
                current = basis.schedule
            } else {
                current = try await app.redis.get(key, asJSON: LiveScore.self)
            }
            guard let updated = try await transform(current), updated != current else {
                return .unchanged
            }
            try await app.redis.set(key, toJSON: updated)
            _ = try? await app.redis.increment(versionKey(isDebug: isDebug)).get()
            return .written
        }
        guard let outcome else {
            logger.warning("Schedule write skipped — \(lockName) lock busy", metadata: ["writer": "\(writer)"])
            return .lockTimeout
        }
        return outcome
    }

    private static func currentVersion(app: Application, isDebug: Bool) async throws -> Int? {
        try await app.redis.get(versionKey(isDebug: isDebug), as: Int.self).get()
    }
}
