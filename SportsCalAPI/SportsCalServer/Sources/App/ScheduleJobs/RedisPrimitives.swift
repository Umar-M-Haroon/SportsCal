//
//  RedisPrimitives.swift
//
//  Optional Redis capabilities beyond the core `KeyValueStore` protocol: atomic
//  compare-and-delete (JobLock release), sets (APNS registration index) and hashes
//  (ESPN event map). They are separate protocols so the in-memory test fakes, which
//  don't implement them, keep compiling — callers cast (`kv as? RedisSetStore`) and
//  fall back to the plain-KV behaviour when a store lacks the capability.
//

import Foundation
import Redis
@preconcurrency import RediStack

/// Atomic "delete this key only if it still holds my value".
protocol CompareAndDeleteStore: Sendable {
    /// Deletes `key` iff its current value equals `value`. Returns true if it deleted.
    func deleteIfValue(_ key: String, equals value: String) async throws -> Bool
}

/// Redis SET operations.
protocol RedisSetStore: Sendable {
    func setAdd(_ key: String, members: [String]) async throws
    func setRemove(_ key: String, members: [String]) async throws
    func setMembers(_ key: String) async throws -> [String]
}

/// Redis HASH operations (string fields and values).
protocol RedisHashStore: Sendable {
    func hashGet(_ key: String, field: String) async throws -> String?
    func hashSet(_ key: String, fields: [String: String]) async throws
    func hashLength(_ key: String) async throws -> Int
}

extension RedisKeyValueStore: CompareAndDeleteStore, RedisSetStore, RedisHashStore {
    /// GET + DEL in one Lua script so no other client can slip a SET between them.
    static let compareAndDeleteScript = """
    if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end
    """

    func deleteIfValue(_ key: String, equals value: String) async throws -> Bool {
        let response = try await redis.send(command: "EVAL", with: [
            Self.compareAndDeleteScript.convertedToRESPValue(),
            1.convertedToRESPValue(),
            key.convertedToRESPValue(),
            value.convertedToRESPValue(),
        ]).get()
        return (response.int ?? 0) == 1
    }

    func setAdd(_ key: String, members: [String]) async throws {
        guard !members.isEmpty else { return }
        for chunk in members.chunked(into: 500) {
            _ = try await redis.send(
                command: "SADD",
                with: [key.convertedToRESPValue()] + chunk.map { $0.convertedToRESPValue() }
            ).get()
        }
    }

    func setRemove(_ key: String, members: [String]) async throws {
        guard !members.isEmpty else { return }
        for chunk in members.chunked(into: 500) {
            _ = try await redis.send(
                command: "SREM",
                with: [key.convertedToRESPValue()] + chunk.map { $0.convertedToRESPValue() }
            ).get()
        }
    }

    /// SSCAN rather than SMEMBERS so a large index never blocks Redis in one call.
    func setMembers(_ key: String) async throws -> [String] {
        var cursor = "0"
        var found = Set<String>()
        repeat {
            let response = try await redis.send(command: "SSCAN", with: [
                key.convertedToRESPValue(),
                cursor.convertedToRESPValue(),
                "COUNT".convertedToRESPValue(),
                "1000".convertedToRESPValue(),
            ]).get()
            guard let top = response.array, top.count == 2,
                  let next = top[0].string else { break }
            for element in top[1].array ?? [] {
                if let member = element.string { found.insert(member) }
            }
            cursor = next
        } while cursor != "0"
        return Array(found)
    }

    func hashGet(_ key: String, field: String) async throws -> String? {
        let response = try await redis.send(command: "HGET", with: [
            key.convertedToRESPValue(), field.convertedToRESPValue(),
        ]).get()
        return response.string
    }

    func hashSet(_ key: String, fields: [String: String]) async throws {
        guard !fields.isEmpty else { return }
        var args: [RESPValue] = [key.convertedToRESPValue()]
        for (field, value) in fields {
            args.append(field.convertedToRESPValue())
            args.append(value.convertedToRESPValue())
        }
        _ = try await redis.send(command: "HSET", with: args).get()
    }

    func hashLength(_ key: String) async throws -> Int {
        let response = try await redis.send(command: "HLEN", with: [key.convertedToRESPValue()]).get()
        return response.int ?? 0
    }
}
