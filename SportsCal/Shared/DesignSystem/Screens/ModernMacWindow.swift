//
//  ModernMacWindow.swift
//  SportsCal — Design System v1.0 (Phase J follow-up)
//
//  Two-column macOS layout with a closeable trailing inspector:
//    [ Sidebar | Today (hero strip + sectioned/agenda) | (.inspector) ]
//
//  Sidebar lists sports + favorites with sport-tinted accent stripes.
//  The middle pane is a hero strip (live or pinned games) above the
//  user's chosen layout: sectioned (Upcoming/Final cards) or agenda
//  (chronological with a left time gutter). Selecting a tile populates
//  the closeable inspector on the right.
//

#if os(macOS)
import SwiftUI
import SportsCalModel
import NukeUI
import AppKit

struct ModernMacWindow: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites
    @Environment(\.openWindow) private var openWindow

    @State private var scope: MacScope = .allSports
    @State private var selectedGame: Game? = nil
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var searchText: String = ""

    @AppStorage("mac.window.layoutMode") private var layoutModeRaw: String = LayoutMode.sectioned.rawValue
    private var layoutMode: LayoutMode {
        LayoutMode(rawValue: layoutModeRaw) ?? .sectioned
    }

    /// User-pinned hero game id (empty string = no pin → multi-hero auto mode).
    /// Mirrored to UserDefaults manually so `withAnimation` participates
    /// in the change (AppStorage writes don't always pick up the animation
    /// transaction, which made the pin feel stuck before the layout caught up).
    @State private var pinnedGameID: String = UserDefaults.standard.string(forKey: Self.pinnedKey) ?? ""
    private static let pinnedKey = "mac.window.pinnedGameID"

    @State private var inspectorVisible: Bool = true

    /// Key of the game tile/row/hero currently under the pointer — drives the
    /// Mac hover affordance (lift + outline + link cursor).
    @State private var hoveredGameID: String?

    private static let pinAnimation: Animation = .spring(response: 0.32, dampingFraction: 0.86)

    /// Single entry point for changing the pin so the same animation +
    /// persistence path runs from every call site (corner button, context
    /// menu, stale-day clear). The UserDefaults write is deferred so it
    /// doesn't block the animation from kicking off.
    private func setPinned(_ value: String) {
        withAnimation(Self.pinAnimation) {
            pinnedGameID = value
        }
        Task.detached(priority: .background) {
            UserDefaults.standard.set(value, forKey: Self.pinnedKey)
        }
    }

    private enum LayoutMode: String, CaseIterable {
        case sectioned, agenda, board
        var symbol: String {
            switch self {
            case .sectioned: return "rectangle.grid.1x2"
            case .agenda:    return "calendar.day.timeline.left"
            case .board:     return "rectangle.split.3x1"
            }
        }
        var label: String {
            switch self {
            case .sectioned: return "Sectioned"
            case .agenda:    return "Agenda"
            case .board:     return "Board"
            }
        }
    }

    /// Sidebar selection scope — drives what the grid/board shows.
    private enum MacScope: Hashable {
        case allSports
        case liveNow
        case favorites
        case sport(SportType)
        case team(String)   // favorite team id

        var title: String {
            switch self {
            case .allSports:     return "Today"
            case .liveNow:       return "Live Now"
            case .favorites:     return "Favorites"
            case .sport(let s):  return s.displayName
            case .team:          return "Team"
            }
        }
    }

    private let calendar = Calendar.current

    /// The selected day's games honoring sport prefs / hidden competitions /
    /// favorites-only — but NOT the sidebar scope or search. Sidebar row counts
    /// derive from this so they stay stable regardless of what's selected.
    private var baseDayGames: [Game] {
        // Touch preferenceVersion so this view re-evaluates when hiddenCompetitions
        // / favoritesOnlyCompetitions change (those AppStorage props are
        // @ObservationIgnored; CloudSyncManager bumps preferenceVersion on remote apply).
        _ = storage.preferenceVersion
        let start = calendar.startOfDay(for: selectedDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let perLeagueFavOnly = storage.favoritesOnlyCompetitions
        return (viewModel.totalGames ?? [])
            .filter { game in
                guard let d = game.standardDate, d >= start, d < end else { return false }
                guard let sport = game.sportType else { return false }
                if !isSportEnabled(sport) { return false }
                // Hidden competition filter (mirrors filterAndSortGamesFromUserPreferences)
                let leagueName: String? = {
                    guard let id = game.idLeague,
                          let intID = Int(id),
                          let league = Leagues(rawValue: intID) else { return nil }
                    return league.leagueName
                }()
                if let leagueName, storage.hiddenCompetitions.contains(leagueName) {
                    return false
                }
                // Favorites-only filter (mirrors GameViewModel.applyFavoritesFilter):
                // sport-level flag wins; otherwise honor per-league flags.
                if storage.favoritesOnly(for: sport) {
                    if !favorites.matches(game) { return false }
                } else if let leagueName,
                          perLeagueFavOnly.contains(leagueName),
                          !favorites.matches(game) {
                    return false
                }
                return true
            }
            .sorted { ($0.standardDate ?? .distantPast) < ($1.standardDate ?? .distantPast) }
    }

    /// `baseDayGames` narrowed by the sidebar scope and the search field — this
    /// is what the grid/board actually renders.
    private var todayGames: [Game] {
        let liveIDs: Set<String> = scopeNeedsLiveSet ? Set(viewModel.liveEvents.map(\.id)) : []
        return baseDayGames.filter { game in
            guard let sport = game.sportType else { return false }
            return matchesScope(game, sport: sport, liveIDs: liveIDs) && matchesSearch(game)
        }
    }

    /// Date components (day/month/year) of every visible game in `totalGames`,
    /// used by the date scrubber to render "has games" dots. Honors sport prefs,
    /// hidden competitions, and favorites-only filters so dots match what's
    /// actually visible.
    private var datesWithGames: Set<DateComponents> {
        _ = storage.preferenceVersion
        let perLeagueFavOnly = storage.favoritesOnlyCompetitions
        var set: Set<DateComponents> = []
        let liveIDs: Set<String> = scopeNeedsLiveSet ? Set(viewModel.liveEvents.map(\.id)) : []
        for game in (viewModel.totalGames ?? []) {
            guard let d = game.standardDate, let sport = game.sportType else { continue }
            if !isSportEnabled(sport) { continue }
            if !matchesScope(game, sport: sport, liveIDs: liveIDs) { continue }
            if !matchesSearch(game) { continue }
            let leagueName: String? = {
                guard let id = game.idLeague,
                      let intID = Int(id),
                      let league = Leagues(rawValue: intID) else { return nil }
                return league.leagueName
            }()
            if let leagueName, storage.hiddenCompetitions.contains(leagueName) { continue }
            if storage.favoritesOnly(for: sport) {
                if !favorites.matches(game) { continue }
            } else if let leagueName,
                      perLeagueFavOnly.contains(leagueName),
                      !favorites.matches(game) {
                continue
            }
            set.insert(calendar.dateComponents([.day, .month, .year], from: d))
        }
        return set
    }

    /// Count of games for a sport on the selected date — same filter as `todayGames`.
    private func todayCount(for sport: SportType) -> Int {
        _ = storage.preferenceVersion
        let start = calendar.startOfDay(for: selectedDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let perLeagueFavOnly = storage.favoritesOnlyCompetitions
        let sportFavOnly = storage.favoritesOnly(for: sport)
        return (viewModel.totalGames ?? []).reduce(into: 0) { acc, game in
            guard let d = game.standardDate, d >= start, d < end else { return }
            guard game.sportType == sport else { return }
            let leagueName: String? = {
                guard let id = game.idLeague,
                      let intID = Int(id),
                      let league = Leagues(rawValue: intID) else { return nil }
                return league.leagueName
            }()
            if let leagueName, storage.hiddenCompetitions.contains(leagueName) { return }
            if sportFavOnly {
                if !favorites.matches(game) { return }
            } else if let leagueName,
                      perLeagueFavOnly.contains(leagueName),
                      !favorites.matches(game) {
                return
            }
            acc += 1
        }
    }

    private func isSportEnabled(_ sport: SportType) -> Bool {
        switch sport {
        case .basketball: return storage.shouldShowNBA || storage.shouldShowWNBA
        case .soccer:     return storage.shouldShowSoccer
        case .hockey:     return storage.shouldShowNHL
        case .mlb:        return storage.shouldShowMLB
        case .nfl:        return storage.shouldShowNFL
        case .golf:       return storage.shouldShowGolf
        case .tennis:     return storage.shouldShowTennis
        case .racing:     return storage.shouldShowRacing
        }
    }

    // MARK: - Scope & search

    /// Whether the current scope needs the (slightly costly) live-id set built.
    private var scopeNeedsLiveSet: Bool {
        if case .liveNow = scope { return true }
        return false
    }

    private func gameInvolvesTeam(_ game: Game, id: String) -> Bool {
        game.idHomeTeam == id || game.idAwayTeam == id
    }

    private func matchesScope(_ game: Game, sport: SportType, liveIDs: Set<String>) -> Bool {
        switch scope {
        case .allSports:     return true
        case .liveNow:       return liveIDs.contains(game.id)
        case .favorites:     return favorites.matches(game)
        case .sport(let s):  return sport == s
        case .team(let id):  return gameInvolvesTeam(game, id: id)
        }
    }

    private func matchesSearch(_ game: Game) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return game.strHomeTeam.lowercased().contains(q)
            || game.strAwayTeam.lowercased().contains(q)
    }

    /// Favorite teams resolved to display models (name + badge), sorted by name.
    private var favoriteTeams: [Team] {
        favorites.teamIDs
            .compactMap { TeamsManager.shared.team(byID: $0) }
            .sorted { ($0.strTeam ?? "") < ($1.strTeam ?? "") }
    }

    /// The soonest live-or-upcoming game involving a favorite team, for the
    /// "My Teams" sidebar subtitle.
    private func nextGame(forTeamID id: String) -> Game? {
        let now = Date()
        return (viewModel.totalGames ?? [])
            .filter { gameInvolvesTeam($0, id: id) }
            .filter { ($0.standardDate ?? .distantPast) >= calendar.date(byAdding: .hour, value: -4, to: now)! }
            .min { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
    }

    private enum GameState { case live, final, pre }

    /// Single-game classifier. The `isLive` closure is built once per pass so
    /// callers can categorize many games without rebuilding the live-id set
    /// — repeatedly recomputing `Set(viewModel.liveEvents.map(\.id))` was the
    /// dominant cost during pin-driven recomputes.
    private func gameState(_ game: Game, isLive: (Game) -> Bool, now: Date) -> GameState {
        if isLive(game) { return .live }
        if let d = game.standardDate, d > now { return .pre }
        if isExplicitlyFinal(game) { return .final }
        if let d = game.standardDate {
            let elapsed = now.timeIntervalSince(d)
            if elapsed < 6 * 60 * 60 { return .live }
            return .final
        }
        return .pre
    }

    /// Convenience wrapper used outside the bucket pipeline (e.g. row builders
    /// that need the per-row state). Builds the live-id set once per call.
    private func gameState(_ game: Game) -> GameState {
        let liveIDs = Set(viewModel.liveEvents.map(\.id))
        return gameState(game, isLive: { liveIDs.contains($0.id) }, now: Date())
    }

    /// Pre-categorized view of the visible day. Built in one pass so we don't
    /// re-scan `todayGames` in every section/strip property.
    private struct DayBuckets {
        let hero: [Game]
        let restLive: [Game]
        let restPre: [Game]
        let restFinal: [Game]
        let restAll: [Game]
        /// True when `hero.first` is the user's pinned game (drives the
        /// "big card on top, mini row beneath" layout).
        let pinnedHeroLayout: Bool
        /// Stable identity for animation `value:` — changes when the visible
        /// hero set changes, but not on every reflow.
        let heroKey: String
        /// Cached counts so the grid header doesn't re-walk `todayGames`.
        let totalCount: Int
        let liveCount: Int
    }

    private func computeDayBuckets() -> DayBuckets {
        let games = todayGames
        let liveIDs = Set(viewModel.liveEvents.map(\.id))
        let isLive: (Game) -> Bool = { liveIDs.contains($0.id) }
        let now = Date()

        var live: [Game] = []
        var pre: [Game] = []
        var final: [Game] = []
        for g in games {
            switch gameState(g, isLive: isLive, now: now) {
            case .live:  live.append(g)
            case .pre:   pre.append(g)
            case .final: final.append(g)
            }
        }

        let upcomingFromNow = pre.filter { ($0.standardDate ?? .distantPast) >= now }
        let auto: [Game] = !live.isEmpty
            ? Array(live.prefix(3))
            : Array(upcomingFromNow.prefix(3))

        var hero: [Game]
        var pinnedHero = false
        if !pinnedGameID.isEmpty,
           let pinned = games.first(where: { gameKey($0) == pinnedGameID }) {
            let others = auto.filter { gameKey($0) != pinnedGameID }
            hero = [pinned] + Array(others.prefix(2))
            pinnedHero = true
        } else {
            hero = auto
        }

        let heroIDs = Set(hero.map(gameKey))
        let restLive  = live.filter  { !heroIDs.contains(gameKey($0)) }
        let restPre   = pre.filter   { !heroIDs.contains(gameKey($0)) }
        let restFinal = final.filter { !heroIDs.contains(gameKey($0)) }
        let restAll   = games.filter { !heroIDs.contains(gameKey($0)) }

        return DayBuckets(
            hero: hero,
            restLive: restLive,
            restPre: restPre,
            restFinal: restFinal,
            restAll: restAll,
            pinnedHeroLayout: pinnedHero,
            heroKey: hero.map(gameKey).joined(separator: ","),
            totalCount: games.count,
            liveCount: live.count
        )
    }

    private func isExplicitlyFinal(_ game: Game) -> Bool {
        let finalStatuses: Set<String> = ["FT", "AOT", "Final", "Final/OT", "AP", "post"]
        if let s = game.strStatus, finalStatuses.contains(s) { return true }
        if let p = game.strProgress, finalStatuses.contains(p) { return true }
        return game.isCompleted == true
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            grid
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                inspectorVisible.toggle()
                            }
                        } label: {
                            Image(systemName: "sidebar.right")
                        }
                        .help(inspectorVisible ? "Hide inspector" : "Show inspector")
                    }
                }
                .inspector(isPresented: $inspectorVisible) {
                    inspector
                        .inspectorColumnWidth(min: 320, ideal: 380, max: 540)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, prompt: "Search teams")
        .onChange(of: selectedDate) { _, newValue in
            clearPinIfStale()
            viewModel.ensureGamesLoaded(for: newValue)
        }
        .task {
            viewModel.ensureGamesLoaded(for: selectedDate)
        }
        .onChange(of: scope) { _, newScope in
            // Selecting a team jumps to its next live/upcoming game so the
            // detail isn't empty when that team doesn't play on the current day.
            if case .team(let id) = newScope,
               let game = nextGame(forTeamID: id),
               let date = game.standardDate {
                withAnimation { selectedDate = calendar.startOfDay(for: date) }
            }
        }
        // Menu-bar commands (SportsCalApp .commands) act on this window's state.
        .onReceive(NotificationCenter.default.publisher(for: .jumpToToday)) { _ in
            withAnimation { selectedDate = calendar.startOfDay(for: Date()) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .previousDay)) { _ in
            shiftDay(by: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextDay)) { _ in
            shiftDay(by: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { inspectorVisible.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLayoutMode)) { _ in
            let all = LayoutMode.allCases
            if let i = all.firstIndex(of: layoutMode) {
                layoutModeRaw = all[(i + 1) % all.count].rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFavoritesOnly)) { _ in
            toggleFavoritesOnly()
        }
        .onReceive(NotificationCenter.default.publisher(for: .printSchedule)) { _ in
            printSchedule()
        }
    }

    /// Prints the visible day's schedule via a print-friendly SwiftUI view
    /// hosted in an NSView. NSPrintOperation paginates by the host view's height.
    private func printSchedule() {
        let title = selectedDate.formatted(date: .complete, time: .omitted)
        let games = todayGames
        let printable = SchedulePrintView(title: title, games: games)
        let hosting = NSHostingView(rootView: printable)
        let height = max(240, CGFloat(games.count) * 26 + 140)
        hosting.frame = NSRect(x: 0, y: 0, width: 540, height: height)
        let operation = NSPrintOperation(view: hosting)
        operation.printInfo.horizontalPagination = .fit
        operation.run()
    }

    private func shiftDay(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        withAnimation { selectedDate = calendar.startOfDay(for: next) }
    }

    /// Toggles the favorites-only filter for the selected sport, or — when
    /// viewing all sports — flips every ordered sport together.
    private func toggleFavoritesOnly() {
        if case .sport(let sport) = scope {
            storage.setFavoritesOnly(sport, value: !storage.favoritesOnly(for: sport))
        } else {
            let sports = storage.orderedSports
            let allOn = !sports.isEmpty && sports.allSatisfy { storage.favoritesOnly(for: $0) }
            for sport in sports {
                storage.setFavoritesOnly(sport, value: !allOn)
            }
        }
        storage.bumpPreferenceVersion()
    }

    /// Drops the pin when the pinned game is no longer in the visible day's
    /// game set — keeps the hero strip honest after the user scrubs to a
    /// different date.
    private func clearPinIfStale() {
        guard !pinnedGameID.isEmpty else { return }
        if !todayGames.contains(where: { gameKey($0) == pinnedGameID }) {
            setPinned("")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $scope) {
            Section {
                scopeRow(.allSports, title: "All Sports",
                         systemImage: "sportscourt", count: baseDayGames.count)
                scopeRow(.liveNow, title: "Live Now",
                         systemImage: "dot.radiowaves.left.and.right",
                         count: liveTodayCount, isLive: true)
                scopeRow(.favorites, title: "Favorites",
                         systemImage: "star.fill",
                         count: favoritesTodayCount, tint: .yellow)
            }

            Section("Sports") {
                ForEach(storage.orderedSports, id: \.self) { sport in
                    sportRow(sport)
                        .tag(MacScope.sport(sport))
                }
            }

            if !favoriteTeams.isEmpty {
                Section("My Teams") {
                    ForEach(favoriteTeams, id: \.idTeam) { team in
                        if let id = team.idTeam {
                            teamRow(team)
                                .tag(MacScope.team(id))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Scoreline")
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
    }

    private var liveTodayCount: Int {
        let liveIDs = Set(viewModel.liveEvents.map(\.id))
        return baseDayGames.filter { liveIDs.contains($0.id) }.count
    }

    private var favoritesTodayCount: Int {
        baseDayGames.filter { favorites.matches($0) }.count
    }

    /// A smart-filter row (All Sports / Live Now / Favorites).
    private func scopeRow(
        _ scopeValue: MacScope,
        title: String,
        systemImage: String,
        count: Int,
        isLive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        HStack(spacing: .appSpace2) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .foregroundStyle(tint ?? (isLive ? Color.appLive : Color.appInkSoft))
                .frame(width: 18)
            Text(title)
                .font(.appHeadline)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(isLive ? Color.appLive : Color.appInkFaint)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .tag(scopeValue)
    }

    /// A favorite-team row with badge + next-game / live subtitle.
    private func teamRow(_ team: Team) -> some View {
        let next = team.idTeam.flatMap { nextGame(forTeamID: $0) }
        let isLive = next.map { gameState($0) == .live } ?? false
        return HStack(spacing: .appSpace2) {
            teamBadge(team.strTeamBadge)
            VStack(alignment: .leading, spacing: 1) {
                Text(team.strTeam ?? "Team")
                    .font(.appHeadline)
                    .lineLimit(1)
                if let next {
                    Text(teamSubtitle(next, isLive: isLive))
                        .font(.appFootnote)
                        .foregroundStyle(isLive ? Color.appLive : Color.appInkFaint)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isLive {
                Circle().fill(Color.appLive).frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 2)
    }

    private func teamBadge(_ badge: String?) -> some View {
        Group {
            if let badge, let url = URL(string: badge) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "shield.fill").foregroundStyle(Color.appInkFaint)
                    }
                }
            } else {
                Image(systemName: "shield.fill").foregroundStyle(Color.appInkFaint)
            }
        }
        .frame(width: 20, height: 20)
    }

    private func teamSubtitle(_ game: Game, isLive: Bool) -> String {
        if isLive { return "LIVE · \(scoreLine(for: game) ?? "—")" }
        guard let d = game.standardDate else { return "Scheduled" }
        if calendar.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func sportRow(_ sport: SportType) -> some View {
        // Touch preferenceVersion so the favorites-only checkmark in the
        // context menu reflects the current state (the underlying flags are
        // @ObservationIgnored AppStorage props).
        _ = storage.preferenceVersion
        let liveCount = viewModel.liveGameCountsBySport[sport] ?? 0
        let total = todayCount(for: sport)
        let accent = Color.app(sport)
        let favOnly = storage.favoritesOnly(for: sport)
        return HStack(spacing: .appSpace2) {
            Image(systemName: sport.systemImage)
                .imageScale(.medium)
                .foregroundStyle(accent)
                .frame(width: 18)
            Text(sport.displayName)
                .font(.appHeadline)
            if favOnly {
                Image(systemName: "star.fill")
                    .imageScale(.small)
                    .foregroundStyle(.yellow)
                    .help("Showing only favorite teams")
            }
            Spacer()
            if liveCount > 0 {
                HStack(spacing: 3) {
                    Circle().fill(Color.appLive).frame(width: 5, height: 5)
                    Text("\(liveCount)")
                        .font(.appFootnote)
                        .tracking(1)
                }
                .foregroundStyle(Color.appLive)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.appLive.opacity(0.12), in: Capsule())
            }
            Text("\(max(liveCount, total))")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color.appInkFaint)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 2)
                .padding(.vertical, 2)
                .allowsHitTesting(false)
        }
        .contextMenu {
            Toggle(isOn: Binding(
                get: { storage.favoritesOnly(for: sport) },
                set: { newValue in
                    storage.setFavoritesOnly(sport, value: newValue)
                    storage.bumpPreferenceVersion()
                }
            )) {
                Label("Show only favorite teams", systemImage: "star.fill")
            }
        }
    }

    // MARK: - Middle grid

    private var grid: some View {
        // Compute once per render — every section/strip below reads from the
        // same `buckets` so we don't re-scan or reclassify games.
        let buckets = computeDayBuckets()
        let isEmpty = buckets.hero.isEmpty && buckets.restAll.isEmpty
        return Group {
            if layoutMode == .board {
                // The board manages its own (horizontal) scrolling, so it lives
                // outside the vertical ScrollView used by the other modes.
                boardGrid(isEmpty: isEmpty, buckets: buckets)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: .appSpace5) {
                        gridHeader(buckets)
                            .padding(.horizontal, .appSpace4)
                            .padding(.top, .appSpace3)

                        ModernDateScrubber(
                            selectedDate: $selectedDate,
                            datesWithGames: datesWithGames
                        )
                        .padding(.horizontal, .appSpace4)

                        if isEmpty {
                            EmptyStateView.quietDay()
                                .frame(minHeight: 320)
                        } else {
                            heroStrip(buckets)
                                .padding(.horizontal, .appSpace4)

                            switch layoutMode {
                            case .sectioned: sections(buckets)
                            case .agenda:    agenda(buckets)
                            case .board:     EmptyView() // handled above
                            }
                        }
                    }
                    .padding(.bottom, .appSpace5)
                }
            }
        }
        .background(Color.appBackground)
        // Arrow keys move the selection through the day's games; the selected
        // tile's ring is the focus indicator, so we suppress the container ring.
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand { direction in moveSelection(direction) }
        .navigationTitle(scopeTitle)
        .navigationSplitViewColumnWidth(min: 360, ideal: 540)
    }

    /// Board (column-per-sport) layout — a scoreboard wall that uses the full
    /// width of the Mac window. Header + date scrubber stay pinned; the board
    /// fills the remaining height and scrolls horizontally.
    @ViewBuilder
    private func boardGrid(isEmpty: Bool, buckets: DayBuckets) -> some View {
        VStack(alignment: .leading, spacing: .appSpace3) {
            gridHeader(buckets)
                .padding(.horizontal, .appSpace4)
                .padding(.top, .appSpace3)

            ModernDateScrubber(
                selectedDate: $selectedDate,
                datesWithGames: datesWithGames
            )
            .padding(.horizontal, .appSpace4)

            if isEmpty {
                EmptyStateView.quietDay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GameBoardLayout(
                    columns: boardColumns,
                    favorites: favorites,
                    onJumpToDate: { date in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = calendar.startOfDay(for: date)
                        }
                    }
                ) { gwt, isLive in
                    boardContent(gwt, isLive: isLive)
                }
                .frame(maxHeight: .infinity)
                .padding(.bottom, .appSpace3)
            }
        }
    }

    /// One column per sport that has games in the current (scope/search-filtered)
    /// day, live games on top. Reuses the shared `GameBoardLayout`/`SportColumnView`.
    private var boardColumns: [BoardColumn] {
        let allowedIDs = Set(todayGames.map(\.id))
        let gwts = viewModel.gamesWithTeams(for: selectedDate)
            .filter { allowedIDs.contains($0.id) }
        let liveIDs = Set(viewModel.liveEvents.map(\.id))

        var grouped: [SportType: [GameWithTeams]] = [:]
        for gwt in gwts {
            guard let sport = gwt.game.sportType else { continue }
            grouped[sport, default: []].append(gwt)
        }

        return storage.orderedSports.compactMap { sport -> BoardColumn? in
            let sportGames = grouped[sport] ?? []
            guard !sportGames.isEmpty else { return nil }
            let live = sportGames.filter { liveIDs.contains($0.id) }
            let liveSet = Set(live.map(\.id))
            let other = sportGames
                .filter { !liveSet.contains($0.id) }
                .sorted { a, b in
                    let aDone = a.game.hasDoneStatus
                    let bDone = b.game.hasDoneStatus
                    if aDone != bDone { return !aDone }
                    return (a.game.standardDate ?? .distantPast) < (b.game.standardDate ?? .distantPast)
                }
            return BoardColumn(sport: sport, liveGames: live, otherGames: other, nextGameDate: nil)
        }
    }

    /// A single board cell: tap selects into the inspector; drag exports the
    /// game; right-click opens it in its own window. BoardGameCard supplies the
    /// card chrome, so this stays lean.
    @ViewBuilder
    private func boardContent(_ gwt: GameWithTeams, isLive: Bool) -> some View {
        let game = gwt.game
        Button {
            selectedGame = game
        } label: {
            Group {
                switch gameState(game) {
                case .live:  liveRow(game)
                case .final: finalRow(game)
                case .pre:   preRow(game)
                }
            }
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .draggable(dragPayload(for: game))
        .contextMenu {
            Button("Open in New Window") {
                openWindow(id: "game-detail", value: game.id)
            }
        }
    }

    private var scopeTitle: String {
        if case .team(let id) = scope {
            return TeamsManager.shared.team(byID: id)?.strTeam ?? "Team"
        }
        return scope.title
    }

    /// Moves `selectedGame` through the visible day's games via arrow keys.
    private func moveSelection(_ direction: MoveCommandDirection) {
        let games = todayGames
        guard !games.isEmpty else { return }
        guard let current = selectedGame,
              let idx = games.firstIndex(where: { $0.id == current.id }) else {
            selectedGame = games.first
            return
        }
        let delta: Int
        switch direction {
        case .up, .left:    delta = -1
        case .down, .right: delta = 1
        @unknown default:   delta = 0
        }
        let next = min(max(idx + delta, 0), games.count - 1)
        selectedGame = games[next]
    }

    /// Categorized renderings of `todayGames` minus games already shown in the
    /// hero strip — each section only renders when non-empty so the page
    /// collapses gracefully on quiet days.
    @ViewBuilder
    private func sections(_ buckets: DayBuckets) -> some View {
        if !buckets.restLive.isEmpty {
            section(title: "ALSO LIVE", count: buckets.restLive.count, accent: Color.appLive) {
                VStack(spacing: .appSpace3) {
                    ForEach(buckets.restLive, id: \.id) { game in
                        selectableRow(game) { liveRow(game) }
                    }
                }
            }
        }

        if !buckets.restPre.isEmpty {
            section(title: "UPCOMING", count: buckets.restPre.count, accent: Color.appInkSoft) {
                gridOfTiles(buckets.restPre, columns: 2)
            }
        }

        if !buckets.restFinal.isEmpty {
            section(title: "FINAL", count: buckets.restFinal.count, accent: Color.appInkFaint) {
                gridOfFinals(buckets.restFinal, columns: 2)
            }
        }
    }

    // MARK: - Hero strip (multi-hero or pinned single hero)

    /// Stable string key for AppStorage persistence and identity comparisons.
    private func gameKey(_ g: Game) -> String { String(describing: g.id) }

    @ViewBuilder
    private func heroStrip(_ buckets: DayBuckets) -> some View {
        let games = buckets.hero
        Group {
            if games.isEmpty {
                EmptyView()
            } else if buckets.pinnedHeroLayout {
                // Pinned full-width featured card + remaining auto-picks as a
                // mini-hero row beneath it — keeps other live games visible.
                VStack(alignment: .leading, spacing: .appSpace3) {
                    heroWrapper(games[0]) { featuredCard(games[0]) }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    let rest = Array(games.dropFirst())
                    if !rest.isEmpty {
                        HStack(alignment: .top, spacing: .appSpace3) {
                            ForEach(rest, id: \.id) { g in
                                heroWrapper(g) { miniHeroCard(g) }
                                    .frame(maxWidth: .infinity)
                                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }
                        }
                    }
                }
            } else if games.count == 1 {
                heroWrapper(games[0]) { featuredCard(games[0]) }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                HStack(alignment: .top, spacing: .appSpace3) {
                    ForEach(games, id: \.id) { g in
                        heroWrapper(g) { miniHeroCard(g) }
                            .frame(maxWidth: .infinity)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
        }
        .animation(Self.pinAnimation, value: buckets.heroKey)
    }

    /// Selectable hero card with a pin/unpin overlay in the top-trailing corner.
    @ViewBuilder
    private func heroWrapper<Content: View>(
        _ game: Game,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let key = gameKey(game)
        let isHovered = (hoveredGameID == key)
        ZStack(alignment: .topTrailing) {
            Button {
                selectedGame = game
            } label: {
                content()
                    .scaleEffect(isHovered ? 1.008 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: isHovered)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hovering in
                if hovering { hoveredGameID = key }
                else if hoveredGameID == key { hoveredGameID = nil }
            }
            .draggable(dragPayload(for: game))
            .contextMenu {
                Button("Open in New Window") {
                    openWindow(id: "game-detail", value: game.id)
                }
            }
            pinToggle(for: game)
                .padding(.appSpace3)
        }
    }

    /// Pin / unpin button. When this game is pinned, shows pin.slash to undo;
    /// otherwise shows pin to set this game as the focused hero.
    private func pinToggle(for game: Game) -> some View {
        let key = gameKey(game)
        let isPinned = (pinnedGameID == key)
        return Button {
            setPinned(isPinned ? "" : key)
        } label: {
            Image(systemName: isPinned ? "pin.slash.fill" : "pin")
                .font(.caption)
                .foregroundStyle(isPinned ? Color.appLive : Color.appInkFaint)
                .padding(6)
                .background(
                    Circle().fill(Color.appBackground.opacity(0.6))
                )
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Unpin hero" : "Pin as hero")
    }

    /// Compact hero used when 2–3 games are featured side-by-side. Sport stripe
    /// + status eyebrow + badges + matchup + score.
    private func miniHeroCard(_ game: Game) -> some View {
        let sport = game.sportType ?? .basketball
        let state = gameState(game)
        let accent = Color.app(sport)
        return VStack(alignment: .leading, spacing: .appSpace2) {
            heroStatusEyebrow(for: game, state: state, accent: accent)

            HStack(spacing: 6) {
                miniBadge(badgeURL(game.strAwayTeamBadge))
                miniBadge(badgeURL(game.strHomeTeamBadge))
                Text("\(game.strAwayTeam) · \(game.strHomeTeam)")
                    .font(.appHeadline)
                    .lineLimit(1)
            }

            if let score = miniScore(for: game, state: state) {
                Text(score)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .monospacedDigit()
            } else {
                Text("vs")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Color.appInkFaint)
            }
        }
        .padding(.appSpace4)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(
            RoundedRectangle.appShape(.appRadiusMD)
                .fill(Color.appSurface)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .clipShape(RoundedRectangle.appShape(.appRadiusMD))
                .allowsHitTesting(false)
        }
        .appShadow(.rest)
    }

    private func miniBadge(_ url: URL?) -> some View {
        Group {
            if let url {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Circle().fill(Color.appAlt)
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
    }

    private func miniScore(for game: Game, state: GameState) -> String? {
        switch state {
        case .live, .final:
            guard let h = game.intHomeScore, let a = game.intAwayScore else { return nil }
            return "\(a) — \(h)"
        case .pre:
            return nil
        }
    }

    // MARK: - Agenda layout (chronological list, hero handled separately)

    @ViewBuilder
    private func agenda(_ buckets: DayBuckets) -> some View {
        if !buckets.restAll.isEmpty {
            VStack(alignment: .leading, spacing: .appSpace3) {
                ForEach(buckets.restAll, id: \.id) { game in
                    agendaRow(game)
                }
            }
            .padding(.horizontal, .appSpace4)
        }
    }

    private func agendaRow(_ game: Game) -> some View {
        HStack(alignment: .top, spacing: .appSpace3) {
            timeGutter(for: game)
                .frame(width: 64, alignment: .trailing)
                .padding(.top, .appSpace3)
            selectableRow(game) {
                switch gameState(game) {
                case .live:  liveRow(game)
                case .pre:   preRow(game)
                case .final: finalRow(game)
                }
            }
        }
    }

    private func timeGutter(for game: Game) -> some View {
        Group {
            if gameState(game) == .live {
                VStack(alignment: .trailing, spacing: 2) {
                    Circle().fill(Color.appLive).frame(width: 6, height: 6)
                    Text("NOW")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .tracking(1)
                        .foregroundStyle(Color.appLive)
                }
            } else {
                Text(timeOnly(for: game))
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color.appInkSoft)
                    .monospacedDigit()
            }
        }
    }

    private func timeOnly(for game: Game) -> String {
        guard let d = game.standardDate else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    private func preRow(_ game: Game) -> some View {
        PreGameRow(
            sport: game.sportType ?? .basketball,
            matchup: "\(game.strAwayTeam) · \(game.strHomeTeam)",
            kickoffLabel: kickoffLabel(for: game),
            countdown: nil,
            contextLine: nil,
            awayBadgeURL: badgeURL(game.strAwayTeamBadge),
            homeBadgeURL: badgeURL(game.strHomeTeamBadge)
        )
    }

    /// Tall featured card. Mirrors the visual weight of a desktop "now playing"
    /// pane — sport stripe on the leading edge, big status eyebrow, oversized
    /// score, badges flanking the matchup.
    private func featuredCard(_ game: Game) -> some View {
        let sport = game.sportType ?? .basketball
        let state = gameState(game)
        let accent = Color.app(sport)
        return VStack(alignment: .leading, spacing: .appSpace4) {
            HStack(spacing: .appSpace2) {
                heroStatusEyebrow(for: game, state: state, accent: accent)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: sport.systemImage)
                    Text(sport.displayName.uppercased())
                        .font(.appCaption)
                        .tracking(1.2)
                }
                .foregroundStyle(accent)
            }

            HStack(alignment: .center, spacing: .appSpace3) {
                heroTeam(name: game.strAwayTeam, badge: badgeURL(game.strAwayTeamBadge))
                Spacer(minLength: .appSpace3)
                heroScore(for: game, state: state)
                Spacer(minLength: .appSpace3)
                heroTeam(name: game.strHomeTeam, badge: badgeURL(game.strHomeTeamBadge))
            }

            if let footer = heroFooter(for: game, state: state) {
                Text(footer)
                    .font(.appCallout)
                    .foregroundStyle(Color.appInkSoft)
                    .lineLimit(2)
            }
        }
        .padding(.appSpace4)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .background(
            RoundedRectangle.appShape(.appRadiusMD)
                .fill(Color.appSurface)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .clipShape(RoundedRectangle.appShape(.appRadiusMD))
                .allowsHitTesting(false)
        }
        .appShadow(.rest)
    }

    @ViewBuilder
    private func heroStatusEyebrow(for game: Game, state: GameState, accent: Color) -> some View {
        switch state {
        case .live:
            HStack(spacing: 6) {
                Circle().fill(Color.appLive).frame(width: 7, height: 7)
                Text(game.strProgress ?? "LIVE")
                    .font(.system(.callout, design: .monospaced).weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.appLive)
            }
        case .pre:
            Text(kickoffLabel(for: game).uppercased())
                .font(.appCaption)
                .tracking(1.4)
                .foregroundStyle(accent)
        case .final:
            Text("FINAL")
                .font(.appCaption)
                .tracking(1.4)
                .foregroundStyle(Color.appInkSoft)
        }
    }

    private func heroTeam(name: String, badge: URL?) -> some View {
        VStack(spacing: .appSpace2) {
            if let badge {
                LazyImage(url: badge) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Circle().fill(Color.appAlt)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            }
            Text(name)
                .font(.appHeadline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func heroScore(for game: Game, state: GameState) -> some View {
        switch state {
        case .live, .final:
            if let h = game.intHomeScore, let a = game.intAwayScore {
                HStack(alignment: .center, spacing: .appSpace2) {
                    Text(a).font(.system(size: 36, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("—").foregroundStyle(Color.appInkFaint).font(.title3)
                    Text(h).font(.system(size: 36, weight: .heavy, design: .rounded)).monospacedDigit()
                }
            } else {
                Text("vs").font(.title3).foregroundStyle(Color.appInkFaint)
            }
        case .pre:
            Text("vs")
                .font(.system(.title, design: .rounded).weight(.medium))
                .foregroundStyle(Color.appInkFaint)
        }
    }

    private func heroFooter(for game: Game, state: GameState) -> String? {
        switch state {
        case .live:
            if let lp = game.lastPlay, !lp.isEmpty { return lp }
            if let v = game.venueName, !v.isEmpty { return v }
            return nil
        case .pre:
            if let v = game.venueName, !v.isEmpty { return v }
            return nil
        case .final:
            if let v = game.venueName, !v.isEmpty { return v }
            return nil
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        count: Int,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            HStack(spacing: .appSpace2) {
                Text(title)
                    .font(.appCaption)
                    .tracking(1.4)
                    .foregroundStyle(accent)
                Text("\(count)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color.appInkFaint)
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, .appSpace4)
            content()
                .padding(.horizontal, .appSpace4)
        }
    }

    private func gridOfTiles(_ games: [Game], columns: Int) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: .appSpace2), count: columns),
            spacing: .appSpace2
        ) {
            ForEach(games, id: \.id) { game in
                selectableRow(game, radius: .appRadiusSM) { tileFor(game) }
            }
        }
    }

    private func gridOfFinals(_ games: [Game], columns: Int) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: .appSpace3), count: columns),
            spacing: .appSpace3
        ) {
            ForEach(games, id: \.id) { game in
                selectableRow(game) { finalRow(game) }
            }
        }
    }

    /// Wraps a section item in a button + selection ring + a "Pin as hero"
    /// context menu so the user can promote any non-hero game to the hero
    /// strip without leaving the list.
    @ViewBuilder
    private func selectableRow<Content: View>(
        _ game: Game,
        radius: CGFloat = .appRadiusMD,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let key = gameKey(game)
        let isPinned = (pinnedGameID == key)
        let isSelected = (selectedGame?.id == game.id)
        let isHovered = (hoveredGameID == key)
        Button {
            selectedGame = game
        } label: {
            content()
                .overlay(
                    RoundedRectangle.appShape(radius)
                        .stroke(
                            isSelected ? Color.appInk
                                : (isHovered ? Color.appInk.opacity(0.28) : Color.clear),
                            lineWidth: isSelected ? 2 : 1.5
                        )
                )
                .scaleEffect(isHovered && !isSelected ? 1.012 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            if hovering { hoveredGameID = key }
            else if hoveredGameID == key { hoveredGameID = nil }
        }
        .draggable(dragPayload(for: game))
        .contextMenu {
            Button("Open in New Window") {
                openWindow(id: "game-detail", value: game.id)
            }
            Button(isPinned ? "Unpin from hero" : "Pin as hero") {
                setPinned(isPinned ? "" : key)
            }
        }
    }

    /// Shareable text for dragging a game out to Calendar / Notes / Messages —
    /// matchup, kickoff, and the universal link when the event has a stable id.
    private func dragPayload(for game: Game) -> String {
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

    // MARK: - Per-state row builders

    private func liveRow(_ game: Game) -> some View {
        let sport = game.sportType ?? .basketball
        let matchup = "\(game.strAwayTeam) · \(game.strHomeTeam)"
        let score = scoreLine(for: game) ?? "—"
        return LiveGameRow(
            sport: sport,
            matchup: matchup,
            scoreLine: score,
            period: game.strProgress ?? "LIVE",
            clock: nil,
            subtext: nil,
            awayBadgeURL: badgeURL(game.strAwayTeamBadge),
            homeBadgeURL: badgeURL(game.strHomeTeamBadge)
        )
    }

    private func finalRow(_ game: Game) -> some View {
        let sport = game.sportType ?? .basketball
        let home = Int(game.intHomeScore ?? "") ?? 0
        let away = Int(game.intAwayScore ?? "") ?? 0
        return FinalGameRow(
            sport: sport,
            homeAbbr: game.strHomeTeam,
            awayAbbr: game.strAwayTeam,
            homeScore: home,
            awayScore: away,
            awayBadgeURL: badgeURL(game.strAwayTeamBadge),
            homeBadgeURL: badgeURL(game.strHomeTeamBadge)
        )
    }

    private func badgeURL(_ s: String?) -> URL? {
        guard let s, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private func gridHeader(_ buckets: DayBuckets) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrowText).appEyebrow()
                Text(headlineText(buckets))
                    .font(.appTitle)
            }
            Spacer()
            layoutPicker
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var layoutPicker: some View {
        Picker("Layout", selection: Binding(
            get: { layoutMode },
            set: { layoutModeRaw = $0.rawValue }
        )) {
            ForEach(LayoutMode.allCases, id: \.self) { mode in
                Image(systemName: mode.symbol)
                    .accessibilityLabel(mode.label)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 96)
    }

    private static let eyebrowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f
    }()

    private var eyebrowText: String {
        Self.eyebrowFormatter.string(from: selectedDate).uppercased()
    }

    private func headlineText(_ buckets: DayBuckets) -> String {
        if buckets.totalCount == 0 { return "nothing on today" }
        if buckets.liveCount == 0 { return "\(buckets.totalCount) on tap" }
        return "\(buckets.liveCount) live · \(buckets.totalCount) total"
    }

    @ViewBuilder
    private func tileFor(_ game: Game) -> some View {
        let sport = game.sportType ?? .basketball
        let matchup = "\(game.strAwayTeam) · \(game.strHomeTeam)"
        let away = badgeURL(game.strAwayTeamBadge)
        let home = badgeURL(game.strHomeTeamBadge)
        switch gameState(game) {
        case .live:
            CompactGameTile(
                sport: sport,
                state: .live,
                shortStatus: game.strProgress ?? "LIVE",
                matchup: matchup,
                scoreLine: scoreLine(for: game),
                awayBadgeURL: away,
                homeBadgeURL: home
            )
        case .final:
            CompactGameTile(
                sport: sport,
                state: .final,
                shortStatus: "FINAL",
                matchup: matchup,
                scoreLine: scoreLine(for: game),
                awayBadgeURL: away,
                homeBadgeURL: home
            )
        case .pre:
            CompactGameTile(
                sport: sport,
                state: .pre,
                shortStatus: kickoffLabel(for: game),
                matchup: matchup,
                scoreLine: nil,
                awayBadgeURL: away,
                homeBadgeURL: home
            )
        }
    }

    private func scoreLine(for game: Game) -> String? {
        guard let h = game.intHomeScore, let a = game.intAwayScore else { return nil }
        return "\(a) — \(h)"
    }

    private func kickoffLabel(for game: Game) -> String {
        guard let d = game.standardDate else { return "TBD" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if let game = selectedGame {
            // Build minimal team wrappers so ModernGameDetailView can render.
            let home = Team(strTeam: game.strHomeTeam)
            let away = Team(strTeam: game.strAwayTeam)
            ModernGameDetailView(game: game, homeTeam: home, awayTeam: away)
                .environment(viewModel)
                .environment(favorites)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 540)
        } else {
            VStack(spacing: .appSpace3) {
                Image(systemName: "rectangle.righthalf.inset.filled.arrow.right")
                    .font(.system(size: 40, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.appInkSoft)
                Text("Pick a game")
                    .font(.appHeadline)
                Text("Tap any tile in the middle column to see scores, plays, leaders, and context here.")
                    .font(.appCallout)
                    .foregroundStyle(Color.appInkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .padding(.appSpace5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 540)
        }
    }
}

/// Plain black-on-white schedule used only for printing (⌘P / File → Print).
private struct SchedulePrintView: View {
    let title: String
    let games: [Game]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scoreline")
                .font(.title.bold())
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)
            Divider()
            if games.isEmpty {
                Text("No games scheduled.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                ForEach(games, id: \.id) { game in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(game.standardDate?.formatted(date: .omitted, time: .shortened) ?? "—")
                            .frame(width: 80, alignment: .leading)
                            .monospacedDigit()
                        Text("\(game.strAwayTeam) @ \(game.strHomeTeam)")
                        Spacer(minLength: 0)
                        if let away = game.intAwayScore, let home = game.intHomeScore,
                           !away.isEmpty, !home.isEmpty {
                            Text("\(away)–\(home)")
                                .monospacedDigit()
                        }
                    }
                    .font(.body)
                }
            }
        }
        .padding(28)
        .frame(width: 540, alignment: .leading)
        .foregroundStyle(.black)
        .background(Color.white)
    }
}
#endif
