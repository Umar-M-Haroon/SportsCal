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
    /// Themes accent mirrored from the phone (see WatchSyncService); -1 = default.
    @AppStorage(AppAccentReader.effectiveHexKey) private var accentHex: Int = -1

    init() {
        WatchSyncService.shared.activate()
        WatchSyncService.shared.onPreferencesUpdated = { [viewModel] in
            viewModel.loadPreferencesFromLocal()
            Task { await viewModel.fetchSchedule(force: true) }
        }
        CloudSyncManager.shared.startSync()
        CloudSyncManager.shared.onRemoteUpdate = { [viewModel] in
            viewModel.loadPreferencesFromLocal()
            Task { await viewModel.fetchSchedule(force: true) }
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(viewModel)
                .tint(accentHex >= 0 ? Color(accentHex: accentHex) : nil)
        }
    }
}
