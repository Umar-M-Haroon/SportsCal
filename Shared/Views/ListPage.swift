//
//  ListPage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 4/15/23.
//

import SwiftUI

struct ListPage: View {
    @EnvironmentObject var viewModel: GameViewModel
    @EnvironmentObject var storage: UserDefaultStorage
    @EnvironmentObject var favorites: Favorites
    @State var shouldShowPromo: Bool
    @State private var sheetType: SheetType?
    
    @State var shouldShowSportsCalProAlert: Bool
    @State var shouldShowSettings: Bool
    @State var searchString: String = ""
    var body: some View {
        List {
            Section {
                SportsSelectView(currentlyLiveSports: viewModel.currentlyLiveSports)
                    .environmentObject(viewModel)
            }  footer: {
                if shouldShowPromo {
                    HStack {
                        Text("Try SportsCal Pro to see multiple sports at once")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Button {
                            sheetType = .settings
                        } label: {
                            Text("Learn More.")
                                .font(.caption2)
                        }
                    }
                }
            }
            if !viewModel.sortedGames.isEmpty {
                LiveEventsView(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType)
                    .environmentObject(favorites)
                    .environmentObject(storage)
                    .environmentObject(viewModel)
                FavoriteGamesView(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType)
                    .environmentObject(favorites)
                    .environmentObject(storage)
                    .environmentObject(viewModel)
                ForEach(viewModel.sortedGames.map({$0.key}).indices, id: \.self) { index in
                    Section {
                        ForEach(viewModel.sortedGames.map({$0.value})[index]) { game in
                            if let (homeTeam, awayTeam) = viewModel.getTeams(for: game) {
                                if let homeScore = Int(game.intHomeScore ?? ""), let awayScore = Int(game.intAwayScore ?? "") {
                                    GameScoreView(homeTeam: homeTeam, awayTeam: awayTeam, homeScore: homeScore, awayScore: awayScore, game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: false)
                                        .environmentObject(favorites)
                                } else {
                                    UpcomingGameView(homeTeam: homeTeam, awayTeam: awayTeam, game: game, showCountdown: storage.$showStartTime, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, dateFormat:  storage.dateFormat)
                                        .environmentObject(favorites)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("\(viewModel.sortedGames.map({$0.key})[index].formatted(format: viewModel.appStorage.dateFormat, isRelative: viewModel.appStorage.useRelativeValue))")
                                .font(.headline)
                        }
                    }
                }
            } else {
                if viewModel.networkState == .loading {
                    HStack {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    VStack {
                        Text("No games fetched")
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            viewModel.getInfo()
                        }
                        .foregroundColor(Color.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .searchable(text: $searchString, placement: SearchFieldPlacement.navigationBarDrawer(displayMode: .automatic), prompt: "Teams: ")
        .onChange(of: favorites.teams, perform: { _ in
            withAnimation {
                viewModel.filterSports(searchString: searchString)
            }
        })
        .onChange(of: searchString, perform: { newValue in
            withAnimation {
                viewModel.filterSports(searchString: newValue)
            }
        })
    }
}

struct ListPage_Previews: PreviewProvider {
    static var previews: some View {
        ListPage(shouldShowPromo: false, shouldShowSportsCalProAlert: false, shouldShowSettings: false)
    }
}
