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
    static var strategy: PlacementStrategy = .everyNGames(n: 5)

    /// Maximum number of ads shown on a single screen/list
    static var maxAdsPerScreen: Int = 3

    /// Kill switch to disable all ads without a code change
    static var isEnabled: Bool = true

    /// Returns an adaptive ad interval based on the number of games in a list.
    /// Fewer games → more frequent ads so users with fewer sports still see ads.
    static func adaptiveInterval(forGameCount totalGames: Int) -> Int {
        if totalGames < 6 { return 3 }
        else if totalGames < 12 { return 4 }
        else { return 7 }
    }
}
#endif
