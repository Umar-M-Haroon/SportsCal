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
    @ObservedObject var favorites = Favorites()
    var body: some Scene {
        WindowGroup {
//            OnboardingPage()
            ContentView()
                .environmentObject(SubscriptionManager.shared)
                .environmentObject(favorites)
        }
    }
}
