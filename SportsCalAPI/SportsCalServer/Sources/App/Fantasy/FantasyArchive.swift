//
//  FantasyArchive.swift
//  SportsCalServer
//
//  Durable game log for fantasy: one row per player per game (`FantasyPlayerLine`),
//  upserted on every live summary fetch and kept after the final. Slates read a week
//  out of it; season averages are the mean of a player's final rows.
//
//  Its own SQLite file (`fantasy.sqlite`, override `FANTASY_ARCHIVE_PATH`) beside the
//  play-by-play archive: the two have nothing to join, and keeping them apart means a
//  fantasy migration can never lock the archive the `/plays` route reads.
//

import Foundation
import NIOCore
import SQLiteNIO
import SportsCalModel
import Redis
import Vapor

actor FantasyArchive {
    private let connection: SQLiteConnection

    static func bootstrap(path: String) async throws -> FantasyArchive {
        let connection = try await SQLiteConnection.open(storage: .file(path: path))
        let archive = FantasyArchive(connection: connection)
        try await archive.migrate()
        return archive
    }

    /// In-memory, for tests.
    static func inMemory() async throws -> FantasyArchive {
        let connection = try await SQLiteConnection.open(storage: .memory)
        let archive = FantasyArchive(connection: connection)
        try await archive.migrate()
        return archive
    }

    private init(connection: SQLiteConnection) {
        self.connection = connection
    }

    func close() async {
        try? await connection.close()
    }

    nonisolated func closeFuture() -> EventLoopFuture<Void> {
        connection.close()
    }

    private func migrate() async throws {
        _ = try await connection.query("PRAGMA journal_mode=WAL").get()
        _ = try await connection.query("PRAGMA synchronous=NORMAL").get()
        _ = try await connection.query("""
            CREATE TABLE IF NOT EXISTS fantasy_lines (
                event_id TEXT NOT NULL,
                athlete_id TEXT NOT NULL,
                tsdb_event_id TEXT,
                league TEXT NOT NULL,
                season INTEGER NOT NULL,
                season_type INTEGER NOT NULL,
                week INTEGER,
                game_date INTEGER,
                is_final INTEGER NOT NULL,
                line_json BLOB NOT NULL,
                PRIMARY KEY (event_id, athlete_id)
            )
        """).get()
        _ = try await connection.query("""
            CREATE INDEX IF NOT EXISTS idx_fantasy_slate ON fantasy_lines(league, season, season_type, week)
        """).get()
        _ = try await connection.query("""
            CREATE INDEX IF NOT EXISTS idx_fantasy_athlete ON fantasy_lines(league, season, athlete_id)
        """).get()
        _ = try await connection.query("""
            CREATE INDEX IF NOT EXISTS idx_fantasy_tsdb ON fantasy_lines(tsdb_event_id)
        """).get()
    }

    struct Slot: Equatable, Sendable {
        var league: String
        var season: Int
        var seasonType: Int
        var week: Int?
    }

    // MARK: Write

    /// The last write in flight. Writes chain on it: the actor alone can't keep two
    /// transactions apart, since another call runs whenever this one awaits.
    private var writeTail: Task<Void, Never>?

    /// Replaces a game's lines. Players who drop out of a live box (a correction) go too.
    func replace(eventID: String, slot: Slot, isFinal: Bool, lines: [FantasyPlayerLine]) async throws {
        guard !lines.isEmpty else { return }
        let previous = writeTail
        let write = Task { () async throws -> Void in
            await previous?.value
            try await self.performReplace(eventID: eventID, slot: slot, isFinal: isFinal, lines: lines)
        }
        writeTail = Task { _ = await write.result }
        try await write.value
    }

    private func performReplace(eventID: String, slot: Slot, isFinal: Bool, lines: [FantasyPlayerLine]) async throws {
        let encoder = JSONEncoder()
        _ = try await connection.query("BEGIN IMMEDIATE").get()
        do {
            _ = try await connection.query("DELETE FROM fantasy_lines WHERE event_id = ?", [.text(eventID)]).get()
            for line in lines {
                let data = try encoder.encode(line)
                var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                buffer.writeBytes(data)
                _ = try await connection.query("""
                    INSERT INTO fantasy_lines
                        (event_id, athlete_id, tsdb_event_id, league, season, season_type, week, game_date, is_final, line_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [
                    .text(eventID),
                    .text(line.athleteID),
                    line.tsdbEventID.map(SQLiteData.text) ?? .null,
                    .text(slot.league),
                    .integer(slot.season),
                    .integer(slot.seasonType),
                    slot.week.map(SQLiteData.integer) ?? .null,
                    line.gameDate.map { .integer(Int($0.timeIntervalSince1970)) } ?? .null,
                    .integer(isFinal ? 1 : 0),
                    .blob(buffer),
                ]).get()
            }
            _ = try await connection.query("COMMIT").get()
        } catch {
            _ = try? await connection.query("ROLLBACK").get()
            throw error
        }
    }

    // MARK: Read

    func lines(slot: Slot) async throws -> [FantasyPlayerLine] {
        var sql = "SELECT line_json FROM fantasy_lines WHERE league = ? AND season = ? AND season_type = ?"
        var binds: [SQLiteData] = [.text(slot.league), .integer(slot.season), .integer(slot.seasonType)]
        if let week = slot.week {
            sql += " AND week = ?"
            binds.append(.integer(week))
        }
        return try decode(try await connection.query(sql, binds).get())
    }

    /// One game's lines, by ESPN or TheSportsDB event ID.
    func lines(eventID: String) async throws -> [FantasyPlayerLine] {
        try decode(try await connection.query(
            "SELECT line_json FROM fantasy_lines WHERE event_id = ? OR tsdb_event_id = ?",
            [.text(eventID), .text(eventID)]
        ).get())
    }

    /// Final games already logged for a season, so the backfill skips them.
    func finalEventIDs(league: String, season: Int, seasonType: Int) async throws -> Set<String> {
        let rows = try await connection.query("""
            SELECT DISTINCT event_id FROM fantasy_lines
            WHERE league = ? AND season = ? AND season_type = ? AND is_final = 1
        """, [.text(league), .integer(season), .integer(seasonType)]).get()
        return Set(rows.compactMap { $0.column("event_id")?.string })
    }

    /// Weeks with any logged game, oldest first.
    func weeks(league: String, season: Int, seasonType: Int) async throws -> [Int] {
        let rows = try await connection.query("""
            SELECT DISTINCT week FROM fantasy_lines
            WHERE league = ? AND season = ? AND season_type = ? AND week IS NOT NULL ORDER BY week
        """, [.text(league), .integer(season), .integer(seasonType)]).get()
        return rows.compactMap { $0.column("week")?.integer }
    }

    struct Average: Equatable, Sendable {
        var stats: [String: Double]
        var games: Int
    }

    /// Per-game averages over each athlete's final games this season (regular season
    /// and playoffs alike), leaving out `excludingEvents` — the slate's own games, so a
    /// player's big day isn't measured against itself.
    func seasonAverages(
        league: String, season: Int, athleteIDs: Set<String>, excludingEvents: Set<String>
    ) async throws -> [String: Average] {
        guard !athleteIDs.isEmpty else { return [:] }
        var totals: [String: [String: Double]] = [:]
        var games: [String: Int] = [:]
        let decoder = JSONDecoder()
        // SQLite caps bound parameters (999 on older builds); chunk the IN list.
        let ids = Array(athleteIDs)
        for start in stride(from: 0, to: ids.count, by: 400) {
            let chunk = ids[start..<min(start + 400, ids.count)]
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let rows = try await connection.query("""
                SELECT event_id, athlete_id, line_json FROM fantasy_lines
                WHERE league = ? AND season = ? AND is_final = 1 AND athlete_id IN (\(placeholders))
            """, [.text(league), .integer(season)] + chunk.map(SQLiteData.text)).get()
            for row in rows {
                guard let eventID = row.column("event_id")?.string, !excludingEvents.contains(eventID),
                      let athleteID = row.column("athlete_id")?.string,
                      let blob = row.column("line_json")?.blob,
                      let line = try? decoder.decode(FantasyPlayerLine.self, from: Data(blob.readableBytesView))
                else { continue }
                games[athleteID, default: 0] += 1
                for (key, value) in line.stats {
                    totals[athleteID, default: [:]][key, default: 0] += value
                }
            }
        }
        var out: [String: Average] = [:]
        for (athleteID, count) in games where count > 0 {
            let stats = (totals[athleteID] ?? [:]).mapValues { ($0 / Double(count) * 100).rounded() / 100 }
            out[athleteID] = Average(stats: stats, games: count)
        }
        return out
    }

    private func decode(_ rows: [SQLiteRow]) throws -> [FantasyPlayerLine] {
        let decoder = JSONDecoder()
        return rows.compactMap { row in
            guard let blob = row.column("line_json")?.blob else { return nil }
            return try? decoder.decode(FantasyPlayerLine.self, from: Data(blob.readableBytesView))
        }
    }
}

struct FantasyArchiveKey: StorageKey {
    typealias Value = FantasyArchive
}

struct FantasyArchiveLifecycle: LifecycleHandler {
    func shutdown(_ application: Application) {
        try? application.fantasyArchive?.closeFuture().wait()
    }

    func shutdownAsync(_ application: Application) async {
        await application.fantasyArchive?.close()
    }
}

extension Application {
    var fantasyArchive: FantasyArchive? {
        get { storage[FantasyArchiveKey.self] }
        set { storage[FantasyArchiveKey.self] = newValue }
    }
}
