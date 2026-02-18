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
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites
    @Environment(GameViewModel.self) private var viewModel
    @Binding var sheetType: SheetType?

    @State var shouldShowSportsCalProAlert: Bool = false
    @State private var collapsedSportSections: Set<SportType> = []

    private var allGames: [Game] {
        listGames.flatMap { $0.value }
    }

    private var favoriteGames: [Game] {
        allGames.filter { favorites.contains($0) }
    }

    private var nonFavoriteGamesBySport: [SportType: [Game]] {
        let nonFavorites = allGames.filter { !favorites.contains($0) }
        return Dictionary(grouping: nonFavorites, by: { sportForGame($0) ?? .soccer })
    }

    var body: some View {
        NavigationStack {
            Group {
                if liveGames.isEmpty && allGames.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No games scheduled")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // Live games
                        if !liveGames.isEmpty {
                            Section {
                                ForEach(liveGames, id: \.id) { event in
                                    if event.isRace {
                                        NavigationLink {
                                            RaceDetailView(game: event)
                                                .environment(viewModel)
                                                .environment(favorites)
                                        } label: {
                                            RaceScoreView(game: event, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: true)
                                                .environment(viewModel)
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
                                    } else if let homeScore = Int(event.intHomeScore ?? ""),
                                       let awayScore = Int(event.intAwayScore ?? ""),
                                       let (homeTeam, awayTeam) = viewModel.getTeams(for: event) {
                                        GameScoreView(homeTeam: homeTeam, awayTeam: awayTeam, homeScore: homeScore, awayScore: awayScore, game: event, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: true)
                                            .environment(viewModel)
                                            .environment(favorites)
                                    }
                                }
                            } header: {
                                LiveAnimatedView()
                            }
                        }

                        // Favorites section
                        if !favoriteGames.isEmpty {
                            Section {
                                ForEach(favoriteGames, id: \.id) { game in
                                    gameRow(game: game)
                                }
                            } header: {
                                HStack {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                    Text("Your Teams")
                                        .font(.headline)
                                    Text("(\(favoriteGames.count))")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // Games grouped by sport
                        ForEach(SportType.allCases, id: \.self) { sport in
                            if let games = nonFavoriteGamesBySport[sport], !games.isEmpty {
                                let isCollapsed = collapsedSportSections.contains(sport)
                                Section {
                                    if !isCollapsed {
                                        ForEach(games, id: \.id) { game in
                                            gameRow(game: game)
                                        }
                                    }
                                } header: {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if collapsedSportSections.contains(sport) {
                                                collapsedSportSections.remove(sport)
                                            } else {
                                                collapsedSportSections.insert(sport)
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: sport.systemImage)
                                                .foregroundColor(sport.color)
                                            Text(sport.displayName)
                                                .font(.headline)
                                            Text("(\(games.count))")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
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
            #if os(iOS)
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle(navigationTitleText)
        }
    }

    private var navigationTitleText: String {
        guard let first = listGames.first?.key else { return "" }
        return first.formatted(format: viewModel.appStorage.dateFormat, isRelative: viewModel.appStorage.useRelativeValue)
    }

    @ViewBuilder
    private func gameRow(game: Game) -> some View {
        @Bindable var bindableStorage = storage
        
        if game.isRace {
            NavigationLink {
                RaceDetailView(game: game)
                    .environment(viewModel)
                    .environment(favorites)
            } label: {
                RaceScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: false)
                    .environment(viewModel)
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
        } else if let (homeTeam, awayTeam) = viewModel.getTeams(for: game) {
            if let homeScore = Int(game.intHomeScore ?? ""), let awayScore = Int(game.intAwayScore ?? "") {
                GameScoreView(homeTeam: homeTeam, awayTeam: awayTeam, homeScore: homeScore, awayScore: awayScore, game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: false)
                    .environment(favorites)
                    .environment(viewModel)
            } else {
                UpcomingGameView(homeTeam: homeTeam, awayTeam: awayTeam, game: game, showCountdown: $bindableStorage.showStartTime, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, dateFormat: storage.dateFormat)
                    .environment(favorites)
            }
        }
    }

    private func sportForGame(_ game: Game) -> SportType? {
        guard let league = game.idLeague,
              let leagueInt = Int(league),
              let foundLeague = Leagues(rawValue: leagueInt) else {
            return nil
        }
        return SportType(league: foundLeague)
    }
}
