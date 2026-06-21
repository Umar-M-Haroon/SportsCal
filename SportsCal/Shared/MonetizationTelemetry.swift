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

import Foundation
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
    }

    /// Core emit. Safe to call from any thread; the network send is detached and
    /// failures are swallowed (telemetry must never break a flow).
    static func record(_ event: String, _ fields: [String: String] = [:]) {
        // Sentry breadcrumb — client-side, per-session queryable.
        let crumb = Breadcrumb(level: .info, category: "monetization")
        crumb.message = event
        crumb.data = fields as [String: Any]
        SentrySDK.addBreadcrumb(crumb)

        // Fire-and-forget POST to the server ingestion route.
        guard let url = URL(string: "\(NetworkHandler.baseURL())/telemetry") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Constants.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(InstallID.current(), forHTTPHeaderField: "X-Install-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["event": event, "fields": fields]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
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
}
