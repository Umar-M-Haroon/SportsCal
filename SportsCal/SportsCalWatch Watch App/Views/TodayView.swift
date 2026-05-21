//
//  TodayView.swift
//  SportsCalWatch
//
//  Today's schedule: favorites first, then grouped by sport.
//

import SwiftUI
import SportsCalModel

struct TodayView: View {
    @Environment(WatchViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            List {
                let today = viewModel.todayGames
                let favGames = today.filter { viewModel.isFavorite($0) }
                let otherGames = today.filter { !viewModel.isFavorite($0) }

                if today.isEmpty {
                    WatchEmptyState.quietDay
                        .listRowBackground(Color.clear)
                }

                if !favGames.isEmpty {
                    Section("Favorites") {
                        ForEach(favGames, id: \.id) { game in
                            WatchGameRowRouter(game: game, teams: viewModel.teams, isFavorite: true)
                        }
                    }
                }

                // Group remaining by sport
                let grouped = Dictionary(grouping: otherGames, by: { $0.sportType ?? .basketball })
                let sortedSports = grouped.keys.sorted { $0.rawValue < $1.rawValue }

                ForEach(sortedSports, id: \.self) { sport in
                    if let games = grouped[sport] {
                        Section(sport.capitalized) {
                            ForEach(games, id: \.id) { game in
                                WatchGameRowRouter(game: game, teams: viewModel.teams, isFavorite: false)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .navigationDestination(for: Game.self) { game in
                WatchGameDetailRouter(game: game, teams: viewModel.teams)
            }
        }
    }
}
