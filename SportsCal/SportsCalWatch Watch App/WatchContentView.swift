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
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "watchOnboardingComplete")

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
        .overlay(alignment: .bottom) {
            WatchUpdateStatusView(
                failed: viewModel.lastFetchFailed,
                stale: viewModel.isStale,
                lastUpdated: viewModel.lastUpdated
            )
        }
        // One loop per active period: the first activation does the initial load (cache,
        // then one schedule fetch), later ones a throttled refresh. Leaving `.active`
        // cancels the loop, so nothing polls while the wrist is down or the app is
        // backgrounded.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await viewModel.becameActive()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(viewModel.pollInterval))
                guard !Task.isCancelled else { break }
                await viewModel.poll()
            }
        }
        .sheet(isPresented: $showOnboarding) {
            WatchOnboardingView(isPresented: $showOnboarding)
                .environment(viewModel)
        }
    }
}

/// Small "Couldn't update" / "Updated 3h ago" caption shown over the last good data.
private struct WatchUpdateStatusView: View {
    let failed: Bool
    let stale: Bool
    let lastUpdated: Date?

    var body: some View {
        if failed || stale {
            Label {
                Text(message)
            } icon: {
                Image(systemName: failed ? "exclamationmark.icloud" : "clock.arrow.circlepath")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
            .allowsHitTesting(false)
        }
    }

    private var message: String {
        let updated = lastUpdated.map { "Updated \($0.formatted(.relative(presentation: .named)))" }
        if failed {
            return updated.map { "Couldn't update · \($0)" } ?? "Couldn't update"
        }
        return updated ?? "Not updated"
    }
}

enum WatchTab {
    case liveNow, today, favorites, settings
}
