//
//  SportsCalWatchApp.swift
//  SportsCalWatch Watch App
//
//  Entry point for the Watch app.
//  Activates WatchConnectivity, injects WatchViewModel into environment.
//

import SwiftUI
import SportsCalModel

@main
struct SportsCalWatchApp: App {
    @State private var viewModel = WatchViewModel()

    init() {
        WatchSyncService.shared.activate()
        WatchSyncService.shared.onPreferencesUpdated = { [viewModel] in
            viewModel.loadPreferencesFromLocal()
            Task { await viewModel.fetchSchedule() }
        }
        CloudSyncManager.shared.startSync()
        CloudSyncManager.shared.onRemoteUpdate = { [viewModel] in
            viewModel.loadPreferencesFromLocal()
            Task { await viewModel.fetchSchedule() }
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(viewModel)
        }
    }
}
