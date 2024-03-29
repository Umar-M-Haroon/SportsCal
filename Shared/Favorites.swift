//
//  Favorites.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/13/21.
//

import Foundation
import SwiftUI
import SportsCalModel

class Favorites: ObservableObject, Equatable {
    private(set) var teams: Set<String>
    
    private let saveKey = "Favorites"
    
    init() {
        let array = UserDefaults(suiteName: "group.Komodo.SportsCal")?.stringArray(forKey: saveKey)
        
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
        objectWillChange.send()
        teams.insert(favorite)
        save()
    }
    func remove(_ favorite: String) {
        objectWillChange.send()
        teams.remove(favorite)
        save()
    }
    func save() {
        let stringArray = Array(teams)
        UserDefaults(suiteName: "group.Komodo.SportsCal")?.set(stringArray, forKey: saveKey)
    }
    static func ==(lhs: Favorites, rhs: Favorites) -> Bool{
        return lhs.teams == rhs.teams
    }
}
