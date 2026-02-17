//
//  SportBrowseSheet.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel

struct SportBrowseSheet: View {
    let sport: SportType
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites
    @Environment(\.dismiss) private var dismiss

    @State private var browseVM: SportBrowseViewModel?
    @State private var shouldShowSportsCalProAlert = false
    @State private var sheetType: SheetType?

    var body: some View {
        NavigationStack {
            Group {
                if let browseVM, !browseVM.isLoading {
                    if let error = browseVM.errorMessage,
                       browseVM.liveGames.isEmpty && browseVM.todayGames.isEmpty &&
                       browseVM.upcomingGames.isEmpty && browseVM.recentGames.isEmpty {
                        ContentUnavailableView {
                            Label("Unable to Load", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Retry") {
                                Task { await browseVM.fetch() }
                            }
                        }
                    } else {
                        gamesList(browseVM)
                    }
                } else {
                    ProgressView("Loading \(sport.displayName)...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(sport.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !storage.enabledSports.contains(sport) {
                        Button {
                            storage.toggleSport(sport, enabled: true)
                            if let games = browseVM?.fetchedGames, !games.isEmpty {
                                viewModel.totalGames = (viewModel.totalGames ?? []) + games
                            }
                            viewModel.filterSports(force: true)
                            dismiss()
                        } label: {
                            Label("Add to My Sports", systemImage: "plus.circle.fill")
                        }
                    }
                }
            }
        }
        .task {
            let vm = SportBrowseViewModel(sport: sport, viewModel: viewModel)
            browseVM = vm
            await vm.fetch()
        }
    }

    @ViewBuilder
    private func gamesList(_ browseVM: SportBrowseViewModel) -> some View {
        List {
            // Live section
            if !browseVM.liveGames.isEmpty {
                Section {
                    ForEach(browseVM.liveGames) { gwt in
                        gameRow(gwt, isLive: true)
                    }
                } header: {
                    LiveAnimatedView()
                }
            }

            // Today section
            if !browseVM.todayGames.isEmpty {
                Section("Today") {
                    ForEach(browseVM.todayGames) { gwt in
                        gameRow(gwt, isLive: false)
                    }
                }
            }

            // Upcoming section
            if !browseVM.upcomingGames.isEmpty {
                Section("Upcoming") {
                    ForEach(browseVM.upcomingGames) { gwt in
                        gameRow(gwt, isLive: false)
                    }
                }
            }

            // Recent Results section
            if !browseVM.recentGames.isEmpty {
                Section("Recent Results") {
                    ForEach(browseVM.recentGames) { gwt in
                        gameRow(gwt, isLive: false)
                    }
                }
            }

            // Empty state
            if browseVM.liveGames.isEmpty && browseVM.todayGames.isEmpty &&
               browseVM.upcomingGames.isEmpty && browseVM.recentGames.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: sport.systemImage)
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No games found for \(sport.displayName)")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private func gameRow(_ gwt: GameWithTeams, isLive: Bool) -> some View {
        let game = gwt.game
        if game.isRace {
            NavigationLink {
                RaceDetailView(game: game)
                    .environment(viewModel)
                    .environment(favorites)
            } label: {
                RaceScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: isLive)
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
                TennisMatchScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: isLive)
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
                TournamentScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: isLive)
                    .environment(viewModel)
            }
            .buttonStyle(.plain)
        } else if let homeTeam = gwt.homeTeam, let awayTeam = gwt.awayTeam {
            if let homeScore = Int(game.intHomeScore ?? ""),
               let awayScore = Int(game.intAwayScore ?? "") {
                GameScoreView(
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    homeScore: homeScore,
                    awayScore: awayScore,
                    game: game,
                    shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                    sheetType: $sheetType,
                    isLive: isLive
                )
                .environment(favorites)
                .environment(viewModel)
            } else {
                UpcomingGameView(
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    game: game,
                    showCountdown: .constant(storage.showStartTime),
                    shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                    sheetType: $sheetType,
                    dateFormat: storage.dateFormat
                )
                .environment(favorites)
            }
        }
    }
}
