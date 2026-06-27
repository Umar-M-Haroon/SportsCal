//
//  DayPage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/15/26.
//

import SwiftUI
import SportsCalModel
import TipKit
#if os(iOS)
import EventKit
#endif

/// Cross-platform scope the day board can be narrowed to (driven by the macOS
/// sidebar selection; defaults to `.all` everywhere else).
enum DayScope: Hashable {
    case all
    case sport(SportType)
    case liveNow
    case favorites
    case team(String)   // team id

    var isTeam: Bool {
        if case .team = self { return true }
        return false
    }
}

extension View {
    /// Adds Mac-native affordances to a board game cell — hover lift + link
    /// cursor, drag-to-export, and an "Open in New Window" context menu. No-op
    /// on iOS.
    @ViewBuilder
    func macBoardAffordances(game: Game) -> some View {
        #if os(macOS)
        modifier(MacBoardAffordances(game: game))
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct MacBoardAffordances: ViewModifier {
    let game: Game
    @Environment(\.openWindow) private var openWindow
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .pointerStyle(.link)
            .onHover { isHovered = $0 }
            .draggable(dragPayload)
            .contextMenu {
                Button("Open in New Window") {
                    openWindow(id: "game-detail", value: game.id)
                }
            }
    }

    private var dragPayload: String {
        var line = "\(game.strAwayTeam) @ \(game.strHomeTeam)"
        if let date = game.standardDate {
            line += " — " + date.formatted(date: .abbreviated, time: .shortened)
        }
        if let idEvent = game.idEvent,
           let url = DeepLink.url(for: .game(idEvent: idEvent)) {
            line += "\n" + url.absoluteString
        }
        return line
    }
}
#endif

struct DayPage: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites
    @Environment(EngagementTracker.self) private var engagementTracker
    @Environment(SubscriptionManager.self) private var subscriptionManager
    #if os(iOS)
    @Environment(NativeAdManager.self) private var adManager
    #endif
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var spotlightGameID: String?
    /// Sidebar-driven scope (macOS). `.all` = the full multi-sport board.
    var dayScope: DayScope = .all
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var sheetType: SheetType?
    @State private var collapsedSportSections: Set<SportType> = []
    @State private var sportFilter: SportChipFilter = .all
    @State private var showSportPicker: Bool = false
    @State private var browseSport: SportType?
    @State private var searchString: String = ""
    @State private var searchTokens: [SearchToken] = []
    @State private var showHiddenGames: Bool = false
    @State private var boardNavigationTarget: GameWithTeams?
    @State private var worldCupHubPresented = false
    /// Keyboard-selected board cell (macOS): ⌥↑/⌥↓ move it, Return pops it out.
    @State private var boardSelectedGameID: String?
    /// The date we were on before a team's date-jump, so leaving the team scope
    /// returns there instead of stranding on the team's game day.
    @State private var dateBeforeTeamScope: Date?
    /// macOS: trailing inspector showing the selected game's rich detail.
    /// Persisted so its open/closed state survives relaunch. (Inspector *width*
    /// is restored automatically by the window's state restoration.)
    @AppStorage("board.inspector.visible") private var boardInspectorVisible: Bool = true
    @Environment(\.openWindow) private var openWindow

    // Memoization for `dayData`. A plain reference-type box held by @State keeps a
    // stable identity across renders without SwiftUI observing its mutations — so
    // writing the cache during a body read doesn't kick off another render cycle.
    @State private var dayDataCacheBox = DayDataCacheBox()

    private final class DayDataCacheBox {
        var entry: (key: DayDataKey, value: DayData)?
    }

    private struct DayDataKey: Hashable {
        let dayStart: Date
        let gameCount: Int
        let firstGameID: String?
        let lastGameID: String?
        let sportFilter: SportChipFilter
        let dayScope: DayScope
        let favoritesHash: Int
        let suggestedHash: Int
        let orderedSportsHash: Int
        let worldCupHeroActive: Bool
    }

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

    // MARK: - World Cup hero

    private static let worldCupLeagueID = String(Leagues.FIFA_World_Cup.rawValue)

    /// The World Cup hero owns today's WC matches (marquee + ticker), so the
    /// regular Live / soccer sections skip them. Mirrors `ModernDayPage`.
    private var showWorldCupHero: Bool {
        guard storage.shouldShowWorldCup || storage.shouldShowSoccer else { return false }
        // Lead every matchday with the hero. On today, also show it during the
        // tournament era for the next-kickoff countdown even on rest days.
        if dayGames.contains(where: { $0.game.idLeague == Self.worldCupLeagueID }) { return true }
        return isToday && WorldCupHeroCard.isActive(viewModel: viewModel)
    }

    /// IDs of today's World Cup games claimed by the hero — excluded from the
    /// regular sections to avoid showing each match twice. Empty when the hero
    /// isn't shown (so WC games surface normally on other days / when disabled).
    private var heroClaimedWorldCupIDs: Set<String> {
        guard showWorldCupHero else { return [] }
        return Set(dayGames.filter { $0.game.idLeague == Self.worldCupLeagueID }.map(\.id))
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
        let suggestedGames: [GameWithTeams]
        let filteredOtherBySport: [(sport: SportType, games: [GameWithTeams])]
        let isEmpty: Bool
    }

    private var dayGames: [GameWithTeams] {
        viewModel.gamesWithTeams(for: selectedDate).filter { passesDayScope($0.game) }
    }

    /// Sidebar-scope predicate (macOS). On iOS `dayScope` stays `.all` → no-op.
    private func passesDayScope(_ game: Game) -> Bool {
        switch dayScope {
        case .all:          return true
        case .sport(let s): return game.sportType == s
        case .liveNow:      return liveGameIDs.contains(game.id)
        case .favorites:    return favorites.matches(game)
        case .team(let id): return game.idHomeTeam == id || game.idAwayTeam == id
        }
    }

    private var dayDataKey: DayDataKey {
        let games = dayGames
        let suggested = engagementTracker.suggestedTeamNames(excluding: favorites.teams)
        return DayDataKey(
            dayStart: calendar.startOfDay(for: selectedDate),
            gameCount: games.count,
            firstGameID: games.first?.id,
            lastGameID: games.last?.id,
            sportFilter: sportFilter,
            dayScope: dayScope,
            favoritesHash: favorites.teams.hashValue,
            suggestedHash: suggested.hashValue,
            orderedSportsHash: storage.orderedSports.hashValue,
            worldCupHeroActive: showWorldCupHero
        )
    }

    private var dayData: DayData {
        let key = dayDataKey
        if let entry = dayDataCacheBox.entry, entry.key == key {
            return entry.value
        }
        let value = computeDayData()
        dayDataCacheBox.entry = (key, value)
        return value
    }

    // Computes the heavy partition over `dayGames`. Called on cache miss only.
    // `isEmpty` here intentionally excludes the live-events check so this result
    // stays valid through WebSocket pushes (which only invalidate `filteredLiveEvents`).
    private func computeDayData() -> DayData {
        let games = dayGames
        let suggestedTeamNames = engagementTracker.suggestedTeamNames(excluding: favorites.teams)
        // Today's World Cup matches render inside the hero, not the sections.
        let claimedWorldCupIDs = heroClaimedWorldCupIDs

        var favs: [GameWithTeams] = []
        var suggested: [GameWithTeams] = []
        var grouped: [SportType: [GameWithTeams]] = [:]

        for gwt in games {
            if claimedWorldCupIDs.contains(gwt.id) { continue }
            if favorites.contains(gwt.game) {
                if sportFilter.matches(gwt.game) {
                    favs.append(gwt)
                }
            } else if !suggestedTeamNames.isEmpty &&
                      (suggestedTeamNames.contains(gwt.game.strHomeTeam) || suggestedTeamNames.contains(gwt.game.strAwayTeam)) {
                if sportFilter.matches(gwt.game) {
                    suggested.append(gwt)
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

        let empty = favs.isEmpty && suggested.isEmpty && otherBySport.isEmpty

        return DayData(allGames: games, filteredFavorites: favs, suggestedGames: suggested, filteredOtherBySport: otherBySport, isEmpty: empty)
    }

    private var filteredLiveEvents: [GameWithTeams] {
        guard isToday else { return [] }
        let claimedWorldCupIDs = heroClaimedWorldCupIDs
        return viewModel.liveEventsWithTeams.filter {
            sportFilter.matches($0.game) && passesDayScope($0.game) && !claimedWorldCupIDs.contains($0.id)
        }
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
        let claimedWorldCupIDs = heroClaimedWorldCupIDs
        let games = dayGames.filter { !claimedWorldCupIDs.contains($0.id) }
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

        return storage.enabledSports.compactMap { sport -> BoardColumn? in
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

            let isEmpty = sportGames.isEmpty && liveForSport.isEmpty
            // In a focused scope (a single sport/team/live/favorites), don't show
            // a wall of empty sport columns — only the ones with content.
            if isEmpty, dayScope != .all { return nil }

            let nextDate: Date? = isEmpty
                ? viewModel.nextGame(for: sport, after: selectedDate)?.standardDate
                : nil

            return BoardColumn(sport: sport, liveGames: liveForSport, otherGames: other, nextGameDate: nextDate)
        }
    }

    private var isEmpty: Bool {
        // `dayData.isEmpty` excludes the live-events check by design (see computeDayData)
        // so the cache stays valid through WebSocket pushes. Combine the live check here.
        dayData.isEmpty && filteredLiveEvents.isEmpty
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
        #if os(iOS)
        .onAppear {
            if !subscriptionManager.isPro && AdConfiguration.isEnabled {
                adManager.refreshOnAppear()
            }
        }
        #endif
        .navigationDestination(item: $spotlightGameID) { eventID in
            spotlightDestination(for: eventID)
        }
        .navigationDestination(item: $boardNavigationTarget) { gwt in
            boardDetailView(for: gwt)
        }
        .navigationDestination(isPresented: $worldCupHubPresented) {
            WorldCupHubView()
                .environment(viewModel)
                .environment(favorites)
                .environment(storage)
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
                Button {
                    showSportPicker = true
                } label: {
                    Label("Manage Sports", systemImage: "slider.horizontal.3")
                }
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
        .onChange(of: selectedDate) { _, newValue in
            showHiddenGames = false
            boardSelectedGameID = nil
            viewModel.ensureGamesLoaded(for: newValue)
        }
        .onChange(of: dayScope) { oldScope, newScope in
            // A sidebar tap should land somewhere useful: a team jumps to its
            // next/most-recent game; Live Now jumps to today. Leaving a team
            // restores the date we had before the jump (so team → All Sports
            // doesn't strand you on the team's game day).
            boardSelectedGameID = nil
            switch newScope {
            case .team(let id):
                if !oldScope.isTeam { dateBeforeTeamScope = selectedDate }
                if let date = nextGame(forTeamID: id)?.standardDate {
                    selectedDate = calendar.startOfDay(for: date)
                }
            case .liveNow:
                selectedDate = calendar.startOfDay(for: Date())
                dateBeforeTeamScope = nil
            case .all, .sport, .favorites:
                if oldScope.isTeam {
                    selectedDate = dateBeforeTeamScope ?? calendar.startOfDay(for: Date())
                    dateBeforeTeamScope = nil
                }
            }
        }
        .task {
            viewModel.ensureGamesLoaded(for: selectedDate)
        }
    }

    /// Soonest live-or-upcoming (or most-recent) game involving a team — used to
    /// land on a useful day when a team is picked in the sidebar.
    private func nextGame(forTeamID id: String) -> Game? {
        let cutoff = calendar.date(byAdding: .hour, value: -4, to: Date()) ?? Date()
        let games = (viewModel.totalGames ?? []).filter { $0.idHomeTeam == id || $0.idAwayTeam == id }
        let upcoming = games
            .filter { ($0.standardDate ?? .distantPast) >= cutoff }
            .min { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
        // Fall back to the most recent past game if the team has nothing upcoming.
        return upcoming ?? games.max { ($0.standardDate ?? .distantPast) < ($1.standardDate ?? .distantPast) }
    }

    #if os(macOS)
    /// Trailing inspector: the keyboard/click-selected game's full detail
    /// (standings, leaders, plays, injuries, H2H) shown inline beside the board.
    @ViewBuilder
    private var boardInspector: some View {
        if let id = boardSelectedGameID, let gwt = boardGameWithTeams(byID: id) {
            boardDetailView(for: gwt)
                .id(id)   // rebuild section loaders when the selection changes
                // Keep a comfortable reading measure on very wide inspector panes
                // (the detail was originally tuned for phone widths).
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity, alignment: .top)
        } else {
            ContentUnavailableView(
                "No Game Selected",
                systemImage: "sportscourt",
                description: Text("Pick a game — or press ⌥↑ / ⌥↓ — to see standings, leaders, and plays. Press Return to open it in its own window.")
            )
        }
    }
    #endif

    #if os(macOS)
    /// Display order of board cells (column by column, live then upcoming) — the
    /// traversal order for ⌥↑/⌥↓ keyboard navigation.
    private var boardSelectionOrder: [GameWithTeams] {
        boardColumns.flatMap { $0.liveGames + $0.otherGames }
    }

    private func boardGameWithTeams(byID id: String) -> GameWithTeams? {
        boardSelectionOrder.first { $0.id == id }
    }

    private func moveBoardSelection(by delta: Int) {
        let order = boardSelectionOrder.map(\.id)
        guard !order.isEmpty else { return }
        guard let current = boardSelectedGameID,
              let idx = order.firstIndex(of: current) else {
            boardSelectedGameID = order.first
            return
        }
        boardSelectedGameID = order[min(max(idx + delta, 0), order.count - 1)]
    }
    #endif

    /// Tapping a board cell shows its detail: inline in the inspector on macOS,
    /// pushed full-screen elsewhere.
    private func selectBoardGame(_ gwt: GameWithTeams) {
        #if os(macOS)
        boardSelectedGameID = gwt.id
        boardInspectorVisible = true
        #else
        boardNavigationTarget = gwt
        #endif
    }

    // MARK: - Board Layout (iPad/Mac)

    private var boardBody: some View {
        let board = VStack(spacing: 0) {
            DayChipStrip(
                selectedDate: $selectedDate,
                datesWithGames: viewModel.datesWithGames()
            )
            .padding(.horizontal)
            .padding(.bottom, 8)

            // World Cup hero — pinned on matchday above the board. Width-capped
            // so it reads as a card rather than stretching across a wide iPad.
            if showWorldCupHero {
                WorldCupHeroCard(
                    onSelectGame: { selectBoardGame($0) },
                    onOpenHub: { worldCupHubPresented = true },
                    date: selectedDate
                )
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if isEmpty && (!viewModel.sortedGamesWithTeams.isEmpty || !viewModel.liveEventsWithTeams.isEmpty) {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(isToday ? "No games scheduled for today" : "No games scheduled for \(formattedSelectedDate)")
                        .foregroundStyle(.secondary)
                    if let nextDate = viewModel.nextDateWithGames(after: selectedDate) {
                        nextGamesHint(
                            date: nextDate,
                            sportCounts: viewModel.gameCountsBySport(for: nextDate)
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = nextDate
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else if !viewModel.sortedGamesWithTeams.isEmpty || !viewModel.liveEventsWithTeams.isEmpty {
                GameBoardLayout(
                    columns: boardColumns,
                    favorites: favorites,
                    onJumpToDate: { date in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = calendar.startOfDay(for: date)
                        }
                    },
                    onMoveSport: { source, target in
                        withAnimation { storage.moveSport(source, before: target) }
                    }
                ) { gwt, isLive in
                    boardGameRow(for: gwt, isLive: isLive)
                }
            } else {
                Spacer()
                if viewModel.networkState == .loading || viewModel.isFetching {
                    VStack(spacing: .appSpace2) {
                        SkeletonRow()
                        SkeletonRow()
                        SkeletonRow()
                    }
                    .padding(.horizontal, .appSpace4)
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
        #if os(macOS)
        return macBoardChrome(board)
        #else
        return board
        #endif
    }

    #if os(macOS)
    /// Bundles the Mac board's keyboard navigation, detail inspector, and the
    /// inspector-toggle toolbar item. Isolated in its own generic function so the
    /// (heavy) inspector closure type-checks independently of `body`.
    @ViewBuilder
    private func macBoardChrome(_ content: some View) -> some View {
        content
            .onKeyPress(.leftArrow) {
                navigateDay(by: -1); return .handled
            }
            .onKeyPress(.rightArrow) {
                navigateDay(by: 1); return .handled
            }
            // ⌥↑ / ⌥↓ move the keyboard selection (plain ←/→ are day nav);
            // Return pops the selected game out into its own window.
            .onKeyPress(keys: [.upArrow]) { press in
                guard press.modifiers.contains(.option) else { return .ignored }
                moveBoardSelection(by: -1); return .handled
            }
            .onKeyPress(keys: [.downArrow]) { press in
                guard press.modifiers.contains(.option) else { return .ignored }
                moveBoardSelection(by: 1); return .handled
            }
            .onKeyPress(.return) {
                guard let id = boardSelectedGameID else { return .ignored }
                openWindow(id: "game-detail", value: id); return .handled
            }
            .inspector(isPresented: $boardInspectorVisible) {
                boardInspector
                    .inspectorColumnWidth(min: 340, ideal: 420, max: 600)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { boardInspectorVisible.toggle() }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help(boardInspectorVisible ? "Hide game details" : "Show game details")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .jumpToToday)) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedDate = calendar.startOfDay(for: Date())
                }
            }
    }
    #endif

    // MARK: - List Layout (iPhone)

    private var listBody: some View {
        List {
            // Day chip strip
            Section {
                DayChipStrip(
                    selectedDate: $selectedDate,
                    datesWithGames: viewModel.datesWithGames()
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
        .listSectionSpacing(.compact)
        #endif
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
        let adPlan = classicAdPlan
        // World Cup hero — pinned on matchday, carries the tournament (marquee,
        // ticker, group rail). Owns today's WC matches; the sections skip them.
        if showWorldCupHero {
            Section {
                WorldCupHeroCard(
                    onSelectGame: { selectBoardGame($0) },
                    onOpenHub: { worldCupHubPresented = true },
                    date: selectedDate
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

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

        // Suggested for you
        if storage.showSuggestedForYou, !dayData.suggestedGames.isEmpty {
            Section {
                TipView(FavoriteTeamSuggestionTip())
                    .tipBackground(Color.secondaryGroupedBackground)
                    .onAppear {
                        if let top = engagementTracker.topSuggestedTeam(excluding: favorites.teams) {
                            FavoriteTeamSuggestionTip.suggestedTeamName = top.teamName
                        }
                    }
                    .onTapGesture {
                        if let top = engagementTracker.topSuggestedTeam(excluding: favorites.teams) {
                            favorites.add(top.teamName)
                            FavoriteTeamSuggestionTip.suggestedTeamName = ""
                            FavoriteTeamSuggestionTip().invalidate(reason: .actionPerformed)
                        }
                    }
                ForEach(dayData.suggestedGames) { gameWithTeams in
                    gameRow(for: gameWithTeams, isLive: false)
                }
            } header: {
                HStack {
                    Image(systemName: "star.badge.plus")
                        .foregroundColor(.purple)
                    Text("Suggested For You")
                        .font(.headline)
                }
            }
        }

        #if os(iOS)
        if let slot = adPlan.slot(region: "lead", row: 0), let ad = adManager.adForSlot(slot) {
            Section {
                NativeAdCardView(nativeAd: ad)
            }
        }
        #endif

        // Other games grouped by sport (collapsed by default)
        ForEach(Array(filteredOtherBySport.enumerated()), id: \.element.sport) { index, section in
            let isCollapsed = collapsedSportSections.contains(section.sport)
            Section {
                if !isCollapsed {
                    sportSectionContent(games: section.games, region: "sport-\(index)", adPlan: adPlan)
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
                    if storage.showFilteredOutGames, totalCountForDay > 0 {
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
                        // Next game hint when a specific sport is filtered
                        if case .sport(let activeSport) = sportFilter,
                           let nextGame = viewModel.nextGame(for: activeSport, after: selectedDate),
                           let nextDate = nextGame.standardDate {
                            nextGameHint(sport: activeSport, date: nextDate)
                        }
                        // Next games hint when no specific sport is filtered
                        if case .all = sportFilter,
                           let nextDate = viewModel.nextDateWithGames(after: selectedDate) {
                            nextGamesHint(
                                date: nextDate,
                                sportCounts: viewModel.gameCountsBySport(for: nextDate)
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedDate = nextDate
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .listRowBackground(Color.clear)
        }

        // Game count footer + peek at hidden
        if storage.showFilteredOutGames, !isEmpty || totalCountForDay > 0 {
            let hiddenCount = totalCountForDay - visibleCountForDay
            Section {
                HStack {
                    Spacer()
                    if storage.showFilteredOutGames, hiddenCount > 0 {
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
        if storage.showFilteredOutGames, showHiddenGames {
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
            ForEach(0..<3, id: \.self) { _ in
                SkeletonRow()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
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
        gameRowContent(for: gameWithTeams, isLive: isLive)
            .gameCard(game: gameWithTeams.game, isLive: isLive)
    }

    @ViewBuilder
    private func gameRowContent(for gameWithTeams: GameWithTeams, isLive: Bool) -> some View {
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
                    .environment(favorites)
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

    // MARK: - Board Game Row (programmatic navigation)

    @ViewBuilder
    private func boardGameRow(for gameWithTeams: GameWithTeams, isLive: Bool) -> some View {
        @Bindable var bindableStorage = storage
        let game = gameWithTeams.game

        Button {
            selectBoardGame(gameWithTeams)
        } label: {
            Group {
                if game.isRace {
                    RaceScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: isLive)
                        .environment(viewModel)
                        .environment(favorites)
                } else if game.isTennisMatch {
                    TennisMatchScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: isLive)
                        .environment(viewModel)
                        .environment(favorites)
                } else if game.isIndividualSport {
                    TournamentScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: isLive)
                        .environment(viewModel)
                        .environment(favorites)
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
                            isLive: isLive,
                            navigationDisabled: true
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
                            isFavorite: favorites.contains(game),
                            navigationDisabled: true
                        )
                        .environment(favorites)
                        .environment(viewModel)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .overlay {
            // Keyboard-selection ring (macOS ⌥↑/⌥↓). `boardSelectedGameID` is
            // only ever set on macOS, so this is inert elsewhere.
            if boardSelectedGameID == game.id {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .macBoardAffordances(game: game)
    }

    @ViewBuilder
    private func boardDetailView(for gwt: GameWithTeams) -> some View {
        let game = gwt.game
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
        } else if let homeTeam = gwt.homeTeam, let awayTeam = gwt.awayTeam {
            AdaptiveGameDetail(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                .environment(viewModel)
                .environment(favorites)
        }
    }

    // MARK: - Sport Filter Menu

    private var totalLiveCount: Int {
        viewModel.liveGameCountsBySport.values.reduce(0, +)
    }

    private var sportFilterMenu: some View {
        Menu {
            Picker(selection: $sportFilter) {
                Label("All Sports", systemImage: "sportscourt")
                    .tag(SportChipFilter.all)
                ForEach(storage.enabledSports, id: \.self) { sport in
                    let liveCount = viewModel.liveGameCountsBySport[sport] ?? 0
                    let title = liveCount > 0
                        ? "\(sport.displayName) · \(liveCount) live"
                        : sport.displayName
                    Label(title, systemImage: sport.systemImage)
                        .tag(SportChipFilter.sport(sport))
                }
            } label: {
                Text("Filter")
            }
            .pickerStyle(.inline)

            let disabledSports = SportType.allCases.filter { !storage.enabledSports.contains($0) }
            if !disabledSports.isEmpty {
                Menu {
                    ForEach(disabledSports, id: \.self) { sport in
                        Button {
                            browseSport = sport
                        } label: {
                            Label(sport.displayName, systemImage: sport.systemImage)
                        }
                    }
                } label: {
                    Label("Browse other sports", systemImage: "magnifyingglass")
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
                AdaptiveGameDetail(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
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

    private func nextGameHint(sport: SportType, date: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: sport.systemImage)
                .foregroundStyle(sport.color)
            Text("Next \(sport.displayName) game: \(date.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated)))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func nextGamesHint(date: Date, sportCounts: [SportType: Int], onTap: @escaping () -> Void) -> some View {
        let ordered = sportCounts.sorted { $0.value > $1.value }
        let visible = ordered.prefix(3).map(\.key)
        let overflow = max(0, ordered.count - visible.count)

        return Button(action: onTap) {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.secondary)
                    Text("Next games: \(date.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !visible.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(visible, id: \.self) { sport in
                            Image(systemName: sport.systemImage)
                                .foregroundStyle(sport.color)
                                .font(.subheadline)
                        }
                        if overflow > 0 {
                            Text("+\(overflow)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
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

    // MARK: - Ad Helpers

    @ViewBuilder
    private func sportSectionContent(games: [GameWithTeams], region: String?, adPlan: FeedAdPlan) -> some View {
        let hasTennisMatches = games.contains { $0.game.isTennisMatch }
        if hasTennisMatches {
            // Tennis groups games into per-tournament disclosure groups; we
            // don't inline ads inside those nested lists.
            tennisTournamentContent(games: games)
        } else {
            flatGameList(games: games, region: region, adPlan: adPlan)
        }
    }

    @ViewBuilder
    private func tennisTournamentContent(games: [GameWithTeams]) -> some View {
        let grouped = groupedByTournament(games)
        ForEach(grouped, id: \.key) { tournamentName, matches in
            DisclosureGroup {
                flatGameList(games: matches, region: nil, adPlan: FeedAdPlan())
            } label: {
                HStack {
                    Text(tournamentName)
                        .font(.subheadline.weight(.medium))
                    Text("(\(matches.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

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

    @ViewBuilder
    private func flatGameList(games: [GameWithTeams], region: String?, adPlan: FeedAdPlan) -> some View {
        ForEach(Array(games.enumerated()), id: \.element.id) { index, gameWithTeams in
            gameRow(for: gameWithTeams, isLive: false)
            #if os(iOS)
            if let region,
               let slot = adPlan.slot(region: region, row: index),
               let ad = adManager.adForSlot(slot) {
                NativeAdCardView(nativeAd: ad)
            }
            #endif
        }
    }

    #if os(iOS)
    /// One globally-capped ad layout for the whole day feed: a single lead ad
    /// above the per-sport sections, then ads spread across those sections in
    /// order. The total honors `AdConfiguration.maxAdsPerScreen` and no creative
    /// repeats. Empty for Pro users / kill switch.
    private var classicAdPlan: FeedAdPlan {
        guard !subscriptionManager.isPro, AdConfiguration.isEnabled else { return FeedAdPlan() }
        var planner = FeedAdPlanner(cap: AdConfiguration.maxAdsPerScreen)
        planner.offerSingle(region: "lead")
        for (i, section) in filteredOtherBySport.enumerated() {
            planner.offerFlatList(region: "sport-\(i)", count: section.games.count)
        }
        return planner.plan
    }
    #else
    /// macOS has no AdMob SDK — the day feed never shows ads, so the plan is empty.
    private var classicAdPlan: FeedAdPlan { FeedAdPlan() }
    #endif
}

#Preview {
    DayPage(shouldShowSportsCalProAlert: .constant(false), spotlightGameID: .constant(nil))
        .environment(GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites()))
        .environment(UserDefaultStorage())
        .environment(Favorites())
        .environment(EngagementTracker())
        .environment(SubscriptionManager.shared)
        #if os(iOS)
        .environment(NativeAdManager())
        #endif
}
