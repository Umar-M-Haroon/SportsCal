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
    
    private let saveKey = "Favorites"
    
    init() {
        // watchOS: app group is not available cross-device, read from standard UserDefaults
        // (synced via WatchConnectivity)
        #if os(watchOS)
        let array = UserDefaults.standard.stringArray(forKey: saveKey)
        #else
        let array = UserDefaults(suiteName: "group.Komodo.SportsCal")?.stringArray(forKey: saveKey)
        #endif

        var teamSet = Set<String>()
        array?.forEach({ team in
            teamSet.insert(team)
        })
        teams = teamSet
    }
    func contains(_ team: Game) -> Bool {
        return teams.contains(team.strHomeTeam) || teams.contains(team.strAwayTeam)
    }
    func containsHome(_ home: String) -> Bool {
        return teams.contains(home)
    }
    func containsAway(_ away: String) -> Bool {
        teams.contains(away)
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
    func save() {
        let stringArray = Array(teams)
        #if os(watchOS)
        UserDefaults.standard.set(stringArray, forKey: saveKey)
        #else
        UserDefaults(suiteName: "group.Komodo.SportsCal")?.set(stringArray, forKey: saveKey)
        #endif
    }
    static func ==(lhs: Favorites, rhs: Favorites) -> Bool{
        return lhs.teams == rhs.teams
    }
}

extension Notification.Name {
    static let favoritesDidChange = Notification.Name("favoritesDidChange")
}
