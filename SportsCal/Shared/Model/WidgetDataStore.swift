//
//  WidgetDataStore.swift
//  SportsCal
//
//  Shared data store for the widget extension.
//  The main app writes a trimmed snapshot of upcoming games + teams to the app group.
//  The widget reads it directly — no network requests needed.
//

import Foundation
import SportsCalModel
import os

struct WidgetSnapshot: Codable {
    let games: [Game]
    let teams: [Team]
    let updatedAt: Date
}

enum WidgetDataStore {
    private static let suiteName = "group.Komodo.SportsCal"
    private static let fileName = "widget-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent(fileName)
    }

    /// Strips heavy fields from a Game, keeping only what the widget needs.
    private static func stripGame(_ game: Game) -> Game {
        // Trim leaderboard to top 3, drop headshots and rounds
        let strippedLeaderboard = game.leaderboardEntries?.prefix(3).map { entry in
            LeaderboardEntry(
                name: entry.name,
                score: entry.score,
                position: entry.position,
                headshot: nil,
                thruHole: entry.thruHole,
                rounds: [],
                constructor: entry.constructor,
                gap: entry.gap
            )
        }

        // Trim lastPlay to top 3 lines
        let trimmedLastPlay: String? = game.lastPlay.flatMap { lp in
            let lines = lp.split(separator: "\n", omittingEmptySubsequences: false)
            return lines.isEmpty ? nil : lines.prefix(3).joined(separator: "\n")
        }

        return Game(
            idEvent: game.idEvent,
            idLeague: game.idLeague,
            idHomeTeam: game.idHomeTeam,
            idAwayTeam: game.idAwayTeam,
            strHomeTeam: game.strHomeTeam,
            strAwayTeam: game.strAwayTeam,
            intHomeScore: game.intHomeScore,
            intAwayScore: game.intAwayScore,
            strStatus: game.strStatus,
            strProgress: game.strProgress,
            strTimestamp: game.strTimestamp,
            lastPlay: trimmedLastPlay,
            isCompleted: game.isCompleted,
            isoDate: game.isoDate,
            leaderboardEntries: strippedLeaderboard.map(Array.init)
        )
    }

    // MARK: - Write (called by main app)

    /// Writes the next upcoming games + relevant teams to the app group container.
    /// Call this after schedule data is refreshed or sport filters change.
    static func writeSnapshot(games: [Game], teams: [Team]) {
        guard let url = fileURL else { return }

        // Keep ~30 upcoming games so the widget can navigate a few days ahead
        let now = Date()
        let upcoming = games
            .filter { ($0.standardDate ?? .distantPast) >= Calendar.current.startOfDay(for: now) }
            .sorted { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
            .prefix(30)

        // Strip heavy fields to reduce snapshot size and widget decode memory
        let strippedGames = upcoming.map { stripGame($0) }

        // Only include teams referenced by these games
        let teamIDs = Set(strippedGames.flatMap { [$0.idHomeTeam, $0.idAwayTeam].compactMap { $0 } })
        let relevantTeams = teams.filter { teamIDs.contains($0.idTeam ?? "") }

        let snapshot = WidgetSnapshot(
            games: strippedGames,
            teams: relevantTeams,
            updatedAt: now
        )

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            AppLogger.widget.info("[snapshot] wrote \(data.count) bytes (\(strippedGames.count) games, \(relevantTeams.count) teams)")
        } catch {
            AppLogger.widget.error("[snapshot] write failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Read (called by widget extension)

    /// Reads the cached snapshot. Returns nil if missing or expired (>2 hours old).
    static func readSnapshot() -> WidgetSnapshot? {
        guard let url = fileURL else {
            AppLogger.widget.warning("[snapshot] no file URL (app group missing?)")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            AppLogger.widget.info("[snapshot] file missing or unreadable at \(url.lastPathComponent)")
            return nil
        }
        AppLogger.widget.info("[snapshot] read \(data.count) bytes from disk")
        guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            AppLogger.widget.error("[snapshot] decode failed for \(data.count) byte file")
            return nil
        }

        let age = Date().timeIntervalSince(snapshot.updatedAt)
        AppLogger.widget.info("[snapshot] decoded \(snapshot.games.count) games, \(snapshot.teams.count) teams, age=\(Int(age))s")

        // Consider stale after 2 hours
        if age > 2 * 60 * 60 {
            AppLogger.widget.info("[snapshot] stale (age=\(Int(age))s > 7200s), returning nil")
            return nil
        }

        return snapshot
    }
}
