//
//  BrowsePage.swift
//  SportsCal (iOS)
//

import SwiftUI
import SportsCalModel

/// Value-based destinations on the Browse stack (registered in ContentView). Links that
/// lead to a `Team` push must be value-based too, or the team gets pushed twice.
enum BrowseRoute: Hashable {
    case teams
}

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
            if WorldCupSeason.isActive {
                NavigationLink {
                    WorldCupHubView()
                        .environment(viewModel)
                        .environment(storage)
                        .environment(favorites)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "soccerball")
                            .font(.title2)
                            .foregroundStyle(Color.app(.soccer))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FIFA World Cup 2026").font(.headline)
                            Text("Groups · Bracket · Golden Boot")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.app(.soccer).opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding([.horizontal, .top])

                if let bracket = viewModel.worldCup?.bracket, !bracket.isEmpty {
                    NavigationLink {
                        WorldCupBracketScreen(bracket: bracket)
                            .environment(viewModel)
                            .environment(favorites)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trophy.fill")
                                .font(.title2)
                                .foregroundStyle(Color.app(.soccer))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Knockout Bracket").font(.headline)
                                Text("Round of 32 → Final")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.app(.soccer).opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }

            NavigationLink(value: BrowseRoute.teams) {
                HStack(spacing: 12) {
                    Image(systemName: "person.3.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Teams").font(.headline)
                        Text("Browse & follow any team")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

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
    /// Golf only: the tour being browsed. Nil until the user picks one — see `golfTourSections`.
    @State private var selectedGolfTour: Leagues?
    /// Racing only: the series shown. All share the racing bucket.
    @State private var racingSeries: Leagues = .formula1
    /// Team sports: the day being browsed. Set to `initialDay()` once data arrives.
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    /// Team sports: the league chip picked, nil for all leagues.
    @State private var selectedLeague: Leagues?
    /// League sections the user expanded or collapsed by hand; the rest use `defaultExpanded`.
    @State private var leagueExpansion: [Leagues: Bool] = [:]
    /// Racing groups (remaining races, a season's results) opened past their preview.
    @State private var expandedRaceGroups: Set<String> = []
    /// Racing: the picked series' standings, nil until loaded (F1 reads the view model's).
    @State private var seriesStandings: NetworkHandler.SeriesStandings?

    /// Tennis, golf and racing browse whole events (tournaments, weekends) rather than days.
    private var browsesEvents: Bool {
        sport == .tennis || sport == .golf || sport == .racing
    }

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
                ScrollView {
                    VStack(spacing: .appSpace2) {
                        ForEach(0..<5, id: \.self) { _ in
                            SkeletonRow()
                        }
                    }
                    .padding(.horizontal, .appSpace4)
                    .padding(.top, .appSpace4)
                }
            }
        }
        .navigationTitle(sport.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !browsesEvents, let browseVM, !browseVM.isLoading {
                ToolbarItem(placement: .automatic) {
                    seasonMenu(browseVM)
                }
            }
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
            // Open on a series the user follows when they've hidden F1.
            if sport == .racing, storage.hiddenCompetitions.contains(Leagues.formula1.leagueName),
               let followed = Leagues.allCases.first(where: { $0.isMotorsportSeries && !storage.hiddenCompetitions.contains($0.leagueName) }) {
                racingSeries = followed
            }
            let vm = SportBrowseViewModel(sport: sport, viewModel: viewModel)
            browseVM = vm
            await vm.fetch()
            selectedDay = vm.initialDay()
        }
        #if os(iOS)
        .onAppear {
            if !subscriptionManager.isPro && AdConfiguration.isEnabled {
                adManager.refreshOnAppear()
            }
        }
        #endif
    }

    // MARK: - Games List

    /// Just the picked racing series.
    private func inSelectedSeries(_ games: [GameWithTeams]) -> [GameWithTeams] {
        games.filter { $0.game.knownLeague == racingSeries }
    }

    @ViewBuilder
    private func gamesList(_ browseVM: SportBrowseViewModel) -> some View {
        if sport == .racing {
            racingBrowseList(browseVM)
        } else if !browsesEvents {
            dayBrowseList(browseVM)
        } else {
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

            if sport == .tennis {
                // Tennis: drill-in tournament hub (group all matches into tournaments).
                tennisTournamentSections(browseVM)
            } else if sport == .golf {
                // Golf: pick a tour, then that tour's tournaments.
                golfTourSections(browseVM)
            }
        }
        }
    }

    // MARK: - Tennis tournament hub

    private struct TennisTournament: Identifiable {
        var id: String { name }
        let name: String
        let games: [Game]
        let startDate: Date?
        let endDate: Date?
        let isLive: Bool
        /// Tours represented in this tournament. Combined events (Grand Slams, Indian Wells…)
        /// contain both ATP + WTA; single-tour events contain one. Drives the card badge and the
        /// Men's/Women's split inside `TournamentHubView`.
        let tours: Set<Leagues>

        /// Short tour badge: "ATP", "WTA", or "ATP · WTA" for combined events. Nil if unknown.
        var tourBadge: String? {
            let parts = [Leagues.atp, Leagues.wta].filter { tours.contains($0) }
            guard !parts.isEmpty else { return nil }
            return parts.map { $0 == .atp ? "ATP" : "WTA" }.joined(separator: " · ")
        }
    }

    /// Groups tennis match games into tournaments (by tournamentName), preserving order.
    private func tennisTournaments(from games: [Game]) -> [TennisTournament] {
        var buckets: [String: [Game]] = [:]
        var order: [String] = []
        for game in games {
            guard let lg = game.idLeague, let i = Int(lg),
                  let league = Leagues(rawValue: i), league.isTennis else { continue }
            let name = game.tournamentName ?? game.strLeague ?? "Tennis"
            if buckets[name] == nil { order.append(name) }
            buckets[name, default: []].append(game)
        }
        return order.map { name in
            let gs = buckets[name] ?? []
            let dates = gs.compactMap { $0.standardDate }
            // From the draw, not `idLeague` — a row cached before draws existed carries a
            // stale league, and mixed doubles counts toward both tours.
            let tours = Set(gs.flatMap { $0.tennisTours })
            return TennisTournament(
                name: name, games: gs,
                startDate: dates.min(), endDate: dates.max(),
                isLive: gs.contains { $0.strStatus?.lowercased() == "in" },
                tours: tours
            )
        }
    }

    // MARK: - Day browse (team sports)

    /// Team sports browse like the home page, scoped to one sport: a day strip, league chips,
    /// then that day's games grouped into collapsible league sections. One day at a time keeps
    /// the page short however busy the sport is, and any date stays reachable.
    private func dayBrowseList(_ browseVM: SportBrowseViewModel) -> some View {
        let leagues = browseVM.leagues
        let league = selectedLeague.flatMap { leagues.contains($0) ? $0 : nil }
        let isToday = Calendar.current.isDateInToday(selectedDay)
        let live = isToday ? browseVM.liveGames.filter { league == nil || $0.game.knownLeague == league } : []
        let dayGames = browseVM.games(on: selectedDay).filter { league == nil || $0.game.knownLeague == league }
        let favoriteGames = dayGames.filter { favorites.contains($0.game) }
        let sections = leagueSections(dayGames.filter { !favorites.contains($0.game) }, order: leagues)

        return List {
            Section {
                if leagues.count > 1 {
                    leagueChipStrip(leagues, selected: league)
                }
                DayChipStrip(
                    selectedDate: $selectedDay,
                    datesWithGames: browseVM.datesWithGames(league: league)
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if let league, sport == .soccer {
                Section {
                    soccerHubLink(league)
                }
            }

            if !live.isEmpty {
                Section {
                    ForEach(live) { gwt in
                        gameRow(gwt, isLive: true)
                    }
                } header: {
                    LiveAnimatedView()
                }
            }

            if !favoriteGames.isEmpty {
                Section {
                    ForEach(favoriteGames) { gwt in
                        dayGroupedRow(gwt)
                    }
                } header: {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text("Your Teams")
                            .font(.headline)
                    }
                }
            }

            #if os(iOS)
            // Ads only once a day has enough games to sit between; a one-game final
            // shouldn't be sandwiched by two.
            if !subscriptionManager.isPro && AdConfiguration.isEnabled,
               dayGames.count >= 4, let ad = adManager.adForSlot(0) {
                Section {
                    NativeAdCardView(nativeAd: ad)
                }
            }
            #endif

            ForEach(Array(sections.enumerated()), id: \.element.league) { index, section in
                let isExpanded = leagueExpansion[section.league]
                    ?? defaultExpanded(section.league, index: index, in: sections, filtered: league != nil)
                Section {
                    if isExpanded {
                        ForEach(section.games) { gwt in
                            dayGroupedRow(gwt)
                        }
                    }
                } header: {
                    leagueSectionHeader(section.league, count: section.games.count, isExpanded: isExpanded)
                }
                #if os(iOS)
                if index == 0, sections.count > 1, dayGames.count >= 8,
                   !subscriptionManager.isPro && AdConfiguration.isEnabled,
                   let ad = adManager.adForSlot(1) {
                    Section {
                        NativeAdCardView(nativeAd: ad)
                    }
                }
                #endif
            }

            if live.isEmpty && dayGames.isEmpty {
                Section {
                    emptyDay(browseVM, league: league)
                }
                .listRowBackground(Color.clear)
            }
        }
        #if os(iOS)
        .listSectionSpacing(.compact)
        .gesture(daySwipeGesture)
        #endif
    }

    /// Jumps the day strip between seasons: the current one opens where the page would,
    /// a past one on its final matchday (the final, the last round). Only for one league —
    /// leagues label seasons differently ("2025-2026" vs MLS's "2026") — and hidden with one season.
    @ViewBuilder
    private func seasonMenu(_ browseVM: SportBrowseViewModel) -> some View {
        let league = selectedLeague.flatMap { browseVM.leagues.contains($0) ? $0 : nil }
            ?? (browseVM.leagues.count == 1 ? browseVM.leagues.first : nil)
        let seasons = league.map { browseVM.seasons(league: $0) } ?? []
        if seasons.count > 1 {
            let showing = seasons.first { $0.firstDay <= selectedDay && selectedDay <= $0.lastDay }
            Menu {
                ForEach(seasons, id: \.self) { span in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDay = span == seasons.first ? browseVM.initialDay() : span.lastDay
                        }
                    } label: {
                        if span == showing {
                            Label(Game.seasonDisplayName(span.season), systemImage: "checkmark")
                        } else {
                            Text(Game.seasonDisplayName(span.season))
                        }
                    }
                }
            } label: {
                Label(showing.map { Game.seasonDisplayName($0.season) } ?? "Season",
                      systemImage: "calendar.badge.clock")
            }
            .accessibilityLabel("Season")
        }
    }

    /// Groups a day's games by league: leagues the user follows first, then the feed's order
    /// (busiest first).
    private func leagueSections(_ games: [GameWithTeams], order: [Leagues]) -> [(league: Leagues, games: [GameWithTeams])] {
        let grouped = Dictionary(grouping: games.filter { $0.game.knownLeague != nil }) { $0.game.knownLeague! }
        return order
            .filter { grouped[$0] != nil }
            .sorted { isFollowed($0) && !isFollowed($1) }
            .map { (league: $0, games: grouped[$0] ?? []) }
    }

    /// The sport is on the user's schedule and the league isn't hidden from it.
    private func isFollowed(_ league: Leagues) -> Bool {
        storage.enabledSports.contains(sport) && !storage.hiddenCompetitions.contains(league.leagueName)
    }

    /// Followed leagues open; others start collapsed so a busy day stays scannable. With one
    /// league picked, or when nothing is followed, the first section opens.
    private func defaultExpanded(_ league: Leagues, index: Int,
                                 in sections: [(league: Leagues, games: [GameWithTeams])],
                                 filtered: Bool) -> Bool {
        if filtered || sections.count == 1 { return true }
        if isFollowed(league) { return true }
        return index == 0 && !sections.contains { isFollowed($0.league) }
    }

    private func leagueSectionHeader(_ league: Leagues, count: Int, isExpanded: Bool) -> some View {
        Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    leagueExpansion[league] = !isExpanded
                }
            } label: {
                HStack {
                    Text(league.leagueName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("(\(count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    /// "All" plus each league in the feed. Picking one scopes the day strip's dots and the
    /// list to that league.
    private func leagueChipStrip(_ leagues: [Leagues], selected: Leagues?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                leagueChip("All", isSelected: selected == nil) { selectedLeague = nil }
                ForEach(leagues, id: \.self) { league in
                    leagueChip(league.racingShortName ?? league.leagueName, isSelected: selected == league) {
                        selectedLeague = league
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func leagueChip(_ title: String, isSelected: Bool, isHidden: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 4) {
                if isHidden {
                    Image(systemName: "eye.slash")
                        .font(.caption2)
                }
                Text(title)
            }
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(isSelected ? Color.app(sport).opacity(0.2) : Color.gray.opacity(0.12)))
                .overlay(Capsule().strokeBorder(isSelected ? Color.app(sport) : .clear, lineWidth: 1.5))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Soccer competitions have a hub (table, matches, top scorers); link it once one is picked.
    private func soccerHubLink(_ league: Leagues) -> some View {
        NavigationLink {
            SoccerCompetitionHubView(league: league)
                .environment(viewModel)
                .environment(favorites)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.number")
                    .foregroundStyle(Color.app(.soccer))
                VStack(alignment: .leading, spacing: 2) {
                    Text(league.leagueName).font(.headline)
                    Text("Table · Matches · Top Scorers")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// No games on the picked day: say so and offer the nearest matchdays either side.
    private func emptyDay(_ browseVM: SportBrowseViewModel, league: Leagues?) -> some View {
        let previous = browseVM.adjacentDayWithGames(from: selectedDay, league: league, forward: false)
        let next = browseVM.adjacentDayWithGames(from: selectedDay, league: league, forward: true)
        return VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No \(league?.leagueName ?? sport.displayName) games \(relativeDayPhrase(selectedDay))")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                if let previous {
                    Button {
                        withAnimation { selectedDay = previous }
                    } label: {
                        Label(previous.formatted(.dateTime.month(.abbreviated).day()), systemImage: "chevron.left")
                    }
                }
                if let next {
                    Button {
                        withAnimation { selectedDay = next }
                    } label: {
                        HStack(spacing: 4) {
                            Text(next.formatted(.dateTime.month(.abbreviated).day()))
                            Image(systemName: "chevron.right")
                        }
                    }
                }
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    #if os(iOS)
    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      let day = Calendar.current.date(byAdding: .day,
                                                      value: value.translation.width < 0 ? 1 : -1,
                                                      to: selectedDay) else { return }
                withAnimation(.easeInOut(duration: 0.2)) { selectedDay = day }
            }
    }
    #endif

    @ViewBuilder
    private func tennisTournamentSections(_ browseVM: SportBrowseViewModel) -> some View {
        let tournaments = tennisTournaments(from: browseVM.fetchedGames)
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let filtered: [TennisTournament] = {
            switch timeFilter {
            case .upcoming:
                return tournaments
                    .filter { ($0.endDate ?? .distantFuture) >= startOfToday }
                    .sorted {
                        if $0.isLive != $1.isLive { return $0.isLive }
                        return ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture)
                    }
            case .past:
                return tournaments
                    .filter { ($0.endDate ?? .distantPast) < startOfToday }
                    .sorted { ($0.endDate ?? .distantPast) > ($1.endDate ?? .distantPast) }
            }
        }()

        if filtered.isEmpty {
            Section {
                if timeFilter == .past { pastEmptyState } else { emptyState }
            }
            .listRowBackground(Color.clear)
        } else {
            Section(timeFilter == .upcoming ? "Tournaments" : "Past Tournaments") {
                ForEach(filtered) { tournament in
                    NavigationLink {
                        TournamentHubView(
                            tournamentName: tournament.name, games: tournament.games,
                            shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                            sheetType: $sheetType
                        )
                        .environment(viewModel)
                        .environment(favorites)
                    } label: {
                        tennisTournamentCard(tournament)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func tennisTournamentCard(_ tournament: TennisTournament) -> some View {
        tournamentCard(
            systemImage: "tennisball.fill",
            name: tournament.name,
            badge: tournament.tourBadge,
            dateText: dateRangeText(tournament.startDate, tournament.endDate),
            isLive: tournament.isLive
        )
    }

    /// One row per tournament in the tennis and golf lists: sport icon, name, an optional tint
    /// badge (tour for tennis, "Major" for golf), date range and an optional detail line.
    @ViewBuilder
    private func tournamentCard(systemImage: String, name: String, badge: String?, dateText: String,
                                detail: String? = nil, isLive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.app(sport))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.app(sport))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.app(sport).opacity(0.15), in: Capsule())
                    }
                    Text(dateText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isLive {
                Text("LIVE")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// "Jun 1 – 14" / "Jun 28 – Jul 5" / single day fallback.
    private func dateRangeText(_ start: Date?, _ end: Date?) -> String {
        guard let start else { return "" }
        guard let end, !Calendar.current.isDate(start, inSameDayAs: end) else {
            return start.formatted(.dateTime.month(.abbreviated).day())
        }
        let cal = Calendar.current
        if cal.component(.month, from: start) == cal.component(.month, from: end) {
            return "\(start.formatted(.dateTime.month(.abbreviated).day()))–\(cal.component(.day, from: end))"
        }
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    // MARK: - Golf tours

    /// Golf browse: a tour strip (only tours with events), then the selected tour's
    /// tournaments for the Upcoming/Past filter. Like tennis browse, this is the unfiltered
    /// catalog — a tour hidden from the schedule is still browsable (so you can find it again),
    /// but it isn't opened on by default and says it's hidden; the coverage preference isn't
    /// applied either, and majors are badged instead.
    @ViewBuilder
    private func golfTourSections(_ browseVM: SportBrowseViewModel) -> some View {
        let games = browseVM.fetchedGames
        let tours = GolfTourBoard.tours(in: games)
        let hidden = Set(storage.hiddenCompetitions)
        if let tour = selectedGolfTour.flatMap({ tours.contains($0) ? $0 : nil })
            ?? GolfTourBoard.defaultTour(in: tours, hidden: hidden) {
            if tours.count > 1 {
                Section {
                    golfTourStrip(tours, selected: tour, hidden: hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

            let events = GolfTourBoard.events(for: tour, in: games)
            let startOfToday = Calendar.current.startOfDay(for: Date())
            let listed = timeFilter == .upcoming
                ? GolfTourBoard.upcoming(events, startOfToday: startOfToday)
                : GolfTourBoard.past(events, startOfToday: startOfToday)
            let isHidden = hidden.contains(tour.leagueName)

            if listed.isEmpty {
                Section {
                    if timeFilter == .past { pastEmptyState } else { emptyState }
                } footer: {
                    if isHidden { hiddenTourFooter(tour) }
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(listed) { game in
                        NavigationLink {
                            TournamentDetailView(game: game)
                                .environment(viewModel)
                                .environment(favorites)
                        } label: {
                            golfTournamentCard(game)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(timeFilter == .upcoming ? tour.leagueName : "\(tour.leagueName) Results")
                } footer: {
                    if isHidden { hiddenTourFooter(tour) }
                }
            }
        } else {
            Section {
                if timeFilter == .past { pastEmptyState } else { emptyState }
            }
            .listRowBackground(Color.clear)
        }
    }

    private func hiddenTourFooter(_ tour: Leagues) -> some View {
        Text("\(tour.leagueName) is hidden from your schedule. Show it again in Settings.")
    }

    private func golfTourStrip(_ tours: [Leagues], selected: Leagues, hidden: Set<String>) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tours, id: \.self) { tour in
                        let isSelected = tour == selected
                        Button {
                            selectedGolfTour = tour
                        } label: {
                            HStack(spacing: 4) {
                                if hidden.contains(tour.leagueName) {
                                    Image(systemName: "eye.slash")
                                        .font(.caption2)
                                }
                                Text(tour.golfTourShortName ?? tour.leagueName)
                                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(isSelected ? Color.app(.golf).opacity(0.2) : Color.gray.opacity(0.12))
                            )
                            .overlay(
                                Capsule().strokeBorder(isSelected ? Color.app(.golf) : .clear, lineWidth: 1.5)
                            )
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(tour)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
    }

    private func golfTournamentCard(_ game: Game) -> some View {
        let span = game.eventDaySpan
        return tournamentCard(
            systemImage: "figure.golf",
            name: game.strHomeTeam,
            badge: game.eventTier == .major ? "Major" : nil,
            dateText: dateRangeText(span?.first, span?.last),
            detail: golfDetail(game),
            isLive: GolfTourBoard.isLive(game)
        )
    }

    /// Leader while live, winner once finished, else the venue.
    private func golfDetail(_ game: Game) -> String? {
        let leader: String? = {
            let name = game.leaderboardEntries?.first?.name ?? game.strAwayTeam
            // TheSportsDB rows fall back to the event name when there are no players.
            guard !name.isEmpty, name != "TBD", name != game.strHomeTeam else { return nil }
            return name
        }()
        if GolfTourBoard.isLive(game), let leader {
            if let score = game.intAwayScore, !score.isEmpty { return "Leader: \(leader) (\(score))" }
            return "Leader: \(leader)"
        }
        if game.hasDoneStatus, let leader { return "Winner: \(leader)" }
        return game.venueName
    }

    // MARK: - Day rows

    /// Row for a day-grouped section. Team sports use the dense `CompactGameRowView`
    /// (time/score on the right). Individual sports fall back to the full row plus a
    /// time/tournament caption.
    @ViewBuilder
    private func dayGroupedRow(_ gwt: GameWithTeams) -> some View {
        let game = gwt.game
        if !game.isIndividualSport, !game.isRace,
           let home = gwt.homeTeam, let away = gwt.awayTeam {
            CompactGameRowView(
                homeTeam: home, awayTeam: away, game: game,
                shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                sheetType: $sheetType, isLive: false
            )
            .environment(viewModel)
            .environment(favorites)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if let date = game.standardDate {
                        GameTimeLabel(date: date, includeDate: false)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if sport == .tennis,
                       let tournament = game.tournamentName ?? game.strLeague {
                        Text("· \(tournament)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                gameRow(gwt, isLive: false)
            }
        }
    }

    /// "today" / "tomorrow" / "yesterday" / "on Saturday, Oct 11", to finish a sentence.
    private func relativeDayPhrase(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) || cal.isDateInTomorrow(day) || cal.isDateInYesterday(day) {
            return dayLabel(day).lowercased()
        }
        return "on \(dayLabel(day))"
    }

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = cal.component(.year, from: day) == cal.component(.year, from: Date())
        if sameYear {
            return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        } else {
            return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        }
    }

    // MARK: - Racing

    /// Racing reads as one series' season: series chips, what's live, the next weekend,
    /// standings, then the rest of the calendar and this season's results — no
    /// Upcoming/Past toggle, and long groups preview a few rows behind "Show all".
    private func racingBrowseList(_ browseVM: SportBrowseViewModel) -> some View {
        let live = inSelectedSeries(browseVM.liveGames)
        let ahead = inSelectedSeries(browseVM.todayGames + browseVM.upcomingGames)
        let seasons = groupedBySeason(inSelectedSeries(browseVM.recentGames))
        let hidden = Set(storage.hiddenCompetitions)

        return List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Leagues.allCases.filter(\.isRacing), id: \.self) { series in
                            leagueChip(series.racingShortName ?? series.leagueName,
                                       isSelected: series == racingSeries,
                                       isHidden: hidden.contains(series.leagueName)) {
                                racingSeries = series
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if racingSeries == .formula1 {
                // One-time pointer to the other series for F1 fans (dismissed for good once acted on).
                NASCARPromoSection()
            } else if hidden.contains(racingSeries.leagueName) {
                Section {
                    RacingSeriesHiddenNotice(series: racingSeries)
                }
            }

            if !live.isEmpty {
                Section {
                    ForEach(live) { gwt in
                        gameRow(gwt, isLive: true)
                    }
                } header: {
                    LiveAnimatedView()
                }
            }

            if let next = ahead.first {
                Section("Next Up") {
                    raceRow(next)
                }
            }

            if hasStandings {
                Section {
                    NavigationLink {
                        RacingStandingsScreen(series: racingSeries, f1: viewModel.f1Standings,
                                              standings: seriesStandings)
                    } label: {
                        Label("\(racingSeries.racingShortName ?? racingSeries.leagueName) Standings",
                              systemImage: "list.number")
                    }
                }
            }

            #if os(iOS)
            if !subscriptionManager.isPro && AdConfiguration.isEnabled,
               let ad = adManager.adForSlot(0) {
                Section {
                    NativeAdCardView(nativeAd: ad)
                }
            }
            #endif

            let remaining = Array(ahead.dropFirst())
            if !remaining.isEmpty {
                racePreviewSection(remaining, key: "remaining", preview: 4) {
                    Text("Coming Up (\(remaining.count))")
                }
            }

            ForEach(Array(seasons.enumerated()), id: \.element.year) { index, season in
                racePreviewSection(season.games, key: "season-\(season.year)", preview: index == 0 ? 3 : 0) {
                    Label("\(String(season.year)) Results (\(season.games.count))",
                          systemImage: "flag.checkered.2.crossed")
                }
            }

            if live.isEmpty && ahead.isEmpty && seasons.isEmpty {
                Section {
                    emptyState
                }
                .listRowBackground(Color.clear)
            }
        }
        #if os(iOS)
        .listSectionSpacing(.compact)
        #endif
        .task(id: racingSeries) {
            seriesStandings = nil
            guard racingSeries != .formula1 else { return }
            seriesStandings = try? await NetworkHandler.fetchSeriesStandings(racingSeries)
        }
    }

    /// F1's standings come with the schedule; the other series' are fetched per pick.
    private var hasStandings: Bool {
        racingSeries == .formula1 ? viewModel.f1Standings != nil : seriesStandings != nil
    }

    /// The first `preview` races, then a toggle for the rest. A zero preview starts collapsed
    /// behind the header (older seasons).
    @ViewBuilder
    private func racePreviewSection(_ games: [GameWithTeams], key: String, preview: Int,
                                    @ViewBuilder header: () -> some View) -> some View {
        let isExpanded = expandedRaceGroups.contains(key)
        let shown = isExpanded ? games : Array(games.prefix(preview))
        Section {
            ForEach(shown) { gwt in
                raceRow(gwt)
            }
            if games.count > shown.count || (isExpanded && games.count > preview) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded { expandedRaceGroups.remove(key) } else { expandedRaceGroups.insert(key) }
                    }
                } label: {
                    Text(isExpanded ? "Show fewer" : (preview == 0 ? "Show \(games.count) races" : "Show all \(games.count)"))
                        .font(.subheadline)
                }
            }
        } header: {
            header()
        }
    }

    // MARK: - Racing rows

    @ViewBuilder
    private func raceRow(_ gwt: GameWithTeams) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let range = raceWeekendRangeLabel(gwt.game) {
                Text(range)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            gameRow(gwt, isLive: false)
        }
    }

    /// Weekend date range from session dates, e.g. "Jun 5–7" or "Jun 28 – Jul 1".
    private func raceWeekendRangeLabel(_ game: Game) -> String? {
        let dates = game.sessionDates.sorted()
        guard let first = dates.first, let last = dates.last else {
            return game.standardDate.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
        }
        let cal = Calendar.current
        if cal.isDate(first, inSameDayAs: last) {
            return first.formatted(.dateTime.month(.abbreviated).day())
        }
        if cal.component(.month, from: first) == cal.component(.month, from: last) {
            let firstPart = first.formatted(.dateTime.month(.abbreviated).day())
            let lastDay = cal.component(.day, from: last)
            return "\(firstPart)–\(lastDay)"
        }
        let firstPart = first.formatted(.dateTime.month(.abbreviated).day())
        let lastPart = last.formatted(.dateTime.month(.abbreviated).day())
        return "\(firstPart) – \(lastPart)"
    }

    /// Groups games by their race-day year, descending; rows within a season newest-first.
    private func groupedBySeason(_ games: [GameWithTeams]) -> [(year: Int, games: [GameWithTeams])] {
        var buckets: [Int: [GameWithTeams]] = [:]
        for gwt in games {
            let date = gwt.game.effectiveEndDate ?? gwt.game.standardDate
            let year = date.map { Calendar.current.component(.year, from: $0) } ?? 0
            buckets[year, default: []].append(gwt)
        }
        return buckets
            .sorted { $0.key > $1.key }
            .map { year, games in
                let sorted = games.sorted {
                    ($0.game.effectiveEndDate ?? $0.game.standardDate ?? .distantPast) >
                    ($1.game.effectiveEndDate ?? $1.game.standardDate ?? .distantPast)
                }
                return (year: year, games: sorted)
            }
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

/// A racing series' championship, pushed from racing browse.
private struct RacingStandingsScreen: View {
    let series: Leagues
    let f1: F1Standings?
    let standings: NetworkHandler.SeriesStandings?
    @State private var showAll = false

    var body: some View {
        ScrollView {
            Group {
                if series == .formula1, let f1 {
                    F1TitleFightCard(standings: f1)
                } else {
                    switch standings {
                    case .drivers(let table):
                        NASCARStandingsCard(standings: table, showAll: $showAll)
                    case .classes(let tables):
                        ClassStandingsCard(standings: tables)
                    case nil:
                        ContentUnavailableView("No Standings", systemImage: "list.number")
                    }
                }
            }
            .padding()
        }
        .navigationTitle("\(series.racingShortName ?? series.leagueName) Standings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
