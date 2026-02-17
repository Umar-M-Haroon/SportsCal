//
//  FavoriteGamesView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 3/7/23.
//

import SwiftUI
import SportsCalModel
struct FavoriteGamesView: View {
    @Environment(Favorites.self) private var favorites
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var sportFilter: SportChipFilter = .all

    private var filteredFavorites: [GameWithTeams] {
        viewModel.favoriteGamesWithTeams.filter { sportFilter.matches($0.game) }
    }

    var body: some View {
        if !filteredFavorites.isEmpty {
            Section {
                SportsRingView(
                    games: viewModel.filteredGames ?? [],
                    favorites: favorites
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(filteredFavorites) { gameWithTeams in
                    let game = gameWithTeams.game
                    if game.isRace {
                        NavigationLink {
                            RaceDetailView(game: game)
                                .environment(viewModel)
                                .environment(favorites)
                        } label: {
                            RaceScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: false)
                                .environment(viewModel)
                                .environment(favorites)
                        }
                        .buttonStyle(.plain)
                    } else if game.isTennisMatch {
                        NavigationLink {
                            TennisMatchDetailView(game: game)
                                .environment(viewModel)
                                .environment(favorites)
                        } label: {
                            TennisMatchScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: false)
                                .environment(viewModel)
                                .environment(favorites)
                        }
                        .buttonStyle(.plain)
                    } else if game.isIndividualSport {
                        NavigationLink {
                            TournamentDetailView(game: game)
                                .environment(viewModel)
                                .environment(favorites)
                        } label: {
                            TournamentScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: false)
                                .environment(viewModel)
                        }
                        .buttonStyle(.plain)
                    } else if let homeTeam = gameWithTeams.homeTeam,
                              let awayTeam = gameWithTeams.awayTeam {
                        UpcomingGameView(homeTeam: homeTeam, awayTeam: awayTeam, game: game, showCountdown: storage.$showStartTime, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, dateFormat:  storage.dateFormat, isFavorite: true)
                            .environment(favorites)
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
