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
    /// Football only: NFL or college. Both share the football bucket, and a college
    /// Saturday alone would bury the NFL's week.
    @State private var footballLeague: Leagues = .nfl
    /// Racing only: the series shown. All share the racing bucket.
    @State private var racingSeries: Leagues = .formula1

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
            if sport == .nfl, storage.shouldShowCFB, !storage.shouldShowNFL {
                footballLeague = .ncaaf
            }
            // Open on a series the user follows when they've hidden F1.
            if sport == .racing, storage.hiddenCompetitions.contains(Leagues.formula1.leagueName),
               let followed = Leagues.allCases.first(where: { $0.isMotorsportSeries && !storage.hiddenCompetitions.contains($0.leagueName) }) {
                racingSeries = followed
            }
            let vm = SportBrowseViewModel(sport: sport, viewModel: viewModel)
            browseVM = vm
            await vm.fetch()
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

    /// For football and racing, just the picked league or series; every other sport
    /// passes through.
    private func inSelectedLeague(_ games: [GameWithTeams]) -> [GameWithTeams] {
        let league: Leagues
        switch sport {
        case .nfl: league = footballLeague
        case .racing: league = racingSeries
        default: return games
        }
        let id = "\(league.rawValue)"
        return games.filter { $0.game.idLeague == id }
    }

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
                if sport == .nfl {
                    Picker("League", selection: $footballLeague) {
                        Text("NFL").tag(Leagues.nfl)
                        Text("College").tag(Leagues.ncaaf)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
                if sport == .racing {
                    Picker("Series", selection: $racingSeries) {
                        ForEach(Leagues.allCases.filter(\.isRacing), id: \.self) { series in
                            Text(series.racingShortName ?? series.leagueName).tag(series)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
            }

            if sport == .racing {
                if racingSeries == .formula1 {
                    // One-time pointer to the other series for F1 fans (dismissed for good once acted on).
                    NASCARPromoSection()
                } else if storage.hiddenCompetitions.contains(racingSeries.leagueName) {
                    Section {
                        RacingSeriesHiddenNotice(series: racingSeries)
                    }
                }
            }

            if sport == .soccer {
                soccerCompetitionsSection(browseVM)
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
            } else {
            let liveGames = inSelectedLeague(browseVM.liveGames)
            let todayGames = inSelectedLeague(browseVM.todayGames)
            let upcomingGames = inSelectedLeague(browseVM.upcomingGames)
            let recentGames = inSelectedLeague(browseVM.recentGames)
            switch timeFilter {
            case .upcoming:
                if !liveGames.isEmpty {
                    Section {
                        ForEach(liveGames) { gwt in
                            gameRow(gwt, isLive: true)
                        }
                    } header: {
                        LiveAnimatedView()
                    }
                }

                if !todayGames.isEmpty {
                    todaySection(todayGames)
                }

                #if os(iOS)
                if !subscriptionManager.isPro && AdConfiguration.isEnabled,
                   let ad = adManager.adForSlot(0) {
                    Section {
                        NativeAdCardView(nativeAd: ad)
                    }
                }
                #endif

                if !upcomingGames.isEmpty {
                    upcomingSections(upcomingGames)
                }

                if liveGames.isEmpty && todayGames.isEmpty &&
                   upcomingGames.isEmpty {
                    Section {
                        emptyState
                    }
                    .listRowBackground(Color.clear)
                }

            case .past:
                if !recentGames.isEmpty {
                    pastSections(recentGames)
                }

                if recentGames.isEmpty {
                    Section {
                        pastEmptyState
                    }
                    .listRowBackground(Color.clear)
                }
            }
            } // end team-sport / racing branch
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

    /// Soccer: a strip of the competitions in the feed, each opening its hub (table,
    /// matches, top scorers). Busiest competitions first, in declaration order on ties.
    @ViewBuilder
    private func soccerCompetitionsSection(_ browseVM: SportBrowseViewModel) -> some View {
        let games = browseVM.liveGames + browseVM.todayGames + browseVM.upcomingGames + browseVM.recentGames
        let counts = Dictionary(grouping: games.compactMap { $0.game.idLeague.flatMap(Int.init) }, by: { $0 })
            .mapValues(\.count)
        let leagues = Leagues.allCases
            .filter { counts[$0.rawValue] != nil && SportType(league: $0) == .soccer }
            .sorted { (counts[$0.rawValue] ?? 0) > (counts[$1.rawValue] ?? 0) }
        if !leagues.isEmpty {
            Section("Competitions") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(leagues, id: \.rawValue) { league in
                            NavigationLink {
                                SoccerCompetitionHubView(league: league)
                                    .environment(viewModel)
                                    .environment(favorites)
                            } label: {
                                Text(league.leagueName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.secondaryGroupedBackground, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
        }
    }

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

    // MARK: - Section dispatchers

    /// Today section — shows time only since the date is implied
    @ViewBuilder
    private func todaySection(_ games: [GameWithTeams]) -> some View {
        if sport == .racing {
            racingSection(games, header: "Today")
        } else {
            Section("Today") {
                ForEach(games) { gwt in
                    dayGroupedRow(gwt)
                }
            }
        }
    }

    /// Upcoming (future) games, dispatched per sport.
    @ViewBuilder
    private func upcomingSections(_ games: [GameWithTeams]) -> some View {
        if sport == .racing {
            racingSection(games, header: "Upcoming Races")
        } else {
            dayGroupedSections(games, ascending: true)
        }
    }

    /// Past (recent) results, dispatched per sport.
    @ViewBuilder
    private func pastSections(_ games: [GameWithTeams]) -> some View {
        if sport == .racing {
            pastSeasonSections(games)
        } else {
            dayGroupedSections(games, ascending: false)
        }
    }

    // MARK: - Day-grouped sections (team sports)

    /// Groups games under day headers (Today / Tomorrow / Yesterday / weekday + date).
    /// Rows show time only since the day is already in the header.
    @ViewBuilder
    private func dayGroupedSections(_ games: [GameWithTeams], ascending: Bool) -> some View {
        let groups = groupedByDay(games, ascending: ascending)
        ForEach(Array(groups.enumerated()), id: \.element.day) { index, group in
            Section {
                ForEach(group.games) { gwt in
                    dayGroupedRow(gwt)
                }
            } header: {
                Text(dayLabel(group.day))
            }
            #if os(iOS)
            adSection(afterGroupIndex: index)
            #endif
        }
    }

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

    #if os(iOS)
    /// Inserts a single native ad after the first day group for non-pro users.
    /// Together with the Today-section ad (slot 0) this caps the Browse feed at
    /// `AdConfiguration.maxAdsPerScreen` (2) total, with distinct creatives.
    @ViewBuilder
    private func adSection(afterGroupIndex index: Int) -> some View {
        if !subscriptionManager.isPro && AdConfiguration.isEnabled {
            let slot: Int? = (index == 0) ? 1 : nil
            if let slot, let ad = adManager.adForSlot(slot) {
                Section {
                    NativeAdCardView(nativeAd: ad)
                }
            }
        }
    }
    #endif

    /// Buckets games by calendar day (race weekends bucket by race day).
    private func groupedByDay(_ games: [GameWithTeams], ascending: Bool) -> [(day: Date, games: [GameWithTeams])] {
        var buckets: [Date: [GameWithTeams]] = [:]
        for gwt in games {
            guard let day = dayBucketStart(gwt.game) else { continue }
            buckets[day, default: []].append(gwt)
        }
        return buckets
            .sorted { ascending ? $0.key < $1.key : $0.key > $1.key }
            .map { day, dayGames in
                let sorted = dayGames.sorted {
                    let d0 = $0.game.standardDate ?? .distantFuture
                    let d1 = $1.game.standardDate ?? .distantFuture
                    return ascending ? d0 < d1 : d0 > d1
                }
                return (day: day, games: sorted)
            }
    }

    private func dayBucketStart(_ game: Game) -> Date? {
        let date = game.isRace ? (game.effectiveEndDate ?? game.standardDate) : game.standardDate
        return date.map { Calendar.current.startOfDay(for: $0) }
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

    // MARK: - Racing sections

    /// Flat racing list — one row per Grand Prix (RaceScoreView shows the GP name + status),
    /// prefixed with the weekend date range. Avoids a section header per single-row GP.
    @ViewBuilder
    private func racingSection(_ games: [GameWithTeams], header: String) -> some View {
        Section(header) {
            ForEach(games) { gwt in
                raceRow(gwt)
            }
        }
    }

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

    // MARK: - Past results by season (racing)

    /// Past F1 results grouped into one section per season (newest season first).
    @ViewBuilder
    private func pastSeasonSections(_ games: [GameWithTeams]) -> some View {
        let seasons = groupedBySeason(games)
        ForEach(seasons, id: \.year) { season in
            Section {
                ForEach(season.games) { gwt in
                    raceRow(gwt)
                }
            } header: {
                Label("\(season.year) Season", systemImage: "flag.checkered.2.crossed")
            }
        }
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
