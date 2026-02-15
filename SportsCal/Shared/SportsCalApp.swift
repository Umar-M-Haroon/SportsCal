//
//  SportsCalApp.swift
//  Shared
//
//  Created by Umar Haroon on 7/2/21.
//

import SwiftUI
import os
//import Purchases
#if os(iOS)
import BackgroundTasks
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
    @State private var serverDiscovery = LocalServerDiscovery()
    @State private var viewModel: GameViewModel

    init() {
        let storage = UserDefaultStorage()
        let favs = Favorites()
        _appStorage = State(initialValue: storage)
        _favorites = State(initialValue: favs)
        _viewModel = State(initialValue: GameViewModel(appStorage: storage, favorites: favs))
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
//                .environmentObject(SubscriptionManager.shared)
                .environment(appStorage)
                .environment(favorites)
                .environment(viewModel)
                .onAppear {
                    appStorage.launches += 1
                    if isTestFlight {
                        appStorage.debugMode = true
                    }
                    if appStorage.debugMode {
                        serverDiscovery.start()
                    }
                }
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
                }
                .environment(serverDiscovery)
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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                #if os(iOS)
                scheduleAppRefresh()
                #endif
            }
        }
        #if os(iOS)
        .backgroundTaskIfAvailable()
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

#if os(iOS)
extension Scene {
    func backgroundTaskIfAvailable() -> some Scene {
        if #available(iOS 16.0, *) {
            return self.backgroundTask(.appRefresh("com.KomodoLLC.SportsCal.updateGamesAndActivities")) {
                AppLogger.general.info("Running background task")
                if #available(iOS 16.1, *) {
#if canImport(ActivityKit) && os(iOS)
                    for activity in Activity<LiveSportActivityAttributes>.activities {
                        for await data in activity.pushTokenUpdates {
                            let myToken = data.map { String(format: "%02x", $0)}.joined()
                            AppLogger.liveActivity.info("Live activity token updated: \(myToken)")
                            do {
                                try await NetworkHandler.subscribeToLiveActivityUpdate(token: myToken, eventID: activity.attributes.eventID)
                            } catch {
                                AppLogger.liveActivity.error("Error updating on background: \(error.localizedDescription)")
                            }
                        }
                    }
#endif
                }
            }
        } else {
            return self
        }
    }
}
#endif
