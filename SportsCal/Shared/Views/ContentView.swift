//
//  ContentView.swift
//  Shared
//
//  Created by Umar Haroon on 7/2/21.
//

import SwiftUI
import CoreSpotlight
#if os(iOS)
import EventKit
#endif
import WidgetKit
import StoreKit
import SportsCalModel
import TipKit
import os
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

enum SheetType: Identifiable {
    var id: String {
        switch self {
        case .settings:
            return "settings"
        case .onboarding:
            return "onboarding"
        case .calendar(_):
            return "calendar"
        case .detail:
            return "detail"
        case .listDetail(games: _):
            return "listDetail"
        case .paywall:
            return "paywall"
        }
    }
    case settings, onboarding
    case calendar(game: Game?)
    case detail
    case listDetail(games: Array<(key: DateComponents, value: Array<Game>)>, liveGames: [Game])
    case paywall
}

#if os(macOS)
enum MacSidebarItem: Hashable {
    case games          // All Sports
    case liveNow
    case favorites
    case sport(SportType)
    case team(String)   // favorite team id
}

/// Small pulsing red dot signalling live activity (respects Reduce Motion).
struct LivePulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        Circle()
            .fill(Color.appLive)
            .frame(width: 7, height: 7)
            .scaleEffect(animating ? 1.0 : 0.6)
            .opacity(animating ? 1.0 : 0.45)
            .onAppear {
                guard !reduceMotion else { animating = true; return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    animating = true
                }
            }
            .accessibilityHidden(true)
    }
}
#endif

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.requestReview) private var requestReview

    @State var shouldShowSettings: Bool = false

    @State private var sheetType: SheetType? = nil

    @State var shouldShowSportsCalProAlert: Bool = false
    @State private var showPaywall: Bool = false

    @State var teamString: String? = ""

    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites

    @Environment(GameViewModel.self) private var viewModel

    @State var calendarShowFavoritesOnly: Bool = false
    @State private var selectedTab: Int = 0
    @State private var spotlightGameID: String?
    @State private var spotlightCalendarDate: Date?
    /// Typed nav path for the Browse stack so a Spotlight team tap can push TeamDetailView.
    @State private var browseTeamPath: [Team] = []

    #if os(macOS)
    @State private var sidebarSelection: MacSidebarItem? = .games
    #endif

    private var showStaleBanner: Bool {
        viewModel.showsStaleBanner
    }

    private var showOfflinePlaceholder: Bool {
        viewModel.showsOfflinePlaceholder
    }

    @ViewBuilder
    private var offlinePlaceholder: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: .appSpace4) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text("You're offline")
                    .font(.title3.weight(.semibold))
                Text("Connect to the internet to load games.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") { viewModel.getInfo() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.appSpace5)
        }
    }

    /// Relative "x min ago" label from the model's last-success timestamp.
    private var staleAgoLabel: String {
        guard let last = viewModel.lastSuccessfulFetch else { return "earlier" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: last, relativeTo: Date())
    }

    var body: some View {
        mainNavigation
            .safeAreaInset(edge: .top) {
                if showStaleBanner {
                    StaleDataBanner(
                        lastUpdatedAgo: staleAgoLabel,
                        isOffline: viewModel.isOffline,
                        retryAction: { viewModel.getInfo() }
                    )
                    .padding(.horizontal, .appSpace3)
                    .padding(.top, 4)
                    .background(Color.appBackground)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if storage.showGameCountHUD {
                    GameCountHUD()
                        .environment(viewModel)
                        .environment(storage)
                        .allowsHitTesting(true)
                }
            }
            .overlay {
                if showOfflinePlaceholder {
                    offlinePlaceholder
                        .transition(.opacity)
                }
            }
            .animation(.default, value: showOfflinePlaceholder)
            .refreshable(action: {
                viewModel.getInfo()
            })
            .alert("Scoreline Pro", isPresented: $shouldShowSportsCalProAlert) {
                Button("Subscribe") { sheetType = .paywall }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This feature requires Scoreline Pro")
            }
            .sheet(item: $sheetType) { sheetType in
                switch sheetType {
                case .settings:
                    #if os(iOS)
                    SettingsView(sheetType: $sheetType)
                        .environment(storage)
                        .environment(viewModel)
                    #else
                    EmptyView()
                    #endif
                case .onboarding:
                    OnboardingPage(sheetType: $sheetType)
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
                case .detail:
                    DetailView()
                case .listDetail(let listGames, let liveGames):
                    ListDetailView(listGames: listGames, liveGames: liveGames, sheetType: $sheetType)
                        .environment(storage)
                        .environment(viewModel)
                        .environment(favorites)
                        .presentationDetents([.medium, .large])
                case .paywall:
                    SubscriptionSheet(subscriptionPresented: $showPaywall)
                }
            }
            .onChange(of: showPaywall) { _, newValue in
                if !newValue { sheetType = nil }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    viewModel.getInfo()
                    viewModel.ensureWebSocketConnected()
                }
            }
            .onChange(of: storage.hiddenCompetitions) { _, _ in
                viewModel.filterSports()
            }
            .onChange(of: storage.shouldShowWorldCup) { _, _ in
                viewModel.filterSports(force: true)
                viewModel.reconcileWorldCupFollows()
            }
            .onReceive(NotificationCenter.default.publisher(for: CloudSyncManager.didApplyRemoteUpdateNotification)) { _ in
                viewModel.filterSports()
            }
            .onChange(of: storage.debugMode) { _, _ in
                viewModel.updateLiveData()
            }
            .onAppear {
                WidgetCenter.shared.reloadAllTimelines()
                // Engagement-gated, throttled rating prompt (replaces the old
                // unconditional launch-#5 ask). Positive signal = the user follows
                // at least one team (a returning, invested user).
                if RatingsManager.shared.shouldRequestReview(
                    launches: viewModel.appStorage.launches,
                    hasPositiveSignal: !favorites.teamIDs.isEmpty
                ) {
                    requestReview()
                }
                if viewModel.appStorage.shouldShowOnboarding {
                    sheetType = .onboarding
                }
                // Check if launched via OpenSportIntent
                checkIntentOpenSport()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestPaywall)) { _ in
                // Explicit upgrade tap from a deeply-nested surface (e.g. ad card).
                sheetType = .paywall
            }
            .onReceive(NotificationCenter.default.publisher(for: .favoritesDidChange)) { _ in
                // One-time activation signal — emitted here (app target) rather
                // than in Favorites, which also compiles into watch/widget where
                // the telemetry helper (and Sentry) aren't available.
                if !favorites.teamIDs.isEmpty,
                   !UserDefaults.standard.bool(forKey: "didEmitFirstFavorite") {
                    UserDefaults.standard.set(true, forKey: "didEmitFirstFavorite")
                    MonetizationTelemetry.activationFirstFavorite()
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            #if os(iOS)
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                handleSpotlightActivity(activity)
            }
            #endif
    }

    // MARK: - Platform Navigation

    @ViewBuilder
    private var mainNavigation: some View {
        #if os(macOS)
        Group {
            switch storage.appTheme {
            case .efRemix:
                ModernMacWindow()
                    .environment(viewModel)
                    .environment(storage)
                    .environment(favorites)
            case .ambient, .classic:
                NavigationSplitView {
                    macSidebar
                } detail: {
                    macDetail
                }
            }
        }
        #else
        TabView(selection: $selectedTab) {
            NavigationStack {
                Group {
                    switch storage.appTheme {
                    case .ambient:
                        AmbientDayPage()
                            .environment(viewModel)
                            .environment(storage)
                            .environment(favorites)
                    case .efRemix:
                        ModernDayPage()
                            .environment(viewModel)
                            .environment(storage)
                            .environment(favorites)
                    case .classic:
                        DayPage(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, spotlightGameID: $spotlightGameID)
                            .environment(viewModel)
                            .environment(storage)
                            .environment(favorites)
                    }
                }
                .navigationTitle("Scoreline")
                .toolbar { settingsToolbarItem }
                .navigationDestination(for: Team.self) { team in
                    TeamDetailView(team: team)
                        .environment(viewModel)
                        .environment(favorites)
                }
            }
            .tabItem {
                Label("Games", systemImage: "sportscourt")
            }
            .tag(0)

            #if os(iOS)
            NavigationStack {
                CalendarPage(sheetType: $sheetType, showFavoritesOnly: $calendarShowFavoritesOnly, spotlightDate: $spotlightCalendarDate)
                    .environment(viewModel)
                    .environment(favorites)
                    .environment(storage)
                    .navigationTitle("Scoreline")
                    .navigationDestination(for: Team.self) { team in
                        TeamDetailView(team: team)
                            .environment(viewModel)
                            .environment(favorites)
                    }
                    .toolbar {
                        settingsToolbarItem
                        ToolbarItem {
                            Button {
                                calendarShowFavoritesOnly.toggle()
                            } label: {
                                Image(systemName: calendarShowFavoritesOnly ? "star.fill" : "star")
                                    .foregroundColor(calendarShowFavoritesOnly ? .yellow : .gray)
                            }
                            .popoverTip(CalendarFavoritesTip())
                        }
                    }
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }
            .tag(1)
            #endif

            // Experimental — disabled. Re-enable to explore the timeline-style day view.
            // NavigationStack {
            //     DayTimelineView(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert)
            //         .environment(viewModel)
            //         .environment(storage)
            //         .environment(favorites)
            //         .navigationTitle("Timeline")
            //         .toolbar { settingsToolbarItem }
            // }
            // .tabItem {
            //     Label("Timeline", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            // }
            // .tag(3)

            NavigationStack(path: $browseTeamPath) {
                Group {
                    switch storage.appTheme {
                    case .ambient:
                        AmbientBrowsePage()
                            .environment(viewModel)
                            .environment(storage)
                            .environment(favorites)
                    case .efRemix:
                        ModernBrowsePage()
                            .environment(viewModel)
                            .environment(storage)
                            .environment(favorites)
                    case .classic:
                        BrowsePage()
                            .environment(viewModel)
                            .environment(storage)
                            .environment(favorites)
                    }
                }
                .navigationTitle("Scoreline")
                .toolbar { settingsToolbarItem }
                .navigationDestination(for: Team.self) { team in
                    TeamDetailView(team: team)
                        .environment(viewModel)
                        .environment(favorites)
                }
            }
            .tabItem {
                Label("Browse", systemImage: "rectangle.grid.2x2")
            }
            #if os(iOS)
            .tag(2)
            #else
            .tag(1)
            #endif
        }
        #endif
    }

    // MARK: - macOS Sidebar

    #if os(macOS)
    private var macSidebar: some View {
        List(selection: $sidebarSelection) {
            Section {
                Label("All Sports", systemImage: "sportscourt")
                    .tag(MacSidebarItem.games)
                sidebarScopeRow("Live Now", systemImage: "dot.radiowaves.left.and.right",
                                count: viewModel.liveEvents.count, isLive: true)
                    .tag(MacSidebarItem.liveNow)
                sidebarScopeRow("Favorites", systemImage: "star.fill",
                                count: favoritesTodayCount, tint: .yellow)
                    .tag(MacSidebarItem.favorites)
            }

            Section("Sports") {
                ForEach(storage.enabledSports, id: \.self) { sport in
                    sidebarSportRow(sport)
                        .tag(MacSidebarItem.sport(sport))
                }
            }

            Section("My Teams") {
                if sidebarFavoriteTeams.isEmpty {
                    favoritesNudge
                } else {
                    ForEach(sidebarFavoriteTeams, id: \.idTeam) { team in
                        if let id = team.idTeam {
                            sidebarTeamRow(team)
                                .tag(MacSidebarItem.team(id))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Scoreline")
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
    }

    private var favoritesTodayCount: Int {
        viewModel.gamesWithTeams(for: Date()).filter { favorites.contains($0.game) }.count
    }

    private var sidebarFavoriteTeams: [Team] {
        favorites.teamIDs
            .compactMap { TeamsManager.shared.team(byID: $0) }
            .sorted { ($0.strTeam ?? "") < ($1.strTeam ?? "") }
    }

    /// Shown in the "My Teams" section when the user follows no teams yet — a
    /// gentle prompt explaining how to populate it.
    private var favoritesNudge: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(.yellow)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text("Follow your teams")
                    .font(.subheadline.weight(.medium))
                Text("Tap the ☆ on any game to keep its team here for quick access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
    }

    private func sidebarScopeRow(_ title: String, systemImage: String, count: Int,
                                 isLive: Bool = false, tint: Color? = nil) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint ?? (isLive ? Color.appLive : Color.appInkSoft))
            }
            Spacer()
            if isLive, count > 0 {
                HStack(spacing: 4) {
                    LivePulseDot()
                    Text("\(count)")
                        .font(.appFootnote.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(Color.appLive)
            } else if count > 0 {
                Text("\(count)")
                    .font(.appFootnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sidebarTeamRow(_ team: Team) -> some View {
        let next = team.idTeam.flatMap { id in
            (viewModel.totalGames ?? [])
                .filter { $0.idHomeTeam == id || $0.idAwayTeam == id }
                .filter { ($0.standardDate ?? .distantPast) >= Calendar.current.date(byAdding: .hour, value: -4, to: Date())! }
                .min { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
        }
        return HStack(spacing: 8) {
            sidebarTeamBadge(team.strTeamBadge)
            VStack(alignment: .leading, spacing: 1) {
                Text(team.strTeam ?? "Team")
                    .lineLimit(1)
                if let next, let date = next.standardDate {
                    Text(Calendar.current.isDateInToday(date)
                         ? date.formatted(date: .omitted, time: .shortened)
                         : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.appFootnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func sidebarTeamBadge(_ badge: String?) -> some View {
        Group {
            if let badge, let url = URL(string: badge) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "shield.fill").foregroundStyle(.tertiary)
                }
            } else {
                Image(systemName: "shield.fill").foregroundStyle(.tertiary)
            }
        }
        .frame(width: 20, height: 20)
    }

    private func sidebarSportRow(_ sport: SportType) -> some View {
        HStack {
            Label {
                Text(sport.displayName)
            } icon: {
                Image(systemName: sport.systemImage)
                    .foregroundStyle(Color.app(sport))
            }
            Spacer()
            if let count = viewModel.liveGameCountsBySport[sport], count > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.appLive)
                        .frame(width: 5, height: 5)
                    Text("\(count) LIVE")
                        .font(.appFootnote)
                        .tracking(1)
                }
                .foregroundStyle(Color.appLive)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.appLive.opacity(0.12), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var macDetail: some View {
        // Every sidebar selection drives the day board, scoped by the chosen
        // filter (all / live / favorites / sport / team). The board itself is
        // the same DayPage; only its `macScope` changes.
        NavigationStack {
            DayPage(
                shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                spotlightGameID: $spotlightGameID,
                dayScope: dayScope(for: sidebarSelection ?? .games)
            )
            .environment(viewModel)
            .environment(storage)
            .environment(favorites)
            .navigationTitle(macDetailTitle)
        }
    }

    private func dayScope(for item: MacSidebarItem) -> DayScope {
        switch item {
        case .games:        return .all
        case .liveNow:      return .liveNow
        case .favorites:    return .favorites
        case .sport(let s): return .sport(s)
        case .team(let id): return .team(id)
        }
    }

    private var macDetailTitle: String {
        switch sidebarSelection ?? .games {
        case .games:        return "All Sports"
        case .liveNow:      return "Live Now"
        case .favorites:    return "Favorites"
        case .sport(let s): return s.displayName
        case .team(let id): return TeamsManager.shared.team(byID: id)?.strTeam ?? "Team"
        }
    }
    #endif

    // MARK: - Deep Link Handling

    /// Handles Spotlight search result taps.
    private func handleSpotlightActivity(_ activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }

        if identifier.hasPrefix("game-") {
            let eventID = String(identifier.dropFirst("game-".count))
            spotlightGameID = eventID
            selectedTab = 0
        } else if identifier.hasPrefix("team-") {
            let name = String(identifier.dropFirst("team-".count))
            if let team = TeamsManager.shared.team(byNameOrAlias: name) {
                browseTeamPath = [team]
                selectedTab = 2
            } else {
                // Team not in cache — fall back to the favorites-filtered games view.
                calendarShowFavoritesOnly = true
                selectedTab = 0
            }
        } else if identifier.hasPrefix("date-") {
            let dateString = String(identifier.dropFirst("date-".count))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dateString) {
                spotlightCalendarDate = date
                selectedTab = 1
            }
        }
    }

    /// Routes an incoming universal link (shared game / World Cup bracket). Reuses
    /// the same `spotlightGameID` deep-open mechanism Spotlight uses, so a shared
    /// game pushes its detail on the Games tab. The bracket route surfaces World
    /// Cup content (full hub-screen routing would need threading DayPage's
    /// `worldCupHubPresented` binding up to here).
    private func handleDeepLink(_ url: URL) {
        switch DeepLink.parse(url) {
        case .game(let idEvent):
            spotlightGameID = idEvent
            selectedTab = 0
        case .worldCupBracket:
            storage.shouldShowWorldCup = true
            storage.recomputeEnabledSports()
            viewModel.filterSports(force: true)
            selectedTab = 0
        case .none:
            break
        }
    }

    /// Checks if the app was opened via OpenSportIntent and switches to that sport.
    private func checkIntentOpenSport() {
        let defaults = UserDefaults(suiteName: "group.Komodo.SportsCal")
        guard let sportRaw = defaults?.string(forKey: "intentOpenSport") else { return }
        defaults?.removeObject(forKey: "intentOpenSport")

        if let sportType = SportType(rawValue: sportRaw) {
            storage.switchTo(sportType: sportType)
            viewModel.filterSports(force: true)
            selectedTab = 0
        }
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                shouldShowSettings = true
                sheetType = .settings
            } label: {
                Image(systemName: "gear")
            }
        }
    }
    #endif

    #if os(iOS)
    func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        AppLogger.calendar.info("Making calendar event for game \(game.strAwayTeam) @ \(game.strHomeTeam)")
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
    ContentView()
        .environment(UserDefaultStorage())
        .environment(Favorites())
        .environment(GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites()))
}
extension View {
    typealias ContentTransform<Content: View> = (Self) -> Content

    @ViewBuilder
    func conditionalModifier<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        ifTrue: ContentTransform<TrueContent>,
        ifFalse: ContentTransform<FalseContent>
    ) -> some View {
        if condition {
            ifTrue(self)
        } else {
            ifFalse(self)
        }
    }
}
