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
    /// The last game this window resolved, kept on screen while its id is briefly
    /// missing (a live tick between feeds) so pushed team pages survive.
    @State private var lastGame: Game?

    /// Live games often carry a different id (ESPN) than their schedule row
    /// (TheSportsDB), so look in both, then match the fixture of the game last
    /// shown: a finished live game leaves the live feed, and its schedule row
    /// has the other id.
    private var game: Game? {
        guard let gameID else { return nil }
        if let match = viewModel.allLiveEvents.first(where: { $0.id == gameID })
            ?? (viewModel.totalGames ?? []).first(where: { $0.id == gameID }) {
            return match
        }
        guard let lastGame else { return nil }
        if let live = viewModel.allLiveEvents.first(where: { $0.id == lastGame.id }) {
            return live
        }
        let home = lastGame.strHomeTeam.lowercased(), away = lastGame.strAwayTeam.lowercased()
        let schedule = (viewModel.totalGames ?? []).filter {
            $0.strHomeTeam.lowercased() == home && $0.strAwayTeam.lowercased() == away
        }
        let index = LiveFixtureIndex(live: [lastGame], schedule: schedule)
        return schedule.first { index.contains($0) } ?? lastGame
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
            } else if gameID != nil && viewModel.totalGames == nil {
                // A restored window opens before the schedule has loaded.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onChange(of: game, initial: true) { _, newGame in
            if let newGame { lastGame = newGame }
        }
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
