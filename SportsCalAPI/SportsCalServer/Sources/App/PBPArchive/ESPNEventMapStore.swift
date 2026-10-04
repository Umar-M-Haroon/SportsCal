//
//  ESPNEventMapStore.swift
//  SportsCalServer
//
//  TheSportsDB event ID → ESPN event (ID + sport/league slugs), used by `/plays` to
//  fetch on demand. Stored as a Redis HASH (`ESPN-Event-Map-Hash`), one field per
//  event, so a lookup is a single HGET instead of decoding the whole map.
//
//  It used to be one JSON blob (`ESPN-Event-Map`) that only ever grew and was fully
//  decoded on every `/plays` miss. Migration: the first `record` on a hash-capable
//  store copies the legacy blob into the hash and deletes it; until then `lookup`
//  falls back to the blob, and afterwards that fallback is a cheap GET of a missing key.
//

import Foundation
import Logging
import SportsCalModel

enum ESPNEventMapStore {
    /// The hash is cleared when it grows past this. Entries are re-recorded every tick
    /// for games that are live or just finished, so a reset only forgets older games —
    /// whose plays are in the SQLite archive by then.
    static let maxEntries = 50_000

    static func hashKey(isDebug: Bool) -> String {
        RedisEndpoint.ESPN.espnEventMapHash.getValue(isDebug: isDebug).rawValue
    }

    static func legacyKey(isDebug: Bool) -> String {
        RedisEndpoint.ESPN.espnEventMap.getValue(isDebug: isDebug).rawValue
    }

    static func lookup(eventID: String, kv: KeyValueStore, isDebug: Bool) async -> ESPNEventMapping? {
        if let hash = kv as? RedisHashStore,
           let raw = try? await hash.hashGet(hashKey(isDebug: isDebug), field: eventID),
           let mapping = decode(raw) {
            return mapping
        }
        // Legacy blob: present only until the first migrating `record`.
        let legacy = try? await kv.getJSON(legacyKey(isDebug: isDebug), as: [String: ESPNEventMapping].self)
        return legacy?[eventID]
    }

    static func record(_ additions: [String: ESPNEventMapping], kv: KeyValueStore, isDebug: Bool, logger: Logger) async {
        guard !additions.isEmpty else { return }
        let legacyKey = legacyKey(isDebug: isDebug)

        guard let hash = kv as? RedisHashStore else {
            // Stores without hash support (test fakes) keep the legacy blob format.
            var existing = (try? await kv.getJSON(legacyKey, as: [String: ESPNEventMapping].self)) ?? [:]
            for (k, v) in additions { existing[k] = v }
            try? await kv.setJSON(legacyKey, value: existing, ttl: nil)
            return
        }

        let hashKey = hashKey(isDebug: isDebug)
        do {
            // One-time migration of the legacy blob.
            if try await kv.exists(legacyKey) {
                let legacy = (try? await kv.getJSON(legacyKey, as: [String: ESPNEventMapping].self)) ?? [:]
                try await write(legacy, to: hashKey, hash: hash)
                _ = try await kv.delete([legacyKey])
                logger.info("Migrated ESPN-Event-Map blob into hash", metadata: ["entries": "\(legacy.count)"])
            }
            try await write(additions, to: hashKey, hash: hash)
            let count = try await hash.hashLength(hashKey)
            if count > maxEntries {
                _ = try await kv.delete([hashKey])
                try await write(additions, to: hashKey, hash: hash)
                logger.info("ESPN-Event-Map hash pruned", metadata: ["previousEntries": "\(count)"])
            }
        } catch {
            logger.warning("ESPN-Event-Map update failed: \(error)")
        }
    }

    private static func write(_ mappings: [String: ESPNEventMapping], to key: String, hash: RedisHashStore) async throws {
        guard !mappings.isEmpty else { return }
        let encoder = JSONEncoder()
        var fields: [String: String] = [:]
        for (eventID, mapping) in mappings {
            guard let data = try? encoder.encode(mapping), let raw = String(data: data, encoding: .utf8) else { continue }
            fields[eventID] = raw
            if fields.count >= 500 {
                try await hash.hashSet(key, fields: fields)
                fields.removeAll(keepingCapacity: true)
            }
        }
        try await hash.hashSet(key, fields: fields)
    }

    private static func decode(_ raw: String) -> ESPNEventMapping? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ESPNEventMapping.self, from: data)
    }
}
