//
//  TeamsManager.swift
//  SportsCal (Shared)
//
//  Local mirror of the server's `/teams` payload. Persists to the App Group
//  container so the iOS app, watch app, and widgets share one cache. Powers
//  Favorites' name → ID resolution and any other call site that needs to
//  reconcile alias-equivalent team names locally.
//

import Foundation
import SportsCalModel
import os

@Observable
final class TeamsManager {
    static let shared = TeamsManager()

    private static let appGroupID = "group.Komodo.SportsCal"
    private static let cacheFileName = "teams.json"
    private static let lastRefreshKey = "TeamsManager.lastRefresh"
    private static let refreshInterval: TimeInterval = 60 * 60 * 24 * 7
    private static let logger = Logger(subsystem: "com.komodo.SportsCal", category: "TeamsManager")

    private(set) var teams: [Team] = []
    private(set) var byID: [String: Team] = [:]
    /// FBS teams, derived from the college football schedule. The server's `/teams`
    /// payload leaves them out — app versions that predate college football would list
    /// teams they can't show games for. Directory-only: they stay out of the ID and name
    /// indexes, so following one goes by name, which works before any cache is warm.
    private(set) var collegeTeams: [Team] = []

    /// Lookup index: normalized (lowercased + diacritic-folded) name/alias → idTeam.
    private var byNameKey: [String: String] = [:]
    /// Exact (un-normalized) canonical name/alias → idTeam, resolved through `byNameKey`
    /// so it always agrees with the normalized lookup. `Favorites.contains` resolves two
    /// names per game across the whole schedule on every filter pass, and normalizing
    /// (lowercase + diacritic fold) each one showed up in main-thread hang reports.
    private var byExactName: [String: String] = [:]
    private var isRefreshing = false

    private init() {
        loadFromDisk()
    }

    /// Resolve a team by exact ID.
    func team(byID id: String) -> Team? {
        byID[id]
    }

    /// Resolve a team by canonical name OR any of its aliases (case- and diacritic-insensitive).
    func team(byNameOrAlias name: String) -> Team? {
        let key = TeamsManager.normalize(name)
        guard let id = byNameKey[key] else { return nil }
        return byID[id]
    }

    /// idTeam for a name or alias if known. Used by Favorites for migration.
    func teamID(forName name: String) -> String? {
        if let id = byExactName[name] { return id }
        return byNameKey[TeamsManager.normalize(name)]
    }

    /// Rebuilds `collegeTeams` from the schedule. FCS opponents are left out: they appear
    /// once or twice a season and would crowd the directory.
    func updateCollegeTeams(from games: [Game]) {
        var seen: [String: Team] = [:]
        for game in games where game.isCollegeFootball {
            let sides = [
                (game.idHomeTeam, game.strHomeTeam, game.strHomeTeamBadge, game.homeConference),
                (game.idAwayTeam, game.strAwayTeam, game.strAwayTeamBadge, game.awayConference),
            ]
            for (id, name, badge, conference) in sides {
                guard let id, !id.isEmpty, seen[id] == nil,
                      let conference, conference != CollegeConference.fcs.rawValue else { continue }
                seen[id] = Team(idTeam: id, strTeam: name, strTeamShort: nil, strAlternate: nil, strTeamBadge: badge)
            }
        }
        let updated = seen.values.sorted { ($0.strTeam ?? "") < ($1.strTeam ?? "") }
        guard updated != collegeTeams else { return }
        collegeTeams = updated
        NotificationCenter.default.post(name: .teamsManagerDidUpdate, object: nil)
    }

    /// Trigger a background refresh if the cache is stale or empty. Cheap if not needed.
    func refreshIfStale() {
        let last = UserDefaults.standard.object(forKey: TeamsManager.lastRefreshKey) as? Date
        let isStale = last.map { Date().timeIntervalSince($0) > TeamsManager.refreshInterval } ?? true
        if isStale || teams.isEmpty {
            Task { await refresh() }
        }
    }

    /// Force-refresh from server. Errors keep the existing on-disk cache.
    @MainActor
    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fetched = try await NetworkHandler.getTeams()
            guard !fetched.isEmpty else {
                TeamsManager.logger.warning("TeamsManager.refresh: server returned empty teams; keeping cache")
                return
            }
            apply(teams: fetched)
            writeToDisk(fetched)
            UserDefaults.standard.set(Date(), forKey: TeamsManager.lastRefreshKey)
            TeamsManager.logger.info("TeamsManager refreshed \(fetched.count, privacy: .public) teams")
            NotificationCenter.default.post(name: .teamsManagerDidUpdate, object: nil)
        } catch {
            TeamsManager.logger.warning("TeamsManager.refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Disk I/O

    private static func cacheURL() -> URL? {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return containerURL.appendingPathComponent(cacheFileName)
        }
        // watchOS extensions / sandboxed environments without app group access
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(cacheFileName)
    }

    private func loadFromDisk() {
        guard let url = TeamsManager.cacheURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Team].self, from: data) else {
            return
        }
        apply(teams: decoded)
    }

    private func writeToDisk(_ teams: [Team]) {
        guard let url = TeamsManager.cacheURL() else { return }
        do {
            let data = try JSONEncoder().encode(teams)
            try data.write(to: url, options: .atomic)
        } catch {
            TeamsManager.logger.warning("TeamsManager.writeToDisk failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(teams: [Team]) {
        var byID: [String: Team] = [:]
        var byNameKey: [String: String] = [:]
        var exactNames: [String] = []
        for team in teams {
            guard let id = team.idTeam, !id.isEmpty,
                  let canonical = team.strTeam, !canonical.isEmpty else { continue }
            byID[id] = team

            exactNames.append(canonical)
            let canonicalKey = TeamsManager.normalize(canonical)
            if byNameKey[canonicalKey] == nil { byNameKey[canonicalKey] = id }

            if let alternate = team.strAlternate {
                for alt in alternate.components(separatedBy: ", ") {
                    let trimmed = alt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    exactNames.append(trimmed)
                    let key = TeamsManager.normalize(trimmed)
                    if byNameKey[key] == nil { byNameKey[key] = id }
                }
            }
        }
        self.teams = teams
        self.byID = byID
        var byExactName: [String: String] = [:]
        for name in exactNames where byExactName[name] == nil {
            byExactName[name] = byNameKey[TeamsManager.normalize(name)]
        }
        self.byNameKey = byNameKey
        self.byExactName = byExactName
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Notification.Name {
    static let teamsManagerDidUpdate = Notification.Name("teamsManagerDidUpdate")
}
