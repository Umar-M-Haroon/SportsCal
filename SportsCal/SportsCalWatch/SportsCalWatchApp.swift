//
//  SportsCalWatchApp.swift
//  SportsCalWatch
//
//  Apple Watch companion app for SportsCal.
//

import SwiftUI
import SportsCalModel

@main
struct SportsCalWatchApp: App {
    @State private var viewModel = WatchViewModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(viewModel)
        }
    }
}
