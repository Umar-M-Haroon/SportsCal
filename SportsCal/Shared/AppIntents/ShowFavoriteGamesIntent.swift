//
//  ShowFavoriteGamesIntent.swift
//  SportsCal
//
//  Siri: "Show my favorite teams' games in SportsCal"
//  Opens the app filtered to favorite games.
//

import AppIntents
import SportsCalModel

struct ShowFavoriteGamesIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Favorite Games"
    static var description: IntentDescription = "Opens SportsCal showing only your favorite teams' upcoming games."

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let favorites = IntentDataProvider.readFavorites()
        guard !favorites.isEmpty else {
            return .result(dialog: "You don't have any favorite teams yet. Open SportsCal to add some!")
        }

        let games = IntentDataProvider.readCachedGames()
        let favoriteGames = games.filter { game in
            favorites.contains(game.strHomeTeam) || favorites.contains(game.strAwayTeam)
        }

        if favoriteGames.isEmpty {
            return .result(dialog: "No upcoming games for your favorite teams right now.")
        }

        let count = favoriteGames.count
        return .result(dialog: "Opening SportsCal with \(count) upcoming game\(count == 1 ? "" : "s") for your favorites.")
    }
}
