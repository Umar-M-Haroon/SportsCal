//
//  RatingsManager.swift
//  SportsCal
//
//  App Store rating-prompt gating. Replaces the old one-shot prompt that fired
//  unconditionally at launch #5 with an engagement-gated, throttled prompt. At
//  the app's small review count, moving from a handful of reviews to dozens
//  during a tentpole (the World Cup) compounds both ranking and conversion — but
//  only if we ask engaged users at a good moment and never nag.
//
//  The eligibility decision is a pure function (`RatingsPolicy`) so it's
//  unit-testable; the local XCTest host can't launch.
//

import Foundation

/// Pure eligibility policy — no persistence, no UIKit.
enum RatingsPolicy {
    /// Don't ask brand-new users; let the habit form first.
    static let minLaunches = 5
    /// Apple hard-caps the system prompt at 3/365 days; mirror it so our own
    /// gate never wastes a precious prompt that iOS would silently swallow.
    static let maxPromptsPerYear = 3
    /// Space repeat asks far apart.
    static let minDaysBetweenPrompts: Double = 30

    static func eligible(
        launches: Int,
        hasPositiveSignal: Bool,
        promptCount: Int,
        lastPromptDate: Date?,
        now: Date
    ) -> Bool {
        guard hasPositiveSignal else { return false }
        guard launches >= minLaunches else { return false }
        guard promptCount < maxPromptsPerYear else { return false }
        if let last = lastPromptDate {
            let days = now.timeIntervalSince(last) / 86_400
            guard days >= minDaysBetweenPrompts else { return false }
        }
        return true
    }
}

@Observable
final class RatingsManager {
    static let shared = RatingsManager()

    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {}

    private enum Keys {
        static let count = "reviewPromptCount"
        static let year = "reviewPromptYear"
        static let lastDate = "lastReviewPromptDate"
    }

    /// Decide whether to invoke the SwiftUI `requestReview` action now. The
    /// `hasPositiveSignal` flag is the "engaged user / happy moment" gate — today
    /// that's "has at least one favorite" (a returning, invested user); a future
    /// refinement is "a favorite team just won". On a `true` return this records
    /// the prompt (count + timestamp) and emits `rating_prompt_shown` telemetry,
    /// so the caller must actually show the prompt.
    func shouldRequestReview(launches: Int, hasPositiveSignal: Bool, now: Date = Date()) -> Bool {
        // Reset the per-year counter when the calendar year rolls over (an
        // approximation of Apple's rolling 365-day window — simpler, and erring
        // toward asking slightly less).
        let year = Calendar.current.component(.year, from: now)
        if defaults.integer(forKey: Keys.year) != year {
            defaults.set(year, forKey: Keys.year)
            defaults.set(0, forKey: Keys.count)
        }

        let count = defaults.integer(forKey: Keys.count)
        let last = defaults.object(forKey: Keys.lastDate) as? Date
        guard RatingsPolicy.eligible(
            launches: launches,
            hasPositiveSignal: hasPositiveSignal,
            promptCount: count,
            lastPromptDate: last,
            now: now
        ) else {
            return false
        }

        defaults.set(count + 1, forKey: Keys.count)
        defaults.set(now, forKey: Keys.lastDate)
        MonetizationTelemetry.ratingPromptShown()
        return true
    }
}
