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
}

struct RedisKeyValueStore: KeyValueStore, @unchecked Sendable {
    let redis: any RedisClient

    func scanKeys(matching pattern: String) async throws -> [String] {
        let response = try await redis.send(command: "keys", with: [pattern.convertedToRESPValue()]).get()
        return response.array?.compactMap { $0.string } ?? []
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
