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
    private(set) var teams: Set<String>
    private(set) var players: Set<String>

    private let saveKey = "Favorites"
    private let playerSaveKey = "FavoritePlayers"

    private var defaults: UserDefaults? {
        #if os(watchOS)
        return UserDefaults.standard
        #else
        return UserDefaults(suiteName: "group.Komodo.SportsCal")
        #endif
    }

    init() {
        #if os(watchOS)
        let ud = UserDefaults.standard
        #else
        let ud = UserDefaults(suiteName: "group.Komodo.SportsCal")
        #endif

        teams = Set(ud?.stringArray(forKey: saveKey) ?? [])
        players = Set(ud?.stringArray(forKey: playerSaveKey) ?? [])
    }
    func contains(_ team: Game) -> Bool {
        return teams.contains(team.strHomeTeam) || teams.contains(team.strAwayTeam)
    }
    func matches(_ game: Game) -> Bool {
        if contains(game) { return true }
        if game.isIndividualSport {
            return game.resolvedLeaderboard.contains { containsPlayer($0.name) }
        }
        return false
    }
    func containsHome(_ home: String) -> Bool {
        return teams.contains(home)
    }
    func containsAway(_ away: String) -> Bool {
        teams.contains(away)
    }
    func containsPlayer(_ name: String) -> Bool {
        players.contains(name)
    }
    func add(_ favorite: String) {
        teams.insert(favorite)
        save()
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }
    func remove(_ favorite: String) {
        teams.remove(favorite)
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
        defaults?.set(Array(teams), forKey: saveKey)
        defaults?.set(Array(players), forKey: playerSaveKey)
    }

    /// Re-reads favorites from the appropriate UserDefaults store.
    /// Called by CloudSyncManager when remote favorites arrive via iCloud KVS.
    func reloadFromDefaults() {
        teams = Set(defaults?.stringArray(forKey: saveKey) ?? [])
        players = Set(defaults?.stringArray(forKey: playerSaveKey) ?? [])
    }
    static func ==(lhs: Favorites, rhs: Favorites) -> Bool {
        return lhs.teams == rhs.teams && lhs.players == rhs.players
    }
}

extension Notification.Name {
    static let favoritesDidChange = Notification.Name("favoritesDidChange")
}
