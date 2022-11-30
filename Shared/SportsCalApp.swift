//
//  SportsCalApp.swift
//  Shared
//
//  Created by Umar Haroon on 7/2/21.
//

import SwiftUI
import Purchases
@main
struct SportsCalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject var appStorage = UserDefaultStorage()
    @StateObject var favorites = Favorites()
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: GameViewModel(appStorage: appStorage, favorites: favorites))
                .environmentObject(SubscriptionManager.shared)
                .environmentObject(appStorage)
                .environmentObject(favorites)
        }
    }
}
