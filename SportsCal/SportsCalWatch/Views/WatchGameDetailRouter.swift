//
//  WatchGameDetailRouter.swift
//  SportsCalWatch
//
//  Routes to the correct detail view based on sport type.
//

import SwiftUI
import SportsCalModel

struct WatchGameDetailRouter: View {
    let game: Game
    let teams: [Team]

    var body: some View {
        if game.isRace {
            WatchRaceDetailView(game: game)
        } else if game.sportType == .tennis && game.homeLinescores != nil {
            WatchTennisDetailView(game: game)
        } else if game.isIndividualSport {
            WatchTournamentDetailView(game: game)
        } else {
            WatchGameDetailView(game: game, teams: teams)
        }
    }
}
