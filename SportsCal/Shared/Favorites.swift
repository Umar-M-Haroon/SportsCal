//
//  Favorites.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/13/21.
//

import Foundation
import SwiftUI
import SportsCalModel

@Observable
class Favorites: Equatable {
    /// Resolved TheSportsDB team IDs. Source of truth post-migration.
    private(set) var teamIDs: Set<String>
    /// Names from the pre-v2 store that didn't resolve to an ID via TeamsManager.
    /// Kept so users don't lose intent if the teams cache wasn't populated yet at
    /// migration time; retried whenever TeamsManager refreshes.
    private(set) var legacyTeamNames: Set<String>
    private(set) var players: Set<String>

    private let saveKey = "Favorites"
    private let playerSaveKey = "FavoritePlayers"
    private static let currentSchemaVersion = 2

    private var defaults: UserDefaults? {
        #if os(watchOS)
        return UserDefaults.standard
        #else
        return UserDefaults(suiteName: "group.Komodo.SportsCal")
        #endif
    }

    init() {
        let store: UserDefaults? = {
            #if os(watchOS)
            return UserDefaults.standard
            #else
            return UserDefaults(suiteName: "group.Komodo.SportsCal")
            #endif
        }()
        let raw = store?.object(forKey: "Favorites")
        let (ids, legacy) = Favorites.decodePayload(raw)
        teamIDs = ids
        legacyTeamNames = legacy
        players = Set(store?.stringArray(forKey: "FavoritePlayers") ?? [])

        // First-launch migration: when raw was the legacy [String] shape,
        // attempt to resolve names → IDs via TeamsManager and persist the new
        // dict shape. Anything still unresolved stays in legacyTeamNames and
        // gets retried on each TeamsManager refresh.
        if Favorites.isLegacyShape(raw) {
            attemptResolveLegacy()
            save()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTeamsManagerUpdate),
            name: .teamsManagerDidUpdate,
            object: nil
        )
    }

    /// Public name-set view for callers that still operate on canonical names
    /// (Spotlight indexing, EngagementTracker exclusions). Combines resolved
    /// canonical names with any unresolved legacy entries.
    var teams: Set<String> {
        var result = legacyTeamNames
        for id in teamIDs {
            if let name = TeamsManager.shared.team(byID: id)?.strTeam {
                result.insert(name)
            }
        }
        return result
    }

    func contains(_ team: Game) -> Bool {
        if let homeID = team.idHomeTeam, !homeID.isEmpty, teamIDs.contains(homeID) { return true }
        if let awayID = team.idAwayTeam, !awayID.isEmpty, teamIDs.contains(awayID) { return true }
        if !legacyTeamNames.isEmpty {
            if legacyTeamNames.contains(team.strHomeTeam) { return true }
            if legacyTeamNames.contains(team.strAwayTeam) { return true }
        }
        // Resolve game team-name to ID via TeamsManager — handles the case
        // where the game record's idHomeTeam/idAwayTeam are nil but the name
        // resolves to a favorited team.
        if let id = TeamsManager.shared.teamID(forName: team.strHomeTeam), teamIDs.contains(id) { return true }
        if let id = TeamsManager.shared.teamID(forName: team.strAwayTeam), teamIDs.contains(id) { return true }
        return false
    }

    func matches(_ game: Game) -> Bool {
        if contains(game) { return true }
        if game.isIndividualSport {
            return game.resolvedLeaderboard.contains { containsPlayer($0.name) }
        }
        return false
    }

    func contains(_ name: String) -> Bool {
        if let id = TeamsManager.shared.teamID(forName: name), teamIDs.contains(id) { return true }
        return legacyTeamNames.contains(name)
    }

    func containsHome(_ home: String) -> Bool { contains(home) }
    func containsAway(_ away: String) -> Bool { contains(away) }

    func containsPlayer(_ name: String) -> Bool {
        players.contains(name)
    }

    func add(_ favorite: String) {
        if let id = TeamsManager.shared.teamID(forName: favorite) {
            teamIDs.insert(id)
            // If we'd previously stashed this name as legacy, clean it up.
            legacyTeamNames.remove(favorite)
        } else {
            legacyTeamNames.insert(favorite)
        }
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    func remove(_ favorite: String) {
        if let id = TeamsManager.shared.teamID(forName: favorite) {
            teamIDs.remove(id)
        }
        legacyTeamNames.remove(favorite)
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    func addPlayer(_ name: String) {
        players.insert(name)
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    func removePlayer(_ name: String) {
        players.remove(name)
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    func save() {
        let payload: [String: Any] = [
            "schemaVersion": Favorites.currentSchemaVersion,
            "ids": Array(teamIDs),
            "legacy": Array(legacyTeamNames)
        ]
        defaults?.set(payload, forKey: saveKey)
        defaults?.set(Array(players), forKey: playerSaveKey)
    }

    /// Re-reads favorites from the appropriate UserDefaults store.
    /// Called by CloudSyncManager when remote favorites arrive via iCloud KVS.
    func reloadFromDefaults() {
        let raw = defaults?.object(forKey: saveKey)
        let (ids, legacy) = Favorites.decodePayload(raw)
        teamIDs = ids
        legacyTeamNames = legacy
        players = Set(defaults?.stringArray(forKey: playerSaveKey) ?? [])
        if Favorites.isLegacyShape(raw) {
            attemptResolveLegacy()
            save()
        }
    }

    static func == (lhs: Favorites, rhs: Favorites) -> Bool {
        return lhs.teamIDs == rhs.teamIDs
            && lhs.legacyTeamNames == rhs.legacyTeamNames
            && lhs.players == rhs.players
    }

    // MARK: - Private

    @objc private func handleTeamsManagerUpdate() {
        guard !legacyTeamNames.isEmpty else { return }
        attemptResolveLegacy()
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    private func attemptResolveLegacy() {
        guard !legacyTeamNames.isEmpty else { return }
        var resolved: [String] = []
        for name in legacyTeamNames {
            if let id = TeamsManager.shared.teamID(forName: name) {
                teamIDs.insert(id)
                resolved.append(name)
            }
        }
        for name in resolved { legacyTeamNames.remove(name) }
    }

    /// Decodes the persisted favorites payload, tolerating both v1 (`[String]`
    /// of team names) and v2 (`{ schemaVersion, ids, legacy }`) shapes.
    private static func decodePayload(_ raw: Any?) -> (ids: Set<String>, legacy: Set<String>) {
        if let dict = raw as? [String: Any] {
            let ids = (dict["ids"] as? [String]).map(Set.init) ?? []
            let legacy = (dict["legacy"] as? [String]).map(Set.init) ?? []
            return (ids, legacy)
        }
        if let array = raw as? [String] {
            return ([], Set(array))
        }
        return ([], [])
    }

    private static func isLegacyShape(_ raw: Any?) -> Bool {
        raw is [String]
    }
}

extension Notification.Name {
    static let favoritesDidChange = Notification.Name("favoritesDidChange")
}
