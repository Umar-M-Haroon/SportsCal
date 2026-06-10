//
//  AdConfiguration.swift
//  SportsCal
//
//  Created by Umar Haroon on 2026-04-08.
//

import Foundation

#if os(iOS)
struct AdConfiguration {
    enum PlacementStrategy {
        /// Insert an ad after every `n` game rows within a section
        case everyNGames(n: Int)
        /// Insert an ad between sport sections
        case betweenSections
    }

    /// Current placement strategy — change this to tune ad frequency
    static var strategy: PlacementStrategy = .everyNGames(n: 9)

    /// Maximum number of ads shown across a single scrollable feed.
    /// Enforced globally per feed via `FeedAdPlanner` (not per-section), so this
    /// is a true ceiling on how many ads a user sees in one Games/Browse screen.
    static var maxAdsPerScreen: Int = 2

    /// Kill switch to disable all ads without a code change
    static var isEnabled: Bool = true

    /// Returns an adaptive ad interval based on the number of games in a list.
    /// Dialed back for v1 (C4): 1 ad per 8–10 games. Short lists show at most
    /// one ad late in the list; `FeedAdPlanner` skips lists under 8 rows entirely.
    static func adaptiveInterval(forGameCount totalGames: Int) -> Int {
        if totalGames < 12 { return 8 }
        else { return 10 }
    }
}
#endif
