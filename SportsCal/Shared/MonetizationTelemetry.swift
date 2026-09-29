//
//  MonetizationTelemetry.swift
//  SportsCal
//
//  Fire-and-forget client telemetry for the monetization + activation funnel.
//  Each event is (a) POSTed to the server's /v2025/telemetry ingestion route,
//  which feeds the existing Redis per-day counters (admin-viewable) and
//  structured logs, and (b) dropped as a Sentry breadcrumb so the same events
//  are queryable when debugging a single session. Never throws, never blocks UI.
//
//  At the app's current scale there's no A/B statistical power — this exists so
//  we can see WHICH gate/trigger converts, not to run experiments.
//
//  Every event carries `channel` (debug / testflight / appstore), `platform`
//  (ios / macos) and `build` (CFBundleVersion) so the server can segregate the
//  developer's own builds from real users. `app_active` (once per UTC day per
//  install) is the denominator: the server folds the install ID into a
//  per-day HyperLogLog, giving DAU/WAU/MAU without storing IDs. Only the main
//  app target compiles this file, so widgets/watch never inflate DAU.
//

import Foundation
import StoreKit
import Sentry

enum MonetizationTelemetry {

    /// Stable event names. The server namespaces these as `client.<event>` and
    /// uses them as the Redis counter suffix, so DO NOT rename without updating
    /// any saved admin queries.
    enum Event {
        static let paywallShown = "paywall_shown"
        static let paywallDismissed = "paywall_dismissed"
        static let purchaseCompleted = "purchase_completed"
        static let trialStarted = "trial_started"
        static let gateHit = "gate_hit"
        static let ratingPromptShown = "rating_prompt_shown"
        static let adUpsellTapped = "ad_upsell_tapped"
        static let activationFirstFavorite = "activation_first_favorite"
        static let activationNotificationsEnabled = "activation_notifications_enabled"
        static let whatsNewShown = "whats_new_shown"
        static let whatsNewAction = "whats_new_action"
        static let appActive = "app_active"
    }

    /// Core emit. Safe to call from any thread; the network send is detached and
    /// failures are swallowed (telemetry must never break a flow).
    static func record(_ event: String, _ fields: [String: String] = [:]) {
        send(event, fields, completion: nil)
    }

    /// `record` with a delivery callback (true iff the server answered 2xx), so
    /// `appActive` only burns its once-a-day slot on a delivered ping.
    private static func send(
        _ event: String,
        _ fields: [String: String],
        completion: (@Sendable (Bool) -> Void)?
    ) {
        // Sentry breadcrumb — client-side, per-session queryable.
        let crumb = Breadcrumb(level: .info, category: "monetization")
        crumb.message = event
        crumb.data = fields as [String: Any]
        SentrySDK.addBreadcrumb(crumb)

        // Fire-and-forget POST to the server ingestion route. Detached because
        // resolving the channel may await StoreKit's AppTransaction (once).
        guard let url = URL(string: "\(NetworkHandler.baseURL())/telemetry") else {
            completion?(false)
            return
        }
        let installID = InstallID.current()
        Task.detached(priority: .utility) {
            var tagged = fields
            tagged["channel"] = await Channel.current()
            tagged["platform"] = MonetizationTelemetry.platform
            tagged["build"] = MonetizationTelemetry.build
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(Constants.apiKey, forHTTPHeaderField: "X-API-Key")
            request.setValue(installID, forHTTPHeaderField: "X-Install-ID")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = ["event": event, "fields": tagged]
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
                completion?(false)
                return
            }
            request.httpBody = body
            URLSession.shared.dataTask(with: request) { _, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                completion?(error == nil && (200..<300).contains(status))
            }.resume()
        }
    }

    // MARK: - Channel / platform tagging

    static let platform: String = {
        #if os(macOS)
        return "macos"
        #else
        return "ios"
        #endif
    }()

    static let build: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

    /// Which distribution channel this binary came from. DEBUG is decided at
    /// compile time; otherwise StoreKit's `AppTransaction.environment` is the
    /// one signal that works on both iOS and macOS (the `sandboxReceipt` path
    /// trick is iOS-only — a Mac TestFlight build's receipt is just `receipt`).
    /// Resolved once per process and cached.
    actor Channel {
        private static let shared = Channel()
        private var cached: String?

        static func current() async -> String {
            await shared.resolve()
        }

        private func resolve() async -> String {
            if let cached { return cached }
            let value = await Self.detect()
            cached = value
            return value
        }

        private static func detect() async -> String {
            #if DEBUG
            return "debug"
            #else
            guard let result = try? await AppTransaction.shared else { return "unknown" }
            let environment: AppStore.Environment
            switch result {
            case .verified(let transaction), .unverified(let transaction, _):
                environment = transaction.environment
            }
            switch environment {
            case .production: return "appstore"
            case .sandbox: return "testflight"
            case .xcode: return "debug"
            default: return "unknown"
            }
            #endif
        }
    }

    // MARK: - Active users

    private static let lastActiveDayKey = "telemetry.appActive.lastEpochDay"

    /// The DAU denominator. Sent at most once per UTC epoch day per install —
    /// UTC to match the server's day buckets, so a late-evening open in the
    /// Americas still counts toward the next server day. The day is claimed up
    /// front (so a burst of scene activations sends once) and released on
    /// failure so the next foreground retries.
    static func appActive() {
        let day = Int(Date().timeIntervalSince1970) / 86_400
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: lastActiveDayKey) != day else { return }
        defaults.set(day, forKey: lastActiveDayKey)
        send(Event.appActive, [:]) { delivered in
            guard !delivered else { return }
            if UserDefaults.standard.integer(forKey: MonetizationTelemetry.lastActiveDayKey) == day {
                UserDefaults.standard.removeObject(forKey: MonetizationTelemetry.lastActiveDayKey)
            }
        }
    }

    // MARK: - Typed conveniences

    static func paywallShown(trigger: String) {
        record(Event.paywallShown, ["trigger": trigger])
    }

    static func paywallDismissed() {
        record(Event.paywallDismissed)
    }

    static func gateHit(_ feature: ProFeature) {
        record(Event.gateHit, ["feature": feature.rawValue])
    }

    /// Pro became active. RevenueCat doesn't cleanly tell us "trial vs paid" at
    /// this layer, so callers pass whether the active entitlement is in its
    /// introductory/trial period.
    static func purchaseCompleted(isTrial: Bool) {
        record(isTrial ? Event.trialStarted : Event.purchaseCompleted)
    }

    static func ratingPromptShown() {
        record(Event.ratingPromptShown)
    }

    static func adUpsellTapped() {
        record(Event.adUpsellTapped)
    }

    static func activationFirstFavorite() {
        record(Event.activationFirstFavorite)
    }

    static func activationNotificationsEnabled() {
        record(Event.activationNotificationsEnabled)
    }

    static func whatsNewShown(version: String) {
        record(Event.whatsNewShown, ["version": version])
    }

    /// A CTA tapped on the What's New sheet, e.g. `competition:A-League`.
    static func whatsNewAction(_ action: String, version: String) {
        record(Event.whatsNewAction, ["action": action, "version": version])
    }
}
