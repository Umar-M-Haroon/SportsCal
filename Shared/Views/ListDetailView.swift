//
//  ListDetailView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 7/6/23.
//

import SwiftUI
import SportsCalModel

struct ListDetailView: View {
    var listGames: Array<(key: DateComponents, value: Array<Game>)>
    var liveGames: [Game]
    @EnvironmentObject var storage: UserDefaultStorage
    @EnvironmentObject var favorites: Favorites
    @EnvironmentObject var viewModel: GameViewModel
    @Binding var sheetType: SheetType?
    
    @State var shouldShowSportsCalProAlert: Bool = false
    
    var body: some View {
        NavigationView {
            List {
                if !liveGames.isEmpty {
                    Section {
                        ForEach(liveGames, id: \.self) { event in
                            if let homeScore = Int(event.intHomeScore ?? ""),
                               let awayScore = Int(event.intAwayScore ?? ""),
                               let (homeTeam, awayTeam) = viewModel.getTeams(for: event) {
                                GameScoreView(homeTeam: homeTeam, awayTeam: awayTeam, homeScore: homeScore, awayScore: awayScore, game: event, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: true)
                                    .environmentObject(viewModel)
                            }
                        }
                    } header: {
                        LiveAnimatedView()
                    }
                }
                
                if !listGames.isEmpty {
                    ForEach(listGames.map({$0.key}).indices, id: \.self) { index in
                        Section {
                            ForEach(listGames.map({$0.value})[index]) { game in
                                if let (homeTeam, awayTeam) = viewModel.getTeams(for: game) {
                                    if let homeScore = Int(game.intHomeScore ?? ""), let awayScore = Int(game.intAwayScore ?? "") {
                                        GameScoreView(homeTeam: homeTeam, awayTeam: awayTeam, homeScore: homeScore, awayScore: awayScore, game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: false)
                                            .environmentObject(favorites)
                                            .environmentObject(viewModel)
                                    } else {
                                        UpcomingGameView(homeTeam: homeTeam, awayTeam: awayTeam, game: game, showCountdown: storage.$showStartTime, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, dateFormat:  storage.dateFormat)
                                            .environmentObject(favorites)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .toolbar(content: {
                Button {
                    sheetType = nil
                } label: {
                    Image(systemName: "x.circle.fill")
                }
            })
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("\(listGames.map({$0.key})[0].formatted(format: viewModel.appStorage.dateFormat, isRelative: viewModel.appStorage.useRelativeValue))")
        }
    }
}

