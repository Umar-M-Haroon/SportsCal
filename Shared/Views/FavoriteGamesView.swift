//
//  FavoriteGamesView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 3/7/23.
//

import SwiftUI
import SportsCalModel
struct FavoriteGamesView: View {
    @EnvironmentObject var favorites: Favorites
    @EnvironmentObject var viewModel: GameViewModel
    @EnvironmentObject var storage: UserDefaultStorage
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var body: some View {
        if let favoriteGames = viewModel.favoriteGames, !favoriteGames.isEmpty {
            Section {
                ForEach(viewModel.favoriteGames ?? []) { game in
                    if let (homeTeam, awayTeam) = viewModel.getTeams(for: game) {
                        UpcomingGameView(homeTeam: homeTeam, awayTeam: awayTeam, game: game, showCountdown: storage.$showStartTime, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, dateFormat:  storage.dateFormat, isFavorite: true)
                            .environmentObject(favorites)
                    }
                }
            } header: {
                HStack {
                    Text("Favorites")
                        .font(.headline)
                }
            }
        } else {
            EmptyView()
        }
    }
}
