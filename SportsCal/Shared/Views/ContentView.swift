//
//  ContentView.swift
//  Shared
//
//  Created by Umar Haroon on 7/2/21.
//

import SwiftUI
import Combine
#if os(iOS)
import EventKit
import CoreSpotlight
#endif
import WidgetKit
import StoreKit
import SportsCalModel
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

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.requestReview) private var requestReview

    @State var shouldShowSettings: Bool = false

    @State private var sheetType: SheetType? = nil

    @State var shouldShowSportsCalProAlert: Bool = false

    @State var teamString: String? = ""

    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites

    @Environment(GameViewModel.self) private var viewModel

    @State var calendarShowFavoritesOnly: Bool = false
    @State private var selectedTab: Int = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DayPage(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert)
                    .environment(viewModel)
                    .environment(storage)
                    .environment(favorites)
                    .navigationTitle("SportsCal")
                    .toolbar { settingsToolbarItem }
            }
            .tabItem {
                Label("Games", systemImage: "sportscourt")
            }
            .tag(0)

            #if os(iOS)
            NavigationStack {
                CalendarPage(sheetType: $sheetType, showFavoritesOnly: $calendarShowFavoritesOnly)
                    .environment(viewModel)
                    .environment(favorites)
                    .environment(storage)
                    .navigationTitle("SportsCal")
                    .toolbar {
                        settingsToolbarItem
                        ToolbarItem {
                            Button {
                                calendarShowFavoritesOnly.toggle()
                            } label: {
                                Image(systemName: calendarShowFavoritesOnly ? "star.fill" : "star")
                                    .foregroundColor(calendarShowFavoritesOnly ? .yellow : .gray)
                            }
                        }
                    }
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }
            .tag(1)
            #endif

            NavigationStack {
                BrowsePage()
                    .environment(viewModel)
                    .environment(storage)
                    .environment(favorites)
                    .navigationTitle("SportsCal")
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
        .refreshable(action: {
            viewModel.getInfo()
        })
        .alert(isPresented: $shouldShowSportsCalProAlert, content: {
            Alert(title: Text("SportsCal Pro"), message: Text("This feature requires SportsCal Pro"))
        })
        .sheet(item: $sheetType) { sheetType in
            switch sheetType {
            case .settings:
                SettingsView(sheetType: $sheetType)
                    .environment(storage)
                    .environment(viewModel)
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
                NavigationView {
                                Text("Cancel")
                }
            }
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

    // MARK: - Deep Link Handling

    /// Handles Spotlight search result taps.
    private func handleSpotlightActivity(_ activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }

        if identifier.hasPrefix("game-") {
            // Navigate to Games tab — the game will be visible in the list
            selectedTab = 0
        } else if identifier.hasPrefix("team-") {
            // Navigate to Games tab with favorites context
            selectedTab = 0
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(UserDefaultStorage())
            .environment(Favorites())
            .environment(GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites()))
        //            .environment(\.sizeCategory, .accessibilityLarge)
    }
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
