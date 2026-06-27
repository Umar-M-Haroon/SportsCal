//
//  MacGameDetailWindow.swift
//  SportsCal
//
//  Standalone game-detail window for macOS multi-window support. Opened via
//  "Open in New Window" (openWindow(value: game.id)); resolves the game id
//  back to a live Game from the view model so the window keeps updating as
//  scores change.
//

#if os(macOS)
import SwiftUI
import SportsCalModel

struct MacGameDetailWindow: View {
    let gameID: String?

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites

    private var game: Game? {
        guard let gameID else { return nil }
        return (viewModel.totalGames ?? []).first { $0.id == gameID }
    }

    var body: some View {
        Group {
            if let game {
                ModernGameDetailView(
                    game: game,
                    homeTeam: Team(strTeam: game.strHomeTeam),
                    awayTeam: Team(strTeam: game.strAwayTeam)
                )
                .environment(viewModel)
                .environment(favorites)
            } else {
                ContentUnavailableView(
                    "Game Not Found",
                    systemImage: "sportscourt",
                    description: Text("This game is no longer in the current schedule.")
                )
            }
        }
        .frame(minWidth: 380, idealWidth: 460, minHeight: 480, idealHeight: 660)
        .navigationTitle(game.map { "\($0.strAwayTeam) @ \($0.strHomeTeam)" } ?? "Game")
    }
}
#endif
