//
//  AddFavoriteTeamIntent.swift
//  SportsCal
//
//  Siri: "Add Lakers to my favorites in SportsCal"
//  Writes to Favorites storage in the shared app group.
//

import AppIntents
import SportsCalModel

struct AddFavoriteTeamIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Favorite Team"
    static var description: IntentDescription = "Add a team to your SportsCal favorites."

    @Parameter(title: "Team")
    var team: TeamEntity

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var favorites = IntentDataProvider.readFavorites()
        let teamName = team.name

        if favorites.contains(teamName) {
            return .result(dialog: "\(teamName) is already in your favorites.")
        }

        favorites.insert(teamName)
        IntentDataProvider.writeFavorites(favorites)
        NotificationCenter.default.post(name: Notification.Name("favoritesDidChange"), object: nil)

        return .result(dialog: "Added \(teamName) to your SportsCal favorites.")
    }
}

struct RemoveFavoriteTeamIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove Favorite Team"
    static var description: IntentDescription = "Remove a team from your SportsCal favorites."

    @Parameter(title: "Team")
    var team: TeamEntity

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var favorites = IntentDataProvider.readFavorites()
        let teamName = team.name

        guard favorites.contains(teamName) else {
            return .result(dialog: "\(teamName) isn't in your favorites.")
        }

        favorites.remove(teamName)
        IntentDataProvider.writeFavorites(favorites)
        NotificationCenter.default.post(name: Notification.Name("favoritesDidChange"), object: nil)

        return .result(dialog: "Removed \(teamName) from your SportsCal favorites.")
    }
}
