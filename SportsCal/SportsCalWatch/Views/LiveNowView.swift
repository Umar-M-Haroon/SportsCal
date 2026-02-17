//
//  LiveNowView.swift
//  SportsCalWatch
//
//  Shows all currently live games, favorites pinned to top.
//

import SwiftUI
import SportsCalModel

struct LiveNowView: View {
    @Environment(WatchViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            List {
                let favLive = viewModel.liveGames.filter { viewModel.isFavorite($0) }
                let otherLive = viewModel.liveGames.filter { !viewModel.isFavorite($0) }

                if !favLive.isEmpty {
                    Section("Favorites") {
                        ForEach(favLive, id: \.id) { game in
                            WatchGameRowRouter(game: game, teams: viewModel.teams, isFavorite: true)
                        }
                    }
                }

                if !otherLive.isEmpty {
                    Section("Live") {
                        ForEach(otherLive, id: \.id) { game in
                            WatchGameRowRouter(game: game, teams: viewModel.teams, isFavorite: false)
                        }
                    }
                }
            }
            .navigationTitle("Live Now")
            .navigationDestination(for: Game.self) { game in
                WatchGameDetailRouter(game: game, teams: viewModel.teams)
            }
        }
    }
}
