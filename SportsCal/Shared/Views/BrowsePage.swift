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

            NavigationLink {
                TeamsListView()
                    .environment(viewModel)
                    .environment(favorites)
            } label: {
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

            if sport == .tennis {
                // Tennis: drill-in tournament hub (group all matches into tournaments).
                tennisTournamentSections(browseVM)
            } else {
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
                    upcomingSections(browseVM.upcomingGames)
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
                    pastSections(browseVM.recentGames)
                }

                if browseVM.recentGames.isEmpty {
                    Section {
                        pastEmptyState
                    }
                    .listRowBackground(Color.clear)
                }
            }
            } // end non-tennis branch
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
            let tours = Set(gs.compactMap { game -> Leagues? in
                guard let lg = game.idLeague, let i = Int(lg) else { return nil }
                return Leagues(rawValue: i)
            })
            return TennisTournament(
                name: name, games: gs,
                startDate: dates.min(), endDate: dates.max(),
                isLive: gs.contains { $0.strStatus?.lowercased() == "in" },
                tours: tours
            )
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

    @ViewBuilder
    private func tennisTournamentCard(_ tournament: TennisTournament) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tennisball.fill")
                .foregroundStyle(Color.app(.tennis))
            VStack(alignment: .leading, spacing: 2) {
                Text(tournament.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let badge = tournament.tourBadge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.app(.tennis))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.app(.tennis).opacity(0.15), in: Capsule())
                    }
                    Text(dateRangeText(tournament.startDate, tournament.endDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if tournament.isLive {
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
