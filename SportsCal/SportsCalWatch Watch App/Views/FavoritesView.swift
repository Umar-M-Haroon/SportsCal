//
//  FavoritesView.swift
//  SportsCalWatch
//
//  Shows upcoming games for favorite teams, grouped by date.
//

import SwiftUI
import SportsCalModel

struct FavoritesView: View {
    @Environment(WatchViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            List {
                let favGames = Array(viewModel.favoriteGames.prefix(10))

                if favGames.isEmpty {
                    WatchEmptyState.noFavorites
                        .listRowBackground(Color.clear)
                }

                let grouped = Dictionary(grouping: favGames) { game -> String in
                    guard let date = game.standardDate else { return "Unknown" }
                    return dateLabel(for: date)
                }
                let sortedKeys = grouped.keys.sorted { key1, key2 in
                    let date1 = grouped[key1]?.first?.standardDate ?? .distantFuture
                    let date2 = grouped[key2]?.first?.standardDate ?? .distantFuture
                    return date1 < date2
                }

                ForEach(sortedKeys, id: \.self) { key in
                    if let games = grouped[key] {
                        Section(key) {
                            ForEach(games, id: \.id) { game in
                                WatchGameRowRouter(game: game, teams: viewModel.teams, isFavorite: true)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Favorites")
            .navigationDestination(for: Game.self) { game in
                WatchGameDetailRouter(game: game, teams: viewModel.teams)
            }
        }
    }

    private func dateLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}
