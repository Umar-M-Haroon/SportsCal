//
//  MacGameDetailWindow.swift
//  SportsCal
//
//  Standalone game-detail window. Opened via "Open in New Window"
//  (openWindow(id: "game-detail", value: game.id)) on the Mac, and on iPad and
//  the unfolded iPhone Duo, where two windows sit side by side. Resolves the
//  game id back to a live Game from the view model so the window keeps updating
//  as scores change.
//

import SwiftUI
import SportsCalModel

struct GameDetailWindow: View {
    let gameID: String?

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites

    /// Live games often carry a different id (ESPN) than their schedule row
    /// (TheSportsDB), so look in both.
    private var game: Game? {
        guard let gameID else { return nil }
        return viewModel.allLiveEvents.first { $0.id == gameID }
            ?? (viewModel.totalGames ?? []).first { $0.id == gameID }
    }

    var body: some View {
        Group {
            if let game {
                // Own stack so the hero's team links (TeamDetailLink) can push.
                NavigationStack {
                    detail(for: game)
                        .environment(viewModel)
                        .environment(favorites)
                }
            } else {
                ContentUnavailableView(
                    "Game Not Found",
                    systemImage: "sportscourt",
                    description: Text("This game is no longer in the current schedule.")
                )
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 460, minHeight: 480, idealHeight: 660)
        #endif
        .navigationTitle(game.map { "\($0.strAwayTeam) @ \($0.strHomeTeam)" } ?? "Game")
    }

    @ViewBuilder
    private func detail(for game: Game) -> some View {
        let teams = viewModel.getTeams(for: game)
        let home = teams?.home ?? Team(strTeam: game.strHomeTeam)
        let away = teams?.away ?? Team(strTeam: game.strAwayTeam)
        #if os(macOS)
        ModernGameDetailView(game: game, homeTeam: home, awayTeam: away)
        #else
        if game.isRace {
            RaceDetailView(game: game)
        } else if game.isTennisMatch {
            TennisMatchDetailView(game: game)
        } else if game.isIndividualSport {
            TournamentDetailView(game: game)
        } else {
            AdaptiveGameDetail(game: game, homeTeam: home, awayTeam: away)
        }
        #endif
    }
}

/// "Open in New Window" for a game's context menu. Shown only where a second
/// window can actually open: multi-window platforms in a regular-width scene (iPad,
/// the unfolded iPhone Duo). The Duo's outer display can't host new windows.
struct OpenGameInNewWindowButton: View {
    let game: Game

    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if supportsMultipleWindows && sizeClass == .regular {
            Button {
                openWindow(id: "game-detail", value: game.id)
            } label: {
                Label("Open in New Window", systemImage: "macwindow.badge.plus")
            }
        }
    }
}
