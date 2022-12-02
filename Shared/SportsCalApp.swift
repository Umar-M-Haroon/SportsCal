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
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: GameViewModel(appStorage: appStorage, favorites: favorites))
                .environmentObject(SubscriptionManager.shared)
                .environmentObject(appStorage)
                .environmentObject(favorites)
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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 0)
        try? BGTaskScheduler.shared.submit(request)
        print("test")
    }
}
extension Scene {
    func backgroundTaskIfAvailable() -> some Scene {
        if #available(iOS 16.0, *) {
            return self.backgroundTask(.appRefresh("com.KomodoLLC.SportsCal.updateGamesAndActivities")) {
                let _ = try? await NetworkHandler.testCall()
                if #available(iOS 16.1, *) {
#if canImport(ActivityKit)
                    for activity in Activity<LiveSportActivityAttributes>.activities {
                        for await data in activity.pushTokenUpdates {
                            let myToken = data.map { String(format: "%02x", $0)}.joined()
                            print("live activity updated", myToken)
                            try? await NetworkHandler.subscribeToLiveActivityUpdate(token: myToken, eventID: activity.attributes.eventID)
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
