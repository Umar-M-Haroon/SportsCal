//
//  WatchContentView.swift
//  SportsCalWatch
//
//  Main tab navigation for the Watch app.
//

import SwiftUI
import SportsCalModel

struct WatchContentView: View {
    @Environment(WatchViewModel.self) private var viewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            if viewModel.hasLiveGames {
                LiveNowView()
                    .tag(WatchTab.liveNow)
            }
            TodayView()
                .tag(WatchTab.today)
            FavoritesView()
                .tag(WatchTab.favorites)
            WatchSettingsView()
                .tag(WatchTab.settings)
        }
        .tabViewStyle(.verticalPage)
        .task {
            await viewModel.initialLoad()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.refreshOnWake() }
            }
        }
        .onReceive(viewModel.pollTimer) { _ in
            guard scenePhase == .active else { return }
            Task { await viewModel.poll() }
        }
    }
}

enum WatchTab {
    case liveNow, today, favorites, settings
}
