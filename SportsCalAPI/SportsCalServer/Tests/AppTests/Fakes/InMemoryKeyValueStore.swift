import Foundation
@testable import App

/// Dictionary-backed KeyValueStore with TTL semantics driven by an injected clock.
/// Semantics match what the job code expects from Redis, not full RediStack parity —
/// SCAN cursor quirks and pipeline ordering are deliberately out of scope here, and
/// are covered by the nightly Docker-Redis smoke workflow instead.
final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private struct Entry {
        var value: String
        /// Absolute expiration time. `nil` means no TTL.
        var expiresAt: Date?
    }

    private let lock = NSLock()
    private var storage: [String: Entry] = [:]
    private let clock: AppClock
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(clock: AppClock = SystemClock()) {
        self.clock = clock
    }

    // MARK: - Test helpers

    var rawSnapshot: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredLocked()
        return storage.mapValues { $0.value }
    }

    /// Returns the TTL remaining for a key (in seconds) or nil if the key has
    /// no TTL or does not exist. Useful for asserting setex calls wrote the
    /// expected expiration.
    func ttl(_ key: String) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredLocked()
        guard let entry = storage[key], let exp = entry.expiresAt else { return nil }
        return exp.timeIntervalSince(clock.now)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }

    // MARK: - Protocol

    func scanKeys(matching pattern: String) async throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredLocked()
        return storage.keys.filter { Self.glob(pattern: pattern, matches: $0) }.sorted()
    }

    func getString(_ key: String) async throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredLocked()
        return storage[key]?.value
    }

    func mget(_ keys: [String]) async throws -> [String?] {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredLocked()
        return keys.map { storage[$0]?.value }
    }

    func getJSON<T: Decodable>(_ key: String, as type: T.Type) async throws -> T? {
        guard let raw = try await getString(key),
              let data = raw.data(using: .utf8) else { return nil }
        return try decoder.decode(type, from: data)
    }

    func setString(_ key: String, value: String, ttl: TimeInterval?) async throws {
        lock.lock()
        defer { lock.unlock() }
        let expiresAt = ttl.map { clock.now.addingTimeInterval($0) }
        storage[key] = Entry(value: value, expiresAt: expiresAt)
    }

    func setJSON<T: Encodable>(_ key: String, value: T, ttl: TimeInterval?) async throws {
        let data = try encoder.encode(value)
        let raw = String(data: data, encoding: .utf8) ?? ""
        try await setString(key, value: raw, ttl: ttl)
    }

    @discardableResult
    func delete(_ keys: [String]) async throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        var count = 0
        for key in keys where storage.removeValue(forKey: key) != nil { count += 1 }
        return count
    }

    func exists(_ key: String) async throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredLocked()
        return storage[key] != nil
    }

    @discardableResult
    func expire(_ key: String, ttl: TimeInterval) async throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredLocked()
        guard var entry = storage[key] else { return false }
        entry.expiresAt = clock.now.addingTimeInterval(ttl)
        storage[key] = entry
        return true
    }

    func setIfAbsent(_ key: String, value: String, ttl: TimeInterval) async throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredLocked()
        guard storage[key] == nil else { return false }
        storage[key] = Entry(value: value, expiresAt: clock.now.addingTimeInterval(ttl))
        return true
    }

    // MARK: - Internals

    private func purgeExpiredLocked() {
        let now = clock.now
        // Collect-then-remove — mutating a dictionary during iteration is UB.
        let expired = storage.compactMap { key, entry -> String? in
            if let exp = entry.expiresAt, exp <= now { return key }
            return nil
        }
        for key in expired { storage.removeValue(forKey: key) }
    }

    /// Minimal Redis glob: supports `*` only (our call sites use `APNS-*` style
    /// patterns exclusively). Extend if we ever rely on `?` or `[...]`.
    static func glob(pattern: String, matches key: String) -> Bool {
        guard pattern.contains("*") else { return pattern == key }
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        var remaining = key[...]
        for (i, part) in parts.enumerated() {
            if part.isEmpty { continue }
            if i == 0 {
                guard remaining.hasPrefix(part) else { return false }
                remaining = remaining.dropFirst(part.count)
            } else if i == parts.count - 1 {
                guard remaining.hasSuffix(part) else { return false }
            } else {
                guard let range = remaining.range(of: part) else { return false }
                remaining = remaining[range.upperBound...]
            }
        }
        return true
    }
}
