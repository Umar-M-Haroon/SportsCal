//
//  LiveEventsView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 3/24/23.
//

import SwiftUI
import SportsCalModel

struct LiveEventsView: View {
    @Environment(Favorites.self) private var favorites
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var sportFilter: SportChipFilter = .all

    private var filteredLiveEvents: [GameWithTeams] {
        viewModel.liveEventsWithTeams.filter { sportFilter.matches($0.game) }
    }

    var body: some View {
        if !filteredLiveEvents.isEmpty {
            Section {
                ForEach(filteredLiveEvents) { gameWithTeams in
                    let event = gameWithTeams.game
                    if event.isRace {
                        NavigationLink {
                            RaceDetailView(game: event)
                                .environment(viewModel)
                                .environment(favorites)
                        } label: {
                            RaceScoreView(game: event, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: true)
                                .environment(viewModel)
                                .environment(favorites)
                        }
                        .buttonStyle(.plain)
                    } else if event.isTennisMatch {
                        NavigationLink {
                            TennisMatchDetailView(game: event)
                                .environment(viewModel)
                                .environment(favorites)
                        } label: {
                            TennisMatchScoreView(game: event, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: true)
                                .environment(viewModel)
                                .environment(favorites)
                        }
                        .buttonStyle(.plain)
                    } else if event.isIndividualSport {
                        NavigationLink {
                            TournamentDetailView(game: event)
                                .environment(viewModel)
                                .environment(favorites)
                        } label: {
                            TournamentScoreView(game: event, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: true)
                                .environment(viewModel)
                        }
                        .buttonStyle(.plain)
                    } else if let homeTeam = gameWithTeams.homeTeam,
                              let awayTeam = gameWithTeams.awayTeam,
                              let homeScore = Int(event.intHomeScore ?? ""),
                              let awayScore = Int(event.intAwayScore ?? "") {
                        GameScoreView(homeTeam: homeTeam, awayTeam: awayTeam, homeScore: homeScore, awayScore: awayScore, game: event, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: true)
                            .environment(viewModel)
                            .environment(favorites)
                    }
                }
            } header: {
                LiveAnimatedView()
            }
        } else {
            EmptyView()
        }
    }
}

