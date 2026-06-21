import Foundation
import Vapor
import Redis
@preconcurrency import RediStack

/// Thin abstraction over the subset of Redis we actually use, so tests can swap in
/// an in-memory fake without booting a real Redis server. String keys only — keep
/// the RediStack `RedisKey` wrapper at the production boundary.
protocol KeyValueStore: Sendable {
    func scanKeys(matching pattern: String) async throws -> [String]
    func getString(_ key: String) async throws -> String?
    func mget(_ keys: [String]) async throws -> [String?]
    func getJSON<T: Decodable>(_ key: String, as type: T.Type) async throws -> T?
    func setString(_ key: String, value: String, ttl: TimeInterval?) async throws
    func setJSON<T: Encodable>(_ key: String, value: T, ttl: TimeInterval?) async throws
    @discardableResult
    func delete(_ keys: [String]) async throws -> Int
    func exists(_ key: String) async throws -> Bool
    /// Refreshes the TTL on an existing key. Returns true if the key existed and the
    /// TTL was updated, false if the key was missing. Used to slide the Live Activity
    /// registration TTL forward on every successful APNS update.
    @discardableResult
    func expire(_ key: String, ttl: TimeInterval) async throws -> Bool
    /// Atomic `SET key value NX EX ttl`. Returns true iff this caller created the key
    /// (i.e., won the claim). False if a previous caller already holds the key.
    /// Foundation of every dedup / leader-election path: the read-then-write pattern
    /// has a TOCTOU window that two server instances race into.
    func setIfAbsent(_ key: String, value: String, ttl: TimeInterval) async throws -> Bool
    /// Atomic `INCR` returning the new counter value, guaranteeing the key carries
    /// a TTL (armed via `EXPIRE … NX`) so a counter can never get stuck without
    /// one — the exact failure that bricked the write rate-limit. Used by
    /// `RedisTelemetry` for persisted per-day counters.
    @discardableResult
    func increment(_ key: String, ttl: TimeInterval) async throws -> Int
}

struct RedisKeyValueStore: KeyValueStore, @unchecked Sendable {
    let redis: any RedisClient

    func scanKeys(matching pattern: String) async throws -> [String] {
        // SCAN cursor loop instead of KEYS: KEYS is O(N) and blocks the entire
        // Redis server (every other client stalls) — unacceptable at device scale.
        // SCAN is incremental/non-blocking; it may return duplicates, so dedup.
        var cursor = "0"
        var found = Set<String>()
        repeat {
            let response = try await redis.send(command: "SCAN", with: [
                cursor.convertedToRESPValue(),
                "MATCH".convertedToRESPValue(),
                pattern.convertedToRESPValue(),
                "COUNT".convertedToRESPValue(),
                "500".convertedToRESPValue()
            ]).get()
            guard let top = response.array, top.count == 2,
                  let nextCursor = top[0].string else { break }
            for element in top[1].array ?? [] {
                if let key = element.string { found.insert(key) }
            }
            cursor = nextCursor
        } while cursor != "0"
        return Array(found)
    }

    func getString(_ key: String) async throws -> String? {
        try await redis.get(RedisKey(key), as: String.self).get()
    }

    func mget(_ keys: [String]) async throws -> [String?] {
        let redisKeys = keys.map { RedisKey($0) }
        let values = try await redis.mget(redisKeys).get()
        return values.map { $0.string }
    }

    func getJSON<T: Decodable>(_ key: String, as type: T.Type) async throws -> T? {
        try await redis.get(RedisKey(key), asJSON: type)
    }

    func setString(_ key: String, value: String, ttl: TimeInterval?) async throws {
        if let ttl {
            try await redis.setex(RedisKey(key), to: value, expirationInSeconds: Int(ttl)).get()
        } else {
            try await redis.set(RedisKey(key), to: value).get()
        }
    }

    func setJSON<T: Encodable>(_ key: String, value: T, ttl: TimeInterval?) async throws {
        if let ttl {
            try await redis.setex(RedisKey(key), toJSON: value, expirationInSeconds: Int(ttl)).get()
        } else {
            try await redis.set(RedisKey(key), toJSON: value).get()
        }
    }

    @discardableResult
    func delete(_ keys: [String]) async throws -> Int {
        guard !keys.isEmpty else { return 0 }
        let redisKeys = keys.map { RedisKey($0) }
        return try await redis.delete(redisKeys).get()
    }

    func exists(_ key: String) async throws -> Bool {
        let count = try await redis.exists(RedisKey(key)).get()
        return count > 0
    }

    @discardableResult
    func expire(_ key: String, ttl: TimeInterval) async throws -> Bool {
        let response = try await redis.send(
            command: "EXPIRE",
            with: [key.convertedToRESPValue(), Int(ttl).convertedToRESPValue()]
        ).get()
        return (response.int ?? 0) == 1
    }

    func setIfAbsent(_ key: String, value: String, ttl: TimeInterval) async throws -> Bool {
        let response = try await redis.send(
            command: "SET",
            with: [
                key.convertedToRESPValue(),
                value.convertedToRESPValue(),
                "NX".convertedToRESPValue(),
                "EX".convertedToRESPValue(),
                Int(ttl).convertedToRESPValue()
            ]
        ).get()
        // Redis returns simple string "OK" when SET NX succeeds, null bulk reply when
        // the key already exists. Anything else is an unexpected response.
        return response.string == "OK"
    }

    @discardableResult
    func increment(_ key: String, ttl: TimeInterval) async throws -> Int {
        let count = try await redis.increment(RedisKey(key)).get()
        // `EXPIRE … NX` arms the TTL only when the key has none, so the first INCR
        // sets the window and any key that ever lost its TTL self-heals on the next
        // hit. Best-effort: the count is already authoritative. Requires Redis 7+.
        _ = try? await redis.send(
            command: "EXPIRE",
            with: [
                key.convertedToRESPValue(),
                Int(ttl).convertedToRESPValue(),
                "NX".convertedToRESPValue()
            ]
        ).get()
        return count
    }
}

struct KeyValueStoreKey: StorageKey {
    typealias Value = KeyValueStore
}

extension Application {
    var kv: KeyValueStore {
        get { storage[KeyValueStoreKey.self] ?? RedisKeyValueStore(redis: redis) }
        set { storage[KeyValueStoreKey.self] = newValue }
    }
}

extension Request {
    var kv: KeyValueStore { application.kv }
}
