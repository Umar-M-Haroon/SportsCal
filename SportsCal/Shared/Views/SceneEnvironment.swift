//
//  SceneEnvironment.swift
//  SportsCal
//
//  Per-window plumbing. The app supports multiple scenes (iPad, Mac, and iPhone
//  Duo Split View), so anything that used to assume "the one window" lives here:
//  scene-local actions, and guards for work that should run once per launch.
//

import SwiftUI

// MARK: - Scene-local paywall

/// Presents the paywall in the window the request came from. Deeply nested views
/// (the native ad card) call this instead of posting a notification, which every
/// open window would answer with its own paywall.
struct RequestPaywallAction {
    var action: () -> Void = {}
    func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var requestPaywall = RequestPaywallAction()
}

// MARK: - Once per launch

/// Work that belongs to the app launch rather than to each window: the launch
/// counter, What's New, onboarding and the rating prompt. A second window (Split
/// View, a popped-out game) must not repeat it.
@MainActor
enum LaunchOnce {
    private static var done: Set<String> = []

    /// Runs `body` the first time `key` is seen this process; later calls no-op.
    static func run(_ key: String, _ body: () -> Void) {
        guard done.insert(key).inserted else { return }
        body()
    }
}

// MARK: - App-wide events

/// App-wide notifications (a tapped push, a Spotlight hand-off) reach every open
/// window. The first window to claim an event handles it; the rest ignore it.
@MainActor
enum SceneEventClaim {
    private static var claimed: Set<String> = []

    /// True for exactly one caller per `token`.
    static func claim(_ token: String) -> Bool {
        claimed.insert(token).inserted
    }
}
