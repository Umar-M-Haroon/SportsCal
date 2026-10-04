import Foundation
@testable import App

/// Wraps `InMemoryKeyValueStore` and adds the optional Redis capabilities
/// (compare-and-delete, sets, hashes) so tests can drive the code paths production
/// takes against real Redis. Sets and hashes are stored JSON-encoded in the wrapped
/// store's string values, so TTLs and `rawSnapshot` behave as for any other key.
final class RedisCapableKV: KeyValueStore, CompareAndDeleteStore, RedisSetStore, RedisHashStore, @unchecked Sendable {
    let inner: InMemoryKeyValueStore

    init(inner: InMemoryKeyValueStore = InMemoryKeyValueStore()) {
        self.inner = inner
    }

    // MARK: KeyValueStore (forwarded)

    func scanKeys(matching pattern: String) async throws -> [String] { try await inner.scanKeys(matching: pattern) }
    func getString(_ key: String) async throws -> String? { try await inner.getString(key) }
    func mget(_ keys: [String]) async throws -> [String?] { try await inner.mget(keys) }
    func getJSON<T: Decodable>(_ key: String, as type: T.Type) async throws -> T? { try await inner.getJSON(key, as: type) }
    func setString(_ key: String, value: String, ttl: TimeInterval?) async throws { try await inner.setString(key, value: value, ttl: ttl) }
    func setJSON<T: Encodable>(_ key: String, value: T, ttl: TimeInterval?) async throws { try await inner.setJSON(key, value: value, ttl: ttl) }
    func delete(_ keys: [String]) async throws -> Int { try await inner.delete(keys) }
    func exists(_ key: String) async throws -> Bool { try await inner.exists(key) }
    func expire(_ key: String, ttl: TimeInterval) async throws -> Bool { try await inner.expire(key, ttl: ttl) }
    func setIfAbsent(_ key: String, value: String, ttl: TimeInterval) async throws -> Bool { try await inner.setIfAbsent(key, value: value, ttl: ttl) }
    func increment(_ key: String, ttl: TimeInterval) async throws -> Int { try await inner.increment(key, ttl: ttl) }
    func hllAdd(_ key: String, element: String, ttl: TimeInterval) async throws { try await inner.hllAdd(key, element: element, ttl: ttl) }
    func hllCount(_ keys: [String]) async throws -> Int { try await inner.hllCount(keys) }

    // MARK: CompareAndDeleteStore

    var compareAndDeleteCalls = 0

    func deleteIfValue(_ key: String, equals value: String) async throws -> Bool {
        compareAndDeleteCalls += 1
        guard try await inner.getString(key) == value else { return false }
        return try await inner.delete([key]) == 1
    }

    // MARK: RedisSetStore

    func setAdd(_ key: String, members: [String]) async throws {
        var set = Set((try await inner.getJSON(key, as: [String].self)) ?? [])
        set.formUnion(members)
        try await inner.setJSON(key, value: set.sorted(), ttl: nil)
    }

    func setRemove(_ key: String, members: [String]) async throws {
        var set = Set((try await inner.getJSON(key, as: [String].self)) ?? [])
        set.subtract(members)
        if set.isEmpty {
            _ = try await inner.delete([key])
        } else {
            try await inner.setJSON(key, value: set.sorted(), ttl: nil)
        }
    }

    func setMembers(_ key: String) async throws -> [String] {
        (try await inner.getJSON(key, as: [String].self)) ?? []
    }

    // MARK: RedisHashStore

    func hashGet(_ key: String, field: String) async throws -> String? {
        (try await inner.getJSON(key, as: [String: String].self))?[field]
    }

    func hashSet(_ key: String, fields: [String: String]) async throws {
        var hash = (try await inner.getJSON(key, as: [String: String].self)) ?? [:]
        for (k, v) in fields { hash[k] = v }
        try await inner.setJSON(key, value: hash, ttl: nil)
    }

    func hashLength(_ key: String) async throws -> Int {
        (try await inner.getJSON(key, as: [String: String].self))?.count ?? 0
    }
}
