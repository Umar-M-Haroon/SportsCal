//
//  BrowsePage.swift
//  SportsCal (iOS)
//

import SwiftUI
import SportsCalModel

struct BrowsePage: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(storage.orderedSports, id: \.self) { sport in
                    NavigationLink {
                        BrowseSportView(sport: sport)
                            .environment(viewModel)
                            .environment(storage)
                            .environment(favorites)
                    } label: {
                        SportCard(sport: sport, liveCount: viewModel.liveGameCountsBySport[sport] ?? 0)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

private struct SportCard: View {
    let sport: SportType
    let liveCount: Int

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: sport.systemImage)
                .font(.system(size: 36))
                .foregroundColor(sport.color)

            Text(sport.displayName)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(sport.color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(sport.color.opacity(0.3), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if liveCount > 0 {
                Text("\(liveCount)")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .padding(8)
            }
        }
    }
}

private enum BrowseTimeFilter: String, CaseIterable {
    case upcoming = "Upcoming"
    case past = "Past"
}

struct BrowseSportView: View {
    let sport: SportType
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites
    @Environment(SubscriptionManager.self) private var subscriptionManager
    #if os(iOS)
    @Environment(NativeAdManager.self) private var adManager
    #endif

    @State private var browseVM: SportBrowseViewModel?
    @State private var shouldShowSportsCalProAlert = false
    @State private var sheetType: SheetType?
    @State private var timeFilter: BrowseTimeFilter = .upcoming

    var body: some View {
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
            ToolbarItem(placement: .primaryAction) {
                if !storage.enabledSports.contains(sport) {
                    Button {
                        storage.toggleSport(sport, enabled: true)
                        // Merge already-fetched browse data into the main game state
                        // so we don't trigger a full network re-fetch
                        if let games = browseVM?.fetchedGames, !games.isEmpty {
                            viewModel.totalGames = (viewModel.totalGames ?? []) + games
                        }
                        viewModel.filterSports(force: true)
                    } label: {
                        Label("Add to My Sports", systemImage: "plus.circle.fill")
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

    // MARK: - Games List

    @ViewBuilder
    private func gamesList(_ browseVM: SportBrowseViewModel) -> some View {
        List {
            Section {
                Picker("Time", selection: $timeFilter) {
                    ForEach(BrowseTimeFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            // DISABLED: Standings movement chart
//            Section {
//                StandingsChartView(sport: sport)
//                    .environment(favorites)
//                    .listRowInsets(EdgeInsets())
//                    .listRowBackground(Color.clear)
//            }

            // DISABLED: XY Stat Scatter Plot
//            Section {
//                StatScatterView(sport: sport)
//                    .environment(favorites)
//                    .listRowInsets(EdgeInsets())
//                    .listRowBackground(Color.clear)
//            }

            switch timeFilter {
            case .upcoming:
                if !browseVM.liveGames.isEmpty {
                    Section {
                        ForEach(browseVM.liveGames) { gwt in
                            gameRow(gwt, isLive: true)
                        }
                    } header: {
                        LiveAnimatedView()
                    }
                }

                if !browseVM.todayGames.isEmpty {
                    todaySection(browseVM.todayGames)
                }

                #if os(iOS)
                if !subscriptionManager.isPro && AdConfiguration.isEnabled,
                   let ad = adManager.adForSlot(0) {
                    Section {
                        NativeAdCardView(nativeAd: ad)
                    }
                }
                #endif

                if !browseVM.upcomingGames.isEmpty {
                    upcomingOrRecentSections(browseVM.upcomingGames, header: "Upcoming")
                }

                if browseVM.liveGames.isEmpty && browseVM.todayGames.isEmpty &&
                   browseVM.upcomingGames.isEmpty {
                    Section {
                        emptyState
                    }
                    .listRowBackground(Color.clear)
                }

            case .past:
                if !browseVM.recentGames.isEmpty {
                    upcomingOrRecentSections(browseVM.recentGames, header: "Recent Results")
                }

                if browseVM.recentGames.isEmpty {
                    Section {
                        pastEmptyState
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    // MARK: - Section builders

    /// Today section — shows time only since the date is implied
    @ViewBuilder
    private func todaySection(_ games: [GameWithTeams]) -> some View {
        if sport == .racing {
            let groups = groupedByGrandPrix(games)
            ForEach(groups, id: \.key) { gpName, sessions in
                Section {
                    ForEach(sessions) { gwt in
                        gameRowWithDate(gwt, isLive: false, showFullDate: false)
                    }
                } header: {
                    Label(gpName, systemImage: "flag.checkered.2.crossed")
                }
            }
        } else if sport == .tennis {
            let groups = groupedByTournament(games)
            ForEach(groups, id: \.key) { name, matches in
                Section {
                    ForEach(matches) { gwt in
                        gameRowWithDate(gwt, isLive: false, showFullDate: false)
                    }
                } header: {
                    Label(name, systemImage: "tennisball.fill")
                }
            }
        } else {
            Section("Today") {
                ForEach(games) { gwt in
                    gameRowWithDate(gwt, isLive: false, showFullDate: false)
                }
            }
        }
    }

    /// Upcoming or Recent sections — groups F1 races by Grand Prix, shows full dates
    @ViewBuilder
    private func upcomingOrRecentSections(_ games: [GameWithTeams], header: String) -> some View {
        if sport == .racing {
            let groups = groupedByGrandPrix(games)
            ForEach(groups, id: \.key) { gpName, sessions in
                Section {
                    ForEach(sessions) { gwt in
                        gameRowWithDate(gwt, isLive: false, showFullDate: true)
                    }
                } header: {
                    Label(gpName, systemImage: "flag.checkered.2.crossed")
                }
            }
        } else if sport == .tennis {
            let groups = groupedByTournament(games)
            ForEach(groups, id: \.key) { name, matches in
                Section {
                    ForEach(matches) { gwt in
                        gameRowWithDate(gwt, isLive: false, showFullDate: true)
                    }
                } header: {
                    Label(name, systemImage: "tennisball.fill")
                }
            }
        } else {
            Section(header) {
                #if os(iOS)
                if !subscriptionManager.isPro && AdConfiguration.isEnabled {
                    let n = AdConfiguration.adaptiveInterval(forGameCount: games.count)
                    let adIndices = AdInsertionHelper.gameAdIndices(totalGames: games.count, every: n, maxAds: 2)
                    ForEach(Array(games.enumerated()), id: \.element.id) { index, gwt in
                        gameRowWithDate(gwt, isLive: false, showFullDate: true)
                        if adIndices.contains(index), let ad = adManager.adForSlot(index + 1) {
                            NativeAdCardView(nativeAd: ad)
                        }
                    }
                } else {
                    ForEach(games) { gwt in
                        gameRowWithDate(gwt, isLive: false, showFullDate: true)
                    }
                }
                #else
                ForEach(games) { gwt in
                    gameRowWithDate(gwt, isLive: false, showFullDate: true)
                }
                #endif
            }
        }
    }

    // MARK: - Date display

    @ViewBuilder
    private func gameRowWithDate(_ gwt: GameWithTeams, isLive: Bool, showFullDate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !isLive, let date = gwt.game.standardDate {
                GameTimeLabel(date: date, includeDate: showFullDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            gameRow(gwt, isLive: isLive)
        }
    }

    // MARK: - F1 Race Grouping

    /// Extracts the Grand Prix name by stripping known session suffixes from strHomeTeam
    private func raceGrandPrixName(_ game: Game) -> String {
        let name = game.strHomeTeam
        let sessionSuffixes = [
            "Sprint Shootout", "Sprint Qualifying", "Sprint",
            "Qualifying", "Race",
            "FP1", "FP2", "FP3",
            "Practice 1", "Practice 2", "Practice 3",
            "Q", "SQ", "R"
        ]
        for suffix in sessionSuffixes {
            if name.hasSuffix(" \(suffix)") {
                return String(name.dropLast(suffix.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return name
    }

    /// Groups races by Grand Prix name while preserving order of first appearance
    private func groupedByGrandPrix(_ games: [GameWithTeams]) -> [(key: String, sessions: [GameWithTeams])] {
        var result: [(key: String, sessions: [GameWithTeams])] = []
        var seen: [String: Int] = [:]

        for gwt in games {
            let key = raceGrandPrixName(gwt.game)
            if let idx = seen[key] {
                result[idx].sessions.append(gwt)
            } else {
                seen[key] = result.count
                result.append((key: key, sessions: [gwt]))
            }
        }
        return result
    }

    // MARK: - Tennis Tournament Grouping

    private func groupedByTournament(_ games: [GameWithTeams]) -> [(key: String, matches: [GameWithTeams])] {
        var result: [(key: String, matches: [GameWithTeams])] = []
        var seen: [String: Int] = [:]

        for gwt in games {
            let key = gwt.game.tournamentName ?? gwt.game.strLeague ?? "Tennis"
            if let idx = seen[key] {
                result[idx].matches.append(gwt)
            } else {
                seen[key] = result.count
                result.append((key: key, matches: [gwt]))
            }
        }
        return result
    }

    // MARK: - Empty state

    private var emptyState: some View {
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

    private var pastEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No recent results for \(sport.displayName)")
                .foregroundColor(.secondary)
            if storage.hidePastEvents {
                Text("Past events are hidden in Settings. Turn off \"Hide past events\" to see recent results.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Game Row

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
