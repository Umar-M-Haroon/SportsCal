//
//  ProFeature.swift
//  SportsCal
//
//  Central definition of the free/Pro line. Previously the boundary was a
//  scattering of `subscriptionManager.isPro` checks across call sites; this
//  file makes the policy one place so it can be tuned (and tested) without
//  hunting through views.
//
//  Design notes:
//  - Most Pro features are a flat gate (`canUse`).
//  - Notifications are a *ladder*, not a wall: free users get game-start
//    reminders for their favorite teams (up to a small cap) so the core
//    habit forms before they hit a paywall. Advance (pre-game) reminders and
//    live score/goal alerts are the Pro upsell. See `NotificationGate`.
//

import Foundation

/// A capability that may be gated behind SportsCal Pro. Raw value doubles as a
/// stable analytics key for `gate_hit` telemetry.
public enum ProFeature: String, CaseIterable, Sendable {
    /// Ad-free experience.
    case adFree
    /// The "Pro options" settings section (hide events, countdowns, etc.).
    case proSettings
    /// Live score-change alerts + goal haptics (lock-screen alerting push).
    case goalAlerts
    /// Advance reminders (30 min / 1 hr / 2 hr before kickoff).
    case preGameReminders
    /// Game-start reminders beyond the free favorite-team allowance.
    case unlimitedReminders
    /// Export / sync games to Apple Calendar (the in-app calendar stays free).
    case calendarExport

    /// Human-facing feature name for paywall copy.
    public var displayName: String {
        switch self {
        case .adFree:             return "Ad-Free"
        case .proSettings:        return "Pro Settings"
        case .goalAlerts:         return "Goal & Score Alerts"
        case .preGameReminders:   return "Advance Reminders"
        case .unlimitedReminders: return "Unlimited Reminders"
        case .calendarExport:     return "Calendar Export"
        }
    }

    /// One-line benefit blurb for `PaywallGate` / contextual upsells.
    public var blurb: String {
        switch self {
        case .adFree:
            return "Remove ads across the app."
        case .proSettings:
            return "Fine-tune how games are shown and filtered."
        case .goalAlerts:
            return "Feel every goal — live score alerts on your lock screen."
        case .preGameReminders:
            return "Get reminded 30 minutes, an hour, or two hours before kickoff."
        case .unlimitedReminders:
            return "Set game-start reminders for every team you follow."
        case .calendarExport:
            return "Add games straight to your Apple Calendar."
        }
    }
}

public extension SubscriptionManager {
    /// Single source of truth for the flat Pro gates. Notification scheduling has
    /// a free allowance and uses `NotificationGate` instead of this.
    func canUse(_ feature: ProFeature) -> Bool {
        // Every listed feature is Pro-only today; the value of routing through
        // one method is that loosening/tightening (or A/B-ing) the line is a
        // one-line change here, not a sweep across views.
        return isPro
    }
}

/// The result of evaluating a gate: either allowed, or blocked with the specific
/// feature to upsell (so the paywall can show contextual copy + telemetry can
/// attribute the `gate_hit`).
public enum GateDecision: Equatable, Sendable {
    case allowed
    case requiresPro(ProFeature)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    public var blockedFeature: ProFeature? {
        if case .requiresPro(let f) = self { return f }
        return nil
    }
}

/// The kind of reminder being scheduled, for gating purposes.
public enum ReminderKind: Sendable {
    /// "When the game starts."
    case gameStart
    /// An advance reminder (30 min / 1 hr / 2 hr before).
    case preGame
}

/// Pure, synchronous policy for notification scheduling — the heart of the
/// free→Pro *ladder*. Kept free of UIKit / view state so it is trivially
/// testable in `ProFeatureGatingTests`.
public enum NotificationGate {
    /// How many distinct favorite teams a free user may set game-start reminders
    /// for. Tunable in one place — raise (or set very high) during big tentpole
    /// moments like the World Cup, lower for steady-state monetization.
    public static var freeFavoriteTeamLimit = 3

    /// Decide whether a reminder may be scheduled.
    ///
    /// - Parameters:
    ///   - isPro: current entitlement.
    ///   - kind: game-start vs advance reminder.
    ///   - gameInvolvesFavorite: whether the game features a favorited team.
    ///   - distinctFreeReminderTeams: how many distinct favorite teams the free
    ///     user has already used their game-start allowance on.
    ///   - teamAlreadyCounted: true when this game's favorite team is already in
    ///     the free allowance set (so scheduling another of its games is free).
    public static func decision(
        isPro: Bool,
        kind: ReminderKind,
        gameInvolvesFavorite: Bool,
        distinctFreeReminderTeams: Int,
        teamAlreadyCounted: Bool
    ) -> GateDecision {
        if isPro { return .allowed }

        switch kind {
        case .preGame:
            // Advance reminders are a Pro power-feature.
            return .requiresPro(.preGameReminders)

        case .gameStart:
            // Game-start reminders are the retention hook — free, but only for
            // teams you actually follow, and only up to the allowance.
            guard gameInvolvesFavorite else {
                return .requiresPro(.unlimitedReminders)
            }
            if teamAlreadyCounted { return .allowed }
            if distinctFreeReminderTeams < freeFavoriteTeamLimit { return .allowed }
            return .requiresPro(.unlimitedReminders)
        }
    }
}
