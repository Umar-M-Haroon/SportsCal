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
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

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
        // Activation funnel — each sent at most once per install, and only by
        // installs in a retention cohort (never by upgraded legacy installs).
        static let activationOnboardingStarted = "activation_onboarding_started"
        static let activationOnboardingCompleted = "activation_onboarding_completed"
        static let activationNotificationsGranted = "activation_notifications_granted"
        static let activationNotificationsDenied = "activation_notifications_denied"
        static let activationFirstReminderSet = "activation_first_reminder_set"
        static let activationFirstLiveActivity = "activation_first_live_activity"
        static let activationWidgetInstalled = "activation_widget_installed"
        static let activationFirstGameDetailOpened = "activation_first_game_detail_opened"
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
    ///
    /// Also carries the install's retention cohort (see `InstallCohort`):
    /// `install_day` for installs first seen on a cohort-aware build, or
    /// `cohort=legacy` for upgraded installs, which the server keeps out of
    /// every cohort.
    static func appActive() {
        let day = Int(Date().timeIntervalSince1970) / 86_400
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: lastActiveDayKey) != day else { return }
        defaults.set(day, forKey: lastActiveDayKey)
        send(Event.appActive, InstallCohort.appActiveFields(InstallCohort.current())) { delivered in
            guard !delivered else { return }
            if UserDefaults.standard.integer(forKey: MonetizationTelemetry.lastActiveDayKey) == day {
                UserDefaults.standard.removeObject(forKey: MonetizationTelemetry.lastActiveDayKey)
            }
        }
    }

    // MARK: - Install-once activation events

    /// Sends `event` at most once per install, claiming a UserDefaults flag up
    /// front and releasing it on a non-2xx (the same pattern `appActive` uses for
    /// its day). Skipped entirely for legacy installs: upgraded users completing
    /// their "first" anything months after installing would pollute the funnel.
    /// `key` overrides the flag name for events that predate this helper.
    static func recordOncePerInstall(_ event: String, _ fields: [String: String] = [:], key: String? = nil) {
        guard InstallCohort.current().isCohortMember else { return }
        let flag = key ?? "telemetry.once.\(event)"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)
        send(event, fields) { delivered in
            if !delivered { UserDefaults.standard.removeObject(forKey: flag) }
        }
    }

    /// Called on every foreground: picks up the notification decision (whichever
    /// prompt asked) and whether any widget is on the Home Screen. Both are
    /// install-once, so after the first hit these are just a flag check plus an
    /// async status read.
    static func observeForegroundActivation() {
        guard InstallCohort.current().isCohortMember else { return }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: notificationsResolvedKey) {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let status = settings.authorizationStatus
                guard let granted = ActivationSignals.notificationDecision(status) else { return }
                notificationsResolved(granted: granted)
            }
        }
        #if canImport(WidgetKit) && os(iOS)
        if !defaults.bool(forKey: "telemetry.once.\(Event.activationWidgetInstalled)") {
            WidgetCenter.shared.getCurrentConfigurations { result in
                guard case .success(let widgets) = result, !widgets.isEmpty else { return }
                recordOncePerInstall(Event.activationWidgetInstalled)
            }
        }
        #endif
    }

    /// One flag for both outcomes: the first decision observed wins.
    private static let notificationsResolvedKey = "telemetry.once.notifications_resolved"

    static func notificationsResolved(granted: Bool) {
        recordOncePerInstall(
            granted ? Event.activationNotificationsGranted : Event.activationNotificationsDenied,
            key: notificationsResolvedKey
        )
    }

    static func onboardingStarted() {
        recordOncePerInstall(Event.activationOnboardingStarted)
    }

    static func onboardingCompleted(sportCount: Int) {
        recordOncePerInstall(
            Event.activationOnboardingCompleted,
            ["sports": ActivationSignals.sportCountBucket(sportCount)]
        )
    }

    static func firstReminderSet() {
        recordOncePerInstall(Event.activationFirstReminderSet)
    }

    static func firstLiveActivity() {
        recordOncePerInstall(Event.activationFirstLiveActivity)
    }

    static func firstGameDetailOpened() {
        recordOncePerInstall(Event.activationFirstGameDetailOpened)
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

    /// Install-once; keeps the flag name it had before `recordOncePerInstall`
    /// existed so installs that already sent it don't send it again.
    static func activationFirstFavorite() {
        recordOncePerInstall(Event.activationFirstFavorite, key: "didEmitFirstFavorite")
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

// MARK: - Activation signals (pure)

/// Pure mappings the activation events report, kept separate so tests can pin
/// them. Bucket strings are allow-listed server-side (`breakoutValues["sports"]`),
/// so keep the two in sync.
enum ActivationSignals {
    /// Coarse selected-sport count for `activation_onboarding_completed`.
    static func sportCountBucket(_ count: Int) -> String {
        switch count {
        case ..<1: return "0"
        case 1: return "1"
        case 2: return "2"
        case 3...4: return "3-4"
        default: return "5+"
        }
    }

    /// nil while the user hasn't been asked yet; otherwise whether they allowed
    /// notifications (provisional/ephemeral count as allowed).
    static func notificationDecision(_ status: UNAuthorizationStatus) -> Bool? {
        switch status {
        case .notDetermined: return nil
        case .denied: return false
        case .authorized, .provisional: return true
        #if os(iOS)
        case .ephemeral: return true
        #endif
        @unknown default: return nil
        }
    }
}

// MARK: - Retention cohort

/// Which retention cohort this install belongs to, decided once, at the first
/// launch of a cohort-aware build, and persisted.
///
/// - `.member(installDay:)`: a fresh install. `installDay` is the UTC epoch day
///   of that first launch; every `app_active` carries it, so the server can file
///   the ping under `d1/d7/d14/d30` without storing anything per install.
/// - `.legacy`: an existing user upgrading. They were installed before we could
///   see it, so they're kept out of every cohort and the activation funnel.
///
/// Legacy is detected from state an earlier build already wrote: a non-zero
/// `launches` count (incremented on every launch for years, read here BEFORE
/// this launch's increment), onboarding marked done, a previous `app_active`, or
/// the old first-favorite flag. A reinstall wipes UserDefaults, so it starts a
/// new cohort entry, the way the App Store counts a re-download.
enum InstallCohort: Equatable {
    case member(installDay: Int)
    case legacy

    static let storageKey = "telemetry.installDay"
    /// Stored in place of a day for legacy installs.
    static let legacyMarker = -1

    var isCohortMember: Bool {
        if case .member = self { return true }
        return false
    }

    /// Pure decision. `stored` is the persisted value (nil the first time).
    static func resolve(
        stored: Int?,
        today: Int,
        priorLaunches: Int,
        onboardingCompleted: Bool,
        hasPriorTelemetry: Bool
    ) -> InstallCohort {
        if let stored {
            return stored >= 0 ? .member(installDay: stored) : .legacy
        }
        if priorLaunches > 0 || onboardingCompleted || hasPriorTelemetry {
            return .legacy
        }
        return .member(installDay: today)
    }

    var storedValue: Int {
        switch self {
        case .member(let day): return day
        case .legacy: return Self.legacyMarker
        }
    }

    /// Extra `app_active` fields for this cohort.
    static func appActiveFields(_ cohort: InstallCohort) -> [String: String] {
        switch cohort {
        case .member(let day): return ["install_day": String(day)]
        case .legacy: return ["cohort": "legacy"]
        }
    }

    /// Call from `App.init`, before anything bumps `launches` or shows
    /// onboarding. Idempotent: later calls just read the stored value.
    @discardableResult
    static func resolveAtLaunch(defaults: UserDefaults = .standard, now: Date = Date()) -> InstallCohort {
        let stored = defaults.object(forKey: storageKey) as? Int
        let onboardingDone = (defaults.object(forKey: "shouldShowOnboarding") as? Bool) == false
        let hasPriorTelemetry = defaults.object(forKey: "telemetry.appActive.lastEpochDay") != nil
            || defaults.bool(forKey: "didEmitFirstFavorite")
        let cohort = resolve(
            stored: stored,
            today: Int(now.timeIntervalSince1970) / 86_400,
            priorLaunches: defaults.integer(forKey: "launches"),
            onboardingCompleted: onboardingDone,
            hasPriorTelemetry: hasPriorTelemetry
        )
        if stored == nil { defaults.set(cohort.storedValue, forKey: storageKey) }
        return cohort
    }

    /// The persisted cohort. Resolves on first use if `resolveAtLaunch` hasn't
    /// run yet (it always has in the app; this keeps the call sites total).
    static func current() -> InstallCohort {
        resolveAtLaunch()
    }
}
