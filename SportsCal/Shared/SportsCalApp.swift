//
//  SportsCalApp.swift
//  Shared
//
//  Created by Umar Haroon on 7/2/21.
//

import SwiftUI
import os
import TipKit
import RevenueCat
#if os(iOS)
import BackgroundTasks
import WatchConnectivity
#endif
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif
@main
struct SportsCalApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var versionChecker = APIVersionChecker.shared

    @State var appStorage = UserDefaultStorage()
    @State var favorites = Favorites()
    @State private var engagementTracker = EngagementTracker()
    @State private var serverDiscovery = LocalServerDiscovery()
    @State private var subscriptionManager = SubscriptionManager.shared
    #if os(iOS)
    @State private var adManager = NativeAdManager()
    #endif
    @State private var viewModel: GameViewModel

    init() {
        let storage = UserDefaultStorage()
        let favs = Favorites()
        let tracker = EngagementTracker()
        _appStorage = State(initialValue: storage)
        _favorites = State(initialValue: favs)
        _engagementTracker = State(initialValue: tracker)
        let vm = GameViewModel(appStorage: storage, favorites: favs)
        vm.engagementTracker = tracker
        _viewModel = State(initialValue: vm)
        try? Tips.configure()
        CloudSyncManager.shared.startSync(storage: storage, favorites: favs)
        SubscriptionManager.shared.configure()
        #if os(iOS)
        PhoneWatchSyncService.shared.activate()
        #endif
    }

    var isTestFlight: Bool {
        guard let path = Bundle.main.appStoreReceiptURL?.path else {
            return false
        }
        return path.contains("sandboxReceipt")
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(subscriptionManager)
                #if os(iOS)
                .environment(adManager)
                #endif
                .environment(appStorage)
                .environment(favorites)
                .environment(viewModel)
                .environment(engagementTracker)
                .onAppear {
                    appStorage.launches += 1
                    NetworkHandler.currentEnvironment = appStorage.serverEnvironment
                    Task { await NetworkHandler.refreshEnvironment() }
                    if isTestFlight {
                        appStorage.debugMode = true
                    }
                    if appStorage.debugMode {
                        serverDiscovery.start()
                    }
                    #if os(iOS)
                    if !subscriptionManager.isPro && AdConfiguration.isEnabled {
                        adManager.preloadAds(count: 5)
                    }
                    #endif
                }
                #if os(iOS)
                .onChange(of: subscriptionManager.isPro) { _, newValue in
                    if !newValue && AdConfiguration.isEnabled {
                        adManager.preloadAds(count: 5)
                    }
                }
                #endif
                .onChange(of: appStorage.debugMode) { _, newValue in
                    if newValue {
                        serverDiscovery.start()
                    } else {
                        serverDiscovery.stop()
                        NetworkHandler.localServerHost = nil
                    }
                }
                .onChange(of: serverDiscovery.discoveredHost) { _, newHost in
                    NetworkHandler.localServerHost = newHost
                    Task { await NetworkHandler.refreshEnvironment() }
                }
                .environment(serverDiscovery)
                .onReceive(NotificationCenter.default.publisher(for: .favoritesDidChange)) { _ in
                    #if os(iOS)
                    PhoneWatchSyncService.shared.syncAllPreferences()
                    let currentFavorites = favorites.teams
                    Task.detached(priority: .utility) {
                        SpotlightIndexer.indexFavoriteTeams(currentFavorites)
                    }
                    #endif
                }
                .onChange(of: appStorage.enabledSports) { _, _ in
                    #if os(iOS)
                    PhoneWatchSyncService.shared.syncAllPreferences()
                    #endif
                }
                .alert("Update Required", isPresented: $versionChecker.updateRequired) {
                    Button("Update Now") {
                        if let url = URL(string: "https://apps.apple.com/app/id1565214492") {
                            openURL(url)
                        }
                    }
                } message: {
                    if let minVersion = versionChecker.minAppVersion {
                        Text("Please update to version \(minVersion) or later to continue using SportsCal.")
                    } else {
                        Text("Please update to the latest version to continue using SportsCal.")
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    viewModel.getInfo()
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Jump to Today") {
                    NotificationCenter.default.post(name: .jumpToToday, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
        #endif
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                #if os(iOS)
                scheduleAppRefresh()
                #endif
            } else if newPhase == .active {
                // Foregrounding: kick the WebSocket back to life if it gave up while backgrounded,
                // and re-register Live Activity push tokens so the server's 12h TTL stays fresh
                // even when BGAppRefresh hasn't fired in a while.
                viewModel.ensureWebSocketConnected()
                #if canImport(ActivityKit) && os(iOS)
                viewModel.reRegisterAllActivityTokens()
                #endif
            }
        }
        #if os(iOS)
        .backgroundTaskIfAvailable()
        #endif

        #if os(macOS)
        MenuBarExtra {
            if subscriptionManager.isPro {
                MenuBarContentView()
                    .environment(appStorage)
                    .environment(favorites)
                    .environment(viewModel)
                    .environment(engagementTracker)
            } else {
                VStack(spacing: 12) {
                    Text("Scoreline Pro")
                        .font(.headline)
                    Text("Subscribe to Scoreline Pro to see live scores in your menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(width: 240)
            }
        } label: {
            MenuBarLabel(
                liveFavorites: subscriptionManager.isPro ? viewModel.liveEventsWithTeams.filter { favorites.contains($0.game) } : [],
                liveGames: subscriptionManager.isPro ? viewModel.liveEventsWithTeams : [],
                upcomingFavorite: subscriptionManager.isPro ? {
                    let liveIDs = Set(viewModel.liveEvents.map(\.id))
                    return viewModel.todayFavoriteGamesWithTeams.first { gwt in
                        guard let d = gwt.game.standardDate else { return false }
                        return d > Date() && !liveIDs.contains(gwt.game.id)
                    }
                }() : nil,
                liveCount: subscriptionManager.isPro ? viewModel.liveEvents.count : 0,
                todayCount: subscriptionManager.isPro ? viewModel.todayGames.count : 0,
                liveSports: subscriptionManager.isPro ? viewModel.currentlyLiveSports : []
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView()
                .environment(appStorage)
                .environment(favorites)
                .environment(viewModel)
                .environment(engagementTracker)
                .environment(serverDiscovery)
        }
        #endif
    }

    #if os(iOS)
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.KomodoLLC.SportsCal.updateGamesAndActivities")
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.general.error("Background task scheduling failed: \(error.localizedDescription)")
        }
    }
    #endif
}

#if os(macOS)
extension Notification.Name {
    static let jumpToToday = Notification.Name("com.scoreline.jumpToToday")
}
#endif

#if os(iOS)
extension Scene {
    func backgroundTaskIfAvailable() -> some Scene {
        self.backgroundTask(.appRefresh("com.KomodoLLC.SportsCal.updateGamesAndActivities")) {
            AppLogger.general.info("Running background task")
#if canImport(ActivityKit) && os(iOS)
            // Re-register current push tokens for all active Live Activities so the
            // server-side Redis TTL stays fresh while we're backgrounded.
            for activity in Activity<LiveSportActivityAttributes>.activities {
                if let tokenData = activity.pushToken {
                    let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
                    AppLogger.liveActivity.info("Background re-registering token for \(activity.attributes.eventID): \(tokenString.prefix(12))...")
                    do {
                        try await NetworkHandler.subscribeToLiveActivityUpdate(
                            token: tokenString,
                            eventID: activity.attributes.eventID,
                            homeTeam: activity.attributes.homeTeam,
                            awayTeam: activity.attributes.awayTeam
                        )
                    } catch {
                        AppLogger.liveActivity.error("Error updating on background: \(error.localizedDescription)")
                    }
                }
            }
#endif
        }
    }
}
#endif
