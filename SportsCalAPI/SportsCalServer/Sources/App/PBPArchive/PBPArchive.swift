//
//  PBPArchive.swift
//  SportsCalServer
//
//  Durable, disk-backed archive of finalized play-by-play data for NBA / NFL / NHL / MLB.
//
//  Design rationale
//  ----------------
//  Redis handles the hot path: live in-progress games overwrite `PBP-{id}` keys every :15 tick.
//  Once a game goes `isFinal`, the row is copied into this SQLite archive (disk-bounded, indexed)
//  and dropped from Redis. The `/plays/:eventID` route falls through Redis → SQLite on miss.
//
//  iOS clients carry TheSportsDB event IDs after the schedule merge; historical/backfill games
//  that never matched a TSDB entry are keyed by ESPN ID only. The `lookup` query searches both
//  columns so clients don't need to care which is which.
//

import Foundation
import NIOCore
import NIOPosix
import SQLiteNIO
import SportsCalModel
import Logging

/// Serialized, actor-isolated access to a single SQLite connection backing the PBP archive.
actor PBPArchive {
    private let logger = Logger(label: "com.sportscal.pbp-archive")
    private let connection: SQLiteConnection

    /// Opens (or creates) the SQLite file and runs migrations.
    /// Call once at server boot and retain the returned instance on `Application.storage`.
    static func bootstrap(path: String) async throws -> PBPArchive {
        let connection = try await SQLiteConnection.open(storage: .file(path: path))
        let archive = PBPArchive(connection: connection)
        try await archive.migrate()
        return archive
    }

    private init(connection: SQLiteConnection) {
        self.connection = connection
    }

    func close() async {
        try? await connection.close()
    }

    // MARK: - Schema

    private func migrate() async throws {
        // WAL mode gives us concurrent readers + a single writer without blocking the live loop.
        _ = try await connection.query("PRAGMA journal_mode=WAL").get()
        _ = try await connection.query("PRAGMA synchronous=NORMAL").get()
        _ = try await connection.query("""
            CREATE TABLE IF NOT EXISTS pbp_archive (
                espn_event_id TEXT PRIMARY KEY,
                tsdb_event_id TEXT,
                sport TEXT NOT NULL,
                league TEXT NOT NULL,
                last_play_id TEXT,
                is_final INTEGER NOT NULL,
                fetched_at INTEGER NOT NULL,
                plays_json BLOB NOT NULL
            )
        """).get()
        _ = try await connection.query("""
            CREATE INDEX IF NOT EXISTS idx_pbp_archive_tsdb ON pbp_archive(tsdb_event_id)
        """).get()
        _ = try await connection.query("""
            CREATE INDEX IF NOT EXISTS idx_pbp_archive_fetched ON pbp_archive(fetched_at)
        """).get()
        logger.info("PBP archive ready", metadata: ["path": "\(connection)"])
    }

    // MARK: - Write

    /// Inserts or updates the archive row for a game. Idempotent on `espn_event_id`.
    func upsert(
        cached: CachedPlays,
        espnEventID: String,
        tsdbEventID: String?,
        sport: String,
        league: String
    ) async throws {
        let playsData = try JSONEncoder().encode(cached.plays)
        var buffer = ByteBufferAllocator().buffer(capacity: playsData.count)
        buffer.writeBytes(playsData)

        let binds: [SQLiteData] = [
            .text(espnEventID),
            tsdbEventID.map(SQLiteData.text) ?? .null,
            .text(sport),
            .text(league),
            cached.lastPlayId.isEmpty ? .null : .text(cached.lastPlayId),
            .integer(cached.isFinal ? 1 : 0),
            .integer(Int(cached.fetchedAt.timeIntervalSince1970)),
            .blob(buffer)
        ]

        _ = try await connection.query("""
            INSERT INTO pbp_archive
                (espn_event_id, tsdb_event_id, sport, league, last_play_id, is_final, fetched_at, plays_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(espn_event_id) DO UPDATE SET
                tsdb_event_id = excluded.tsdb_event_id,
                sport = excluded.sport,
                league = excluded.league,
                last_play_id = excluded.last_play_id,
                is_final = excluded.is_final,
                fetched_at = excluded.fetched_at,
                plays_json = excluded.plays_json
        """, binds).get()
    }

    // MARK: - Read

    /// Looks up a game by either ESPN or TSDB event ID. Returns the archived `CachedPlays`
    /// or nil if no row matches.
    func lookup(eventID: String) async throws -> CachedPlays? {
        let rows = try await connection.query("""
            SELECT espn_event_id, tsdb_event_id, last_play_id, is_final, fetched_at, plays_json
            FROM pbp_archive
            WHERE espn_event_id = ? OR tsdb_event_id = ?
            LIMIT 1
        """, [.text(eventID), .text(eventID)]).get()
        guard let row = rows.first else { return nil }
        return try decodeRow(row, clientEventID: eventID)
    }

    /// Returns a small summary of the archive — used by the admin dashboard and health checks.
    func stats() async throws -> ArchiveStats {
        let rows = try await connection.query("""
            SELECT sport, COUNT(*) as count
            FROM pbp_archive
            WHERE is_final = 1
            GROUP BY sport
        """).get()
        var counts: [String: Int] = [:]
        for row in rows {
            if let sport = row.column("sport")?.string,
               let count = row.column("count")?.integer {
                counts[sport] = count
            }
        }
        let totalRow = try await connection.query("SELECT COUNT(*) as total FROM pbp_archive").get().first
        let total = totalRow?.column("total")?.integer ?? 0
        return ArchiveStats(totalRows: total, finalsBySport: counts)
    }

    struct ArchiveStats: Codable {
        let totalRows: Int
        let finalsBySport: [String: Int]
    }

    // MARK: - Row decoding

    private func decodeRow(_ row: SQLiteRow, clientEventID: String) throws -> CachedPlays {
        guard let playsBuffer = row.column("plays_json")?.blob else {
            throw PBPArchiveError.missingColumn("plays_json")
        }
        let playsData = Data(playsBuffer.readableBytesView)
        let plays = try JSONDecoder().decode([Play].self, from: playsData)

        let lastPlayID = row.column("last_play_id")?.string ?? ""
        let isFinal = (row.column("is_final")?.integer ?? 0) != 0
        let fetchedSeconds = row.column("fetched_at")?.integer ?? 0

        return CachedPlays(
            eventID: clientEventID,
            lastPlayId: lastPlayID,
            plays: plays,
            isFinal: isFinal,
            fetchedAt: Date(timeIntervalSince1970: TimeInterval(fetchedSeconds))
        )
    }
}

enum PBPArchiveError: Error {
    case missingColumn(String)
}

// MARK: - Application storage key

import Vapor

struct PBPArchiveKey: StorageKey {
    typealias Value = PBPArchive
}

extension Application {
    /// The shared SQLite-backed play-by-play archive. `nil` before `configure.swift`
    /// has finished bootstrapping, or if the archive failed to open (check logs).
    var pbpArchive: PBPArchive? {
        get { self.storage[PBPArchiveKey.self] }
        set { self.storage[PBPArchiveKey.self] = newValue }
    }
}
