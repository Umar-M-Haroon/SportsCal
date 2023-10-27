//
//  SportsCalApp.swift
//  Shared
//
//  Created by Umar Haroon on 7/2/21.
//

import SwiftUI
import Purchases
import BackgroundTasks
#if canImport(ActivityKit)
import ActivityKit
#endif
@main
struct SportsCalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) var scenePhase

    @StateObject var appStorage = UserDefaultStorage()
    @StateObject var favorites = Favorites()
    var isTestFlight: Bool {
        guard let path = Bundle.main.appStoreReceiptURL?.path else {
            return false
        }
        return path.contains("sandboxReceipt")
    }
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: GameViewModel(appStorage: appStorage, favorites: favorites))
                .environmentObject(SubscriptionManager.shared)
                .environmentObject(appStorage)
                .environmentObject(favorites)
                .onAppear {
                    appStorage.launches += 1
                    if isTestFlight {
                        appStorage.debugMode = true
                    }
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                scheduleAppRefresh()
            }
        }
        .backgroundTaskIfAvailable()
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.KomodoLLC.SportsCal.updateGamesAndActivities")
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch let e {
            print(e)
            print(e.localizedDescription)
        }
    }
}
extension Scene {
    func backgroundTaskIfAvailable() -> some Scene {
        if #available(iOS 16.0, *) {
            return self.backgroundTask(.appRefresh("com.KomodoLLC.SportsCal.updateGamesAndActivities")) {
                print("Running background task")
                if #available(iOS 16.1, *) {
#if canImport(ActivityKit)
                    for activity in Activity<LiveSportActivityAttributes>.activities {
                        for await data in activity.pushTokenUpdates {
                            let myToken = data.map { String(format: "%02x", $0)}.joined()
                            print("live activity updated", myToken)
                            do {
                                try await NetworkHandler.subscribeToLiveActivityUpdate(token: myToken, eventID: activity.attributes.eventID, debug: UserDefaultStorage().debugMode)
                            } catch let err {
                                print("error updating on background", err.localizedDescription)
                                print(err)
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
