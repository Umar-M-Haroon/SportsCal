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
    case games
    case sport(SportType)
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

    #if os(macOS)
    @State private var sidebarSelection: MacSidebarItem? = .games
    #endif

    var body: some View {
        mainNavigation
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
            .onChange(of: storage.debugMode) { _, _ in
                viewModel.updateLiveData()
            }
            .onAppear {
                WidgetCenter.shared.reloadAllTimelines()
                if viewModel.appStorage.launches == 5 {
                    requestReview()
                }
                if viewModel.appStorage.shouldShowOnboarding {
                    sheetType = .onboarding
                }
                // Check if launched via OpenSportIntent
                checkIntentOpenSport()
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
        NavigationSplitView {
            macSidebar
        } detail: {
            macDetail
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
                        EFRemixDayPage()
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

            NavigationStack {
                Group {
                    switch storage.appTheme {
                    case .ambient:
                        AmbientBrowsePage()
                            .environment(viewModel)
                            .environment(storage)
                            .environment(favorites)
                    case .efRemix:
                        EFRemixBrowsePage()
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
            Label("Games", systemImage: "sportscourt")
                .tag(MacSidebarItem.games)

            Section("Sports") {
                ForEach(storage.enabledSports, id: \.self) { sport in
                    sidebarSportRow(sport)
                        .tag(MacSidebarItem.sport(sport))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Scoreline")
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    }

    private func sidebarSportRow(_ sport: SportType) -> some View {
        HStack {
            Label {
                Text(sport.displayName)
            } icon: {
                Image(systemName: sport.systemImage)
                    .foregroundStyle(sport.color)
            }
            Spacer()
            if let count = viewModel.liveGameCountsBySport[sport], count > 0 {
                Text("\(count) live")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var macDetail: some View {
        switch sidebarSelection {
        case .games, .none:
            NavigationStack {
                DayPage(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, spotlightGameID: $spotlightGameID)
                    .environment(viewModel)
                    .environment(storage)
                    .environment(favorites)
                    .navigationTitle("Games")
            }
        case .sport(let sport):
            NavigationStack {
                BrowseSportView(sport: sport)
                    .environment(viewModel)
                    .environment(storage)
                    .environment(favorites)
            }
            .id(sport)
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
            calendarShowFavoritesOnly = true
            selectedTab = 0
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
