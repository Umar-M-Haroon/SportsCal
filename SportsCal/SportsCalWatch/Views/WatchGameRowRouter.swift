//
//  WatchGameRowRouter.swift
//  SportsCalWatch
//
//  Routes to the correct row view based on sport type.
//

import SwiftUI
import SportsCalModel

struct WatchGameRowRouter: View {
    let game: Game
    let teams: [Team]
    let isFavorite: Bool

    var body: some View {
        if game.isRace {
            WatchRaceRow(game: game)
        } else if game.sportType == .tennis && game.homeLinescores != nil {
            WatchTennisRow(game: game)
        } else if game.isIndividualSport {
            WatchTournamentRow(game: game)
        } else {
            WatchGameRow(game: game, teams: teams, isFavorite: isFavorite)
        }
    }
}
