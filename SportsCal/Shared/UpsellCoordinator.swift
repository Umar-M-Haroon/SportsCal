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
    /// User tried to apply a theme (accent color or app icon) in Settings → Themes.
    case theme = "theme"
    /// User went past the free custom alert allowance (1 player with 1 rule) or
    /// tapped a locked Game Alerts situation.
    case customAlertCap = "custom_alert_cap"
    /// Tapped custom fantasy scoring or league import in the Fantasy hub.
    case fantasy = "fantasy"

    // Direct opens: the user went looking for Pro. No throttling applies.
    /// Settings → Scoreline Pro.
    case settings = "settings"
    /// Mac About panel / Settings → About.
    case about = "about"
    /// The Mac menu bar extra's "Subscribe…" (free users see no live scores there).
    case menuBar = "menu_bar"
    /// "Remove ads" on a native ad card.
    case adCard = "ad_card"
    /// A paywall opened without a known reason (a hub's Pro alert, older paths).
    case direct = "direct"

    /// The Pro feature the paywall should lead with for this trigger, if any.
    var featured: PaywallFeature? {
        switch self {
        case .theme: return .themes
        case .customAlertCap: return .customAlerts
        case .fantasy: return .fantasy
        case .freeReminderCapHit: return .reminders
        case .adCard: return .adFree
        case .menuBar: return .menuBar
        #if os(macOS)
        case .favoriteLiveGameOpened: return .menuBar
        #else
        case .favoriteLiveGameOpened: return .scoreAlerts
        #endif
        default: return nil
        }
    }

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
    /// Records the timestamp and hands the trigger to the paywall, which records
    /// `paywall_shown` when it appears.
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
        pendingTrigger = trigger
        present()
        return true
    }

    /// For an explicit tap on a Pro-only action (e.g. applying a theme): always
    /// presents for free users — throttling a direct request would read as a
    /// broken button — but still records `paywall_shown` with the trigger and
    /// counts toward the session cap so a contextual ask doesn't follow it.
    @discardableResult
    func requestExplicit(
        _ trigger: UpsellTrigger,
        now: Date = Date(),
        present: () -> Void
    ) -> Bool {
        guard !SubscriptionManager.shared.isPro else { return false }
        sessionCount += 1
        defaults.set(now, forKey: Keys.lastShown)
        pendingTrigger = trigger
        present()
        return true
    }

    // MARK: - Trigger hand-off to the paywall

    /// Why the next paywall is opening. The paywall takes it when it appears and
    /// records `paywall_shown` itself, so direct opens (Settings, the ad card, the
    /// Mac menu bar) are counted too, and it can lead with the matching feature.
    @ObservationIgnored private var pendingTrigger: UpsellTrigger?

    /// Tags a direct open (no throttling: the user asked for it).
    func noteDirectOpen(_ trigger: UpsellTrigger) {
        pendingTrigger = trigger
    }

    /// The trigger for the paywall that's appearing now; `.direct` if none was noted.
    func takePendingTrigger() -> UpsellTrigger {
        defer { pendingTrigger = nil }
        return pendingTrigger ?? .direct
    }
}
