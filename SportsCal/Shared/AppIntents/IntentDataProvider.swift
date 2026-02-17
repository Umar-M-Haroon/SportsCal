//
//  IntentDataProvider.swift
//  SportsCal
//
//  Lightweight data provider for App Intents.
//  Reads cached data from WidgetDataStore and favorites from app group.
//

import Foundation
import SportsCalModel

enum IntentDataProvider {
    private static let suiteName = "group.Komodo.SportsCal"
    private static let favoritesKey = "Favorites"

    /// Reads the user's favorite team names from the shared app group.
    static func readFavorites() -> Set<String> {
        let array = UserDefaults(suiteName: suiteName)?.stringArray(forKey: favoritesKey) ?? []
        return Set(array)
    }

    /// Writes updated favorites to the shared app group.
    static func writeFavorites(_ teams: Set<String>) {
        UserDefaults(suiteName: suiteName)?.set(Array(teams), forKey: favoritesKey)
    }

    /// Reads cached games from the widget data store.
    static func readCachedGames() -> [Game] {
        WidgetDataStore.readSnapshot()?.games ?? []
    }

    /// Reads cached teams from the widget data store.
    static func readCachedTeams() -> [Team] {
        WidgetDataStore.readSnapshot()?.teams ?? []
    }

    /// Returns all known team names from cached games (home + away).
    static func allTeamNames() -> [String] {
        let games = readCachedGames()
        var names = Set<String>()
        for game in games {
            names.insert(game.strHomeTeam)
            names.insert(game.strAwayTeam)
        }
        return names.sorted()
    }
}
