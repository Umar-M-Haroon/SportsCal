//
//  DayPage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/15/26.
//

import SwiftUI
import SportsCalModel
#if os(iOS)
import EventKit
#endif

struct DayPage: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var spotlightGameID: String?
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var sheetType: SheetType?
    @State private var collapsedSportSections: Set<SportType> = []
    @State private var sportFilter: SportChipFilter = .all
    @State private var showSportPicker: Bool = false
    @State private var browseSport: SportType?
    @State private var searchString: String = ""
    @State private var searchTokens: [SearchToken] = []
    @State private var showHiddenGames: Bool = false

    private var calendar: Calendar { Calendar.current }

    private var isToday: Bool {
        calendar.isDateInToday(selectedDate)
    }

    private var isSearchActive: Bool {
        !searchString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !searchTokens.isEmpty
    }

    private var liveGameIDs: Set<String> {
        Set(viewModel.liveEventsWithTeams.map { $0.id })
    }

    private var suggestedSearchTokens: [SearchToken] {
        SearchToken.suggestions(
            for: searchString,
            currentTokens: searchTokens,
            enabledSports: storage.enabledSports,
            favoriteTeams: favorites.teams,
            hasLiveEvents: !viewModel.liveEventsWithTeams.isEmpty
        )
    }

    // MARK: - Consolidated day data (computed once, derived multiple times)

    /// All data derived from `dayGames` in a single pass to avoid recomputing per access.
    private struct DayData {
        let allGames: [GameWithTeams]
        let filteredFavorites: [GameWithTeams]
        let filteredOtherBySport: [(sport: SportType, games: [GameWithTeams])]
        let isEmpty: Bool
    }

    private var dayGames: [GameWithTeams] {
        viewModel.gamesWithTeams(for: selectedDate)
    }

    private var dayData: DayData {
        let games = dayGames
        let liveFilt = filteredLiveEvents

        var favs: [GameWithTeams] = []
        var grouped: [SportType: [GameWithTeams]] = [:]

        for gwt in games {
            if favorites.contains(gwt.game) {
                if sportFilter.matches(gwt.game) {
                    favs.append(gwt)
                }
            } else {
                guard let leagueString = gwt.game.idLeague,
                      let intLeague = Int(leagueString),
                      let league = Leagues(rawValue: intLeague) else { continue }
                let sport = SportType(league: league)
                if case .sport(let filterSport) = sportFilter, filterSport != sport { continue }
                grouped[sport, default: []].append(gwt)
            }
        }

        let otherBySport = storage.orderedSports.compactMap { sport -> (sport: SportType, games: [GameWithTeams])? in
            guard let sportGames = grouped[sport], !sportGames.isEmpty else { return nil }
            // Sort completed games to the bottom within each sport section
            let sorted = sportGames.sorted { a, b in
                let aDone = a.game.hasDoneStatus
                let bDone = b.game.hasDoneStatus
                if aDone != bDone { return !aDone }
                return false // preserve existing order otherwise
            }
            return (sport: sport, games: sorted)
        }

        let empty = liveFilt.isEmpty && favs.isEmpty && otherBySport.isEmpty

        return DayData(allGames: games, filteredFavorites: favs, filteredOtherBySport: otherBySport, isEmpty: empty)
    }

    private var filteredLiveEvents: [GameWithTeams] {
        guard isToday else { return [] }
        return viewModel.liveEventsWithTeams.filter { sportFilter.matches($0.game) }
    }

    private var filteredFavorites: [GameWithTeams] {
        dayData.filteredFavorites
    }

    private var filteredOtherBySport: [(sport: SportType, games: [GameWithTeams])] {
        dayData.filteredOtherBySport
    }

    private var allDayGamesWithTeams: [GameWithTeams] {
        var combined: [GameWithTeams] = []
        var seenIDs: Set<String> = []

        if isToday {
            for gwt in viewModel.liveEventsWithTeams {
                if seenIDs.insert(gwt.id).inserted {
                    combined.append(gwt)
                }
            }
        }
        for gwt in dayData.allGames {
            if seenIDs.insert(gwt.id).inserted {
                combined.append(gwt)
            }
        }
        return combined
    }

    private var searchFilteredGames: [GameWithTeams] {
        let chipFiltered = allDayGamesWithTeams.filter { sportFilter.matches($0.game) }
        return SearchToken.filter(
            games: chipFiltered,
            tokens: searchTokens,
            searchText: searchString,
            favorites: favorites,
            liveGameIDs: liveGameIDs
        )
    }

    private var isBoardLayout: Bool {
        sizeClass == .regular
    }

    private var boardColumns: [BoardColumn] {
        let games = dayGames
        let live = filteredLiveEvents
        let liveIDs = liveGameIDs

        var grouped: [SportType: [GameWithTeams]] = [:]
        for gwt in games {
            guard let leagueString = gwt.game.idLeague,
                  let intLeague = Int(leagueString),
                  let league = Leagues(rawValue: intLeague) else { continue }
            let sport = SportType(league: league)
            grouped[sport, default: []].append(gwt)
        }

        return storage.enabledSports.map { sport in
            let sportGames = grouped[sport] ?? []
            let liveForSport = live.filter { $0.game.sportType == sport }
            let liveForSportIDs = Set(liveForSport.map { $0.id })

            let other = sportGames
                .filter { !liveForSportIDs.contains($0.id) }
                .sorted { a, b in
                    let aDone = a.game.hasDoneStatus
                    let bDone = b.game.hasDoneStatus
                    if aDone != bDone { return !aDone }
                    return false
                }

            return BoardColumn(sport: sport, liveGames: liveForSport, otherGames: other)
        }
    }

    private var isEmpty: Bool {
        dayData.isEmpty
    }

    private var totalCountForDay: Int {
        viewModel.totalGameCount(for: selectedDate)
    }

    private var visibleCountForDay: Int {
        dayData.allGames.count
    }

    var body: some View {
        Group {
            if isBoardLayout {
                boardBody
            } else {
                listBody
            }
        }
        .navigationDestination(item: $spotlightGameID) { eventID in
            spotlightDestination(for: eventID)
        }
        .sheet(item: $sheetType) { sheetType in
            switch sheetType {
            case .settings:
                SettingsView(sheetType: $sheetType)
                    .environment(storage)
                    .environment(viewModel)
            case .calendar(let eventGame):
                #if os(iOS)
                if let game = eventGame {
                    makeCalendarEvent(game: game)
                }
                #else
                EmptyView()
                #endif
            case .listDetail(let listGames, let liveGames):
                ListDetailView(listGames: listGames, liveGames: liveGames, sheetType: $sheetType)
                    .environment(storage)
                    .environment(viewModel)
                    .environment(favorites)
                    .presentationDetents([.medium, .large])
            default:
                EmptyView()
            }
        }
        .sheet(isPresented: $showSportPicker) {
            SportPickerSheet()
                .environment(storage)
                .environment(viewModel)
        }
        .sheet(item: $browseSport) { sport in
            SportBrowseSheet(sport: sport)
                .environment(viewModel)
                .environment(storage)
                .environment(favorites)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                sportFilterMenu
            }
            ToolbarItem(placement: .primaryAction) {
                if !calendar.isDateInToday(selectedDate) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = calendar.startOfDay(for: Date())
                        }
                    } label: {
                        Text("Today")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .onChange(of: storage.enabledSports) { oldValue, newValue in
            if case .sport(let sport) = sportFilter, !newValue.contains(sport) {
                sportFilter = .all
            }
        }
        .onChange(of: favorites.teams) { _, _ in
            withAnimation {
                viewModel.filterSports()
            }
        }
        .onChange(of: selectedDate) { _, _ in
            showHiddenGames = false
        }
        #if os(macOS)
        .onKeyPress(.leftArrow) {
            navigateDay(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateDay(by: 1)
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: .jumpToToday)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = calendar.startOfDay(for: Date())
            }
        }
        #endif
    }

    // MARK: - Board Layout (iPad/Mac)

    private var boardBody: some View {
        VStack(spacing: 0) {
            DayChipStrip(
                selectedDate: $selectedDate,
                datesWithGames: viewModel.datesWithGames(),
                pastDays: daysForDuration(storage.hidePastEvents ? .oneDay : storage.hidePastGamesDuration),
                futureDays: daysForDuration(storage.durations)
            )
            .padding(.horizontal)
            .padding(.bottom, 8)

            if !viewModel.sortedGamesWithTeams.isEmpty || !viewModel.liveEventsWithTeams.isEmpty {
                GameBoardLayout(columns: boardColumns, favorites: favorites) { gwt, isLive in
                    gameRow(for: gwt, isLive: isLive)
                }
            } else {
                Spacer()
                if viewModel.networkState == .loading || viewModel.isFetching {
                    ProgressView()
                } else {
                    VStack {
                        Text("No games fetched")
                            .foregroundColor(.secondary)
                        Button("Retry") { viewModel.retry() }
                            .foregroundColor(.blue)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - List Layout (iPhone)

    private var listBody: some View {
        List {
            // Day chip strip
            Section {
                DayChipStrip(
                    selectedDate: $selectedDate,
                    datesWithGames: viewModel.datesWithGames(),
                    pastDays: daysForDuration(storage.hidePastEvents ? .oneDay : storage.hidePastGamesDuration),
                    futureDays: daysForDuration(storage.durations)
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if !viewModel.sortedGamesWithTeams.isEmpty || !viewModel.liveEventsWithTeams.isEmpty {
                if isSearchActive {
                    searchResultsContent
                } else {
                    dayContent
                }
            } else {
                loadingOrEmptyContent
            }
        }
        #if os(iOS)
        .searchable(text: $searchString, tokens: $searchTokens, suggestedTokens: .constant(suggestedSearchTokens), placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search games...") { token in
            token.label
        }
        #else
        .searchable(text: $searchString, tokens: $searchTokens, suggestedTokens: .constant(suggestedSearchTokens), prompt: "Search games...") { token in
            token.label
        }
        #endif
        #if os(iOS)
        .gesture(daySwipeGesture)
        #endif
    }

    // MARK: - Day Content

    @ViewBuilder
    private var dayContent: some View {
        // Live games (only on today)
        if !filteredLiveEvents.isEmpty {
            Section {
                ForEach(filteredLiveEvents) { gameWithTeams in
                    gameRow(for: gameWithTeams, isLive: true)
                }
            } header: {
                LiveAnimatedView()
            }
        }

        // Favorites for this day
        if !filteredFavorites.isEmpty {
            Section {
                ForEach(filteredFavorites) { gameWithTeams in
                    gameRow(for: gameWithTeams, isLive: false)
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

        // Other games grouped by sport (collapsed by default)
        ForEach(filteredOtherBySport, id: \.sport) { section in
            let isCollapsed = collapsedSportSections.contains(section.sport)
            Section {
                if !isCollapsed {
                    ForEach(section.games) { gameWithTeams in
                        gameRow(for: gameWithTeams, isLive: false)
                    }
                }
            } header: {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if collapsedSportSections.contains(section.sport) {
                            collapsedSportSections.remove(section.sport)
                        } else {
                            collapsedSportSections.insert(section.sport)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: section.sport.systemImage)
                            .foregroundColor(section.sport.color)
                        Text(section.sport.displayName)
                            .font(.headline)
                        Text("(\(section.games.count))")
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

        // Empty state
        if isEmpty {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    if totalCountForDay > 0 {
                        Text("\(totalCountForDay) \(totalCountForDay == 1 ? "game" : "games") scheduled but hidden by your sport filters")
                            .foregroundColor(.secondary)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showHiddenGames.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showHiddenGames ? "eye.slash" : "eye")
                                Text(showHiddenGames ? "Hide filtered games" : "Peek at hidden games")
                            }
                            .font(.subheadline)
                        }
                    } else {
                        Text(isToday ? "No games scheduled for today" : "No games scheduled for \(formattedSelectedDate)")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .listRowBackground(Color.clear)
        }

        // Game count footer + peek at hidden
        if !isEmpty || totalCountForDay > 0 {
            let hiddenCount = totalCountForDay - visibleCountForDay
            Section {
                HStack {
                    Spacer()
                    if hiddenCount > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showHiddenGames.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(visibleCountForDay) of \(totalCountForDay) games")
                                Image(systemName: showHiddenGames ? "eye.slash" : "eye")
                                    .font(.caption)
                                Text(showHiddenGames ? "Hide filtered" : "Peek at \(hiddenCount) hidden")
                            }
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("\(visibleCountForDay) \(visibleCountForDay == 1 ? "game" : "games")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
        }

        // Hidden games peek
        if showHiddenGames {
            let hiddenBySport = viewModel.hiddenGamesBySport(for: selectedDate)
            let hiddenSections = storage.orderedSports.compactMap { sport -> (sport: SportType, games: [GameWithTeams])? in
                guard let games = hiddenBySport[sport], !games.isEmpty else { return nil }
                return (sport: sport, games: games)
            }
            ForEach(hiddenSections, id: \.sport) { section in
                Section {
                    ForEach(section.games) { gameWithTeams in
                        gameRow(for: gameWithTeams, isLive: false)
                            .opacity(0.5)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.slash")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Image(systemName: section.sport.systemImage)
                            .foregroundColor(section.sport.color)
                        Text(section.sport.displayName)
                            .font(.headline)
                        Text("(\(section.games.count))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("- filtered out")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsContent: some View {
        if searchFilteredGames.isEmpty {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No matching games")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .listRowBackground(Color.clear)
        } else {
            ForEach(searchFilteredGames) { gameWithTeams in
                gameRow(for: gameWithTeams, isLive: liveGameIDs.contains(gameWithTeams.id))
            }
        }
    }

    // MARK: - Loading / Empty

    @ViewBuilder
    private var loadingOrEmptyContent: some View {
        if viewModel.networkState == .loading || viewModel.isFetching {
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
                    viewModel.retry()
                }
                .foregroundColor(Color.blue)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Game Row

    @ViewBuilder
    private func gameRow(for gameWithTeams: GameWithTeams, isLive: Bool) -> some View {
        @Bindable var bindableStorage = storage
        let game = gameWithTeams.game
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
        } else if let homeTeam = gameWithTeams.homeTeam,
                  let awayTeam = gameWithTeams.awayTeam {
            let isPreGame = game.strStatus == "pre" || game.strStatus == "NS"
            if let homeScore = Int(game.intHomeScore ?? ""),
               let awayScore = Int(game.intAwayScore ?? ""),
               !isPreGame {
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
                    showCountdown: $bindableStorage.showStartTime,
                    shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                    sheetType: $sheetType,
                    dateFormat: storage.dateFormat,
                    isFavorite: favorites.contains(game)
                )
                .environment(favorites)
            }
        }
    }

    // MARK: - Sport Filter Menu

    private var totalLiveCount: Int {
        viewModel.liveGameCountsBySport.values.reduce(0, +)
    }

    private var sportFilterMenu: some View {
        Menu {
            Button {
                withAnimation { sportFilter = .all }
            } label: {
                if sportFilter == .all {
                    Label("All Sports", systemImage: "checkmark")
                } else {
                    Text("All Sports")
                }
            }

            Divider()

            ForEach(storage.enabledSports, id: \.self) { sport in
                let liveCount = viewModel.liveGameCountsBySport[sport] ?? 0
                Button {
                    withAnimation {
                        if case .sport(let current) = sportFilter, current == sport {
                            sportFilter = .all
                        } else {
                            sportFilter = .sport(sport)
                        }
                    }
                } label: {
                    let isSelected = sportFilter == .sport(sport)
                    HStack {
                        Label(sport.displayName, systemImage: sport.systemImage)
                        if liveCount > 0 {
                            Text("(\(liveCount) live)")
                        }
                        if isSelected {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            let disabledSports = SportType.allCases.filter { !storage.enabledSports.contains($0) }
            if !disabledSports.isEmpty {
                Divider()

                ForEach(disabledSports, id: \.self) { sport in
                    Button {
                        browseSport = sport
                    } label: {
                        Label(sport.displayName, systemImage: sport.systemImage)
                    }
                }

                Button {
                    showSportPicker = true
                } label: {
                    Label("Manage Sports", systemImage: "plus")
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: sportFilterIcon)
                if totalLiveCount > 0 {
                    Text("\(totalLiveCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                }
            }
        }
    }

    private var sportFilterIcon: String {
        switch sportFilter {
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .sport(let sport):
            return sport.systemImage
        }
    }

    // MARK: - Spotlight Deep Link

    @ViewBuilder
    private func spotlightDestination(for eventID: String) -> some View {
        if let game = viewModel.totalGames?.first(where: { $0.idEvent == eventID }) {
            if game.isRace {
                RaceDetailView(game: game)
                    .environment(viewModel)
                    .environment(favorites)
            } else if game.isTennisMatch {
                TennisMatchDetailView(game: game)
                    .environment(viewModel)
                    .environment(favorites)
            } else if game.isIndividualSport {
                TournamentDetailView(game: game)
                    .environment(viewModel)
                    .environment(favorites)
            } else if let (homeTeam, awayTeam) = viewModel.getTeams(for: game) {
                GameDetailView(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                    .environment(viewModel)
                    .environment(favorites)
            } else {
                Text("Game not found")
                    .foregroundColor(.secondary)
            }
        } else {
            Text("Game not found")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Navigation

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                if horizontal < 0 {
                    navigateDay(by: 1)
                } else {
                    navigateDay(by: -1)
                }
            }
    }

    private func navigateDay(by offset: Int) {
        guard let newDate = calendar.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = newDate
        }
    }

    private func daysForDuration(_ duration: Durations) -> Int {
        let today = calendar.startOfDay(for: Date())
        let target: Date?
        switch duration {
        case .oneDay:     target = calendar.date(byAdding: .day, value: 1, to: today)
        case .oneWeek:    target = calendar.date(byAdding: .weekOfYear, value: 1, to: today)
        case .twoWeeks:   target = calendar.date(byAdding: .weekOfYear, value: 2, to: today)
        case .threeWeeks: target = calendar.date(byAdding: .weekOfYear, value: 3, to: today)
        case .oneMonth:   target = calendar.date(byAdding: .month, value: 1, to: today)
        case .twoMonths:  target = calendar.date(byAdding: .month, value: 2, to: today)
        case .sixMonths:  target = calendar.date(byAdding: .month, value: 6, to: today)
        case .oneYear:    target = calendar.date(byAdding: .year, value: 1, to: today)
        }
        guard let target else { return 14 }
        return max(1, calendar.dateComponents([.day], from: today, to: target).day ?? 14)
    }

    private var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    #if os(iOS)
    private func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        event.title = "\(game.strAwayTeam) @ \(game.strHomeTeam)"
        if let gameDate = game.standardDate {
            event.startDate = gameDate
            event.endDate = gameDate.afterHoursFromNow(hours: 2)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif
}

#Preview {
    DayPage(shouldShowSportsCalProAlert: .constant(false), spotlightGameID: .constant(nil))
        .environment(GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites()))
        .environment(UserDefaultStorage())
        .environment(Favorites())
}
