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
        // Touch TeamsManager.shared first so its disk-cached teams are loaded
        // before Favorites' init runs — that lets the legacy-shape migration
        // resolve as many name → ID entries as possible on the spot.
        _ = TeamsManager.shared
        let storage = UserDefaultStorage()
        let favs = Favorites()
        let tracker = EngagementTracker()
        _appStorage = State(initialValue: storage)
        _favorites = State(initialValue: favs)
        _engagementTracker = State(initialValue: tracker)
        #if canImport(ActivityKit) && os(iOS)
        // One-shot purge of polluted App Group badge files from the
        // alternate-name caching era. Must run before the view model
        // starts caching badges so the new canonical-name files write cleanly.
        GameViewModel.purgeStaleAppGroupBadgesIfNeeded()
        #endif
        let vm = GameViewModel(appStorage: storage, favorites: favs)
        vm.engagementTracker = tracker
        _viewModel = State(initialValue: vm)
        #if canImport(ActivityKit) && os(iOS)
        // Subscribe to Activity<>.activityUpdates BEFORE iOS gets a chance to
        // create a push-to-start activity in the background-launch case. Apple's
        // docs are explicit: the system wakes our process when a push-to-start
        // arrives so we can request the per-activity push token; if we wire the
        // listener only from a foreground-only path (`getInfo()`), the wake
        // window passes without us POSTing the token and the activity sits at
        // its initial state with no updates until the user opens the app.
        vm.startActivityUpdatesListener()
        #endif
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
                    TeamsManager.shared.refreshIfStale()
                    if isTestFlight {
                        appStorage.debugMode = true
                    }
                    if appStorage.debugMode {
                        serverDiscovery.start()
                    }
                    #if os(iOS)
                    if !subscriptionManager.isPro && AdConfiguration.isEnabled {
                        // Defer ad preloading off the launch-critical window. Each
                        // native ad warms a GoogleMobileAds WKWebView (its own
                        // WebContent/GPU/Networking helper processes); kicking off
                        // a batch during the first frames is the dominant launch
                        // jank. Wait for the UI to settle, then warm a small batch —
                        // the feed's own `refreshOnAppear(target:)` tops it up later.
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            adManager.preloadAds(count: 2)
                        }
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
                .environment(subscriptionManager)
        }
        #endif
    }

    #if os(iOS)
    nonisolated static let backgroundRefreshIdentifier = "com.KomodoLLC.SportsCal.updateGamesAndActivities"

    /// Submit a BGAppRefreshTaskRequest. iOS treats `earliestBeginDate` as a hint —
    /// the actual run depends on user activity, charging, and budget, but giving a
    /// 4-hour floor avoids burning the system's quota on requests we don't need that
    /// soon. Static + nonisolated so the .backgroundTask handler can re-queue itself
    /// without hopping back to the main actor (BGTaskScheduler is thread-safe).
    nonisolated static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            AppLogger.general.info("Background refresh scheduled for ≥ \(request.earliestBeginDate?.formatted() ?? "?")")
        } catch BGTaskScheduler.Error.unavailable {
            // Simulator and Mac Catalyst don't support BGTaskScheduler — log once and move on.
            AppLogger.general.notice("Background refresh unavailable in this environment")
        } catch {
            AppLogger.general.error("Background refresh scheduling failed: \(error.localizedDescription)")
        }
    }

    func scheduleAppRefresh() { Self.scheduleAppRefresh() }
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
        self.backgroundTask(.appRefresh(SportsCalApp.backgroundRefreshIdentifier)) {
            AppLogger.general.info("Running background task")

            // Always queue the next refresh first — if the body crashes or times out,
            // we still want the chain to continue.
            SportsCalApp.scheduleAppRefresh()

            // Refresh schedule + teams disk caches so the next cold launch shows fresh
            // games on the first frame, without the user waiting on the network.
            await GameViewModel.refreshCachesInBackground()

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
