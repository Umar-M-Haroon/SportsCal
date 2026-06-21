//
//  UpsellCoordinator.swift
//  SportsCal
//
//  Central gatekeeper for contextual paywall prompts. Before this, the only
//  upsell paths were a feature-tap alert and explicit "Subscribe" buttons —
//  no timing, no frequency caps. This routes intent-ranked triggers through a
//  single throttle so we ask at high-intent moments without nagging (which, at
//  this app's scale, costs a review and word-of-mouth we can't spare).
//
//  Presentation is left to the caller via a `present` closure (some sites show
//  the RevenueCat paywall sheet, others a soft alert), so this stays free of
//  view state. The eligibility decision is a pure function (`UpsellPolicy`) for
//  unit-testing.
//

import Foundation

extension Notification.Name {
    /// Posted by deeply-nested call sites (e.g. the native ad card) that can't
    /// reach `sheetType` to ask ContentView to present the paywall. Used for
    /// *explicit* user upgrade taps, which are not throttled.
    static let requestPaywall = Notification.Name("requestPaywall")
}

/// A reason to consider showing a paywall, ranked by intent. Raw label is the
/// `trigger` field on `paywall_shown` telemetry.
enum UpsellTrigger: String {
    /// Right after onboarding completes — peak intent, the trial offer.
    case postOnboarding = "post_onboarding"
    /// User hit the free game-start reminder cap.
    case freeReminderCapHit = "free_reminder_cap"
    /// User opened a favorite team's game while it's live.
    case favoriteLiveGameOpened = "favorite_live_opened"
    /// Periodic re-ask for long-time free users.
    case nthSession = "nth_session"

    /// The post-onboarding trial offer is a one-time peak-intent moment, exempt
    /// from the day-cooldown (still bounded by the per-session cap).
    var respectsCooldown: Bool { self != .postOnboarding }
}

/// Pure throttle policy — no persistence, no UIKit.
enum UpsellPolicy {
    /// At most one hard paywall per app session.
    static let maxPerSession = 1
    /// Minimum days between contextual asks.
    static let cooldownDays: Double = 3

    static func shouldShow(
        trigger: UpsellTrigger,
        lastShownAt: Date?,
        sessionCount: Int,
        now: Date
    ) -> Bool {
        guard sessionCount < maxPerSession else { return false }
        if trigger.respectsCooldown, let last = lastShownAt {
            let days = now.timeIntervalSince(last) / 86_400
            guard days >= cooldownDays else { return false }
        }
        return true
    }
}

@Observable
final class UpsellCoordinator {
    static let shared = UpsellCoordinator()

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Resets each launch (in-memory) — enforces the per-session cap.
    @ObservationIgnored private var sessionCount = 0

    private init() {}

    private enum Keys {
        static let lastShown = "lastPaywallShownAt"
    }

    /// Consider showing a paywall for `trigger`. Returns true and invokes
    /// `present` iff the user is free, not suppressed, and within the throttle.
    /// Records the timestamp + emits `paywall_shown` telemetry as a side effect.
    ///
    /// - Parameter suppressed: pass true to skip even an eligible prompt (e.g. a
    ///   live match is on screen and we don't want to interrupt it).
    @discardableResult
    func request(
        _ trigger: UpsellTrigger,
        suppressed: Bool = false,
        now: Date = Date(),
        present: () -> Void
    ) -> Bool {
        // Never upsell existing subscribers.
        guard !SubscriptionManager.shared.isPro else { return false }
        guard !suppressed else { return false }

        let last = defaults.object(forKey: Keys.lastShown) as? Date
        guard UpsellPolicy.shouldShow(
            trigger: trigger,
            lastShownAt: last,
            sessionCount: sessionCount,
            now: now
        ) else {
            return false
        }

        sessionCount += 1
        defaults.set(now, forKey: Keys.lastShown)
        MonetizationTelemetry.paywallShown(trigger: trigger.rawValue)
        present()
        return true
    }
}
