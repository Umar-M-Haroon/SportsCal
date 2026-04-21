//
//  AdInsertionHelper.swift
//  SportsCal
//
//  Created by Umar Haroon on 2026-04-08.
//

#if os(iOS)
import Foundation

struct AdInsertionHelper {
    /// For the "everyNGames" strategy, returns the slot indices where an ad should appear
    /// within a flat list of games.
    /// E.g., with every=5 and totalGames=12, returns [4, 9] (after 5th and 10th game).
    static func gameAdIndices(totalGames: Int, every n: Int, maxAds: Int) -> [Int] {
        guard n > 0, totalGames > 0 else { return [] }
        var indices: [Int] = []
        var i = n - 1
        while i < totalGames && indices.count < maxAds {
            indices.append(i)
            i += n
        }
        return indices
    }

    /// For the "betweenSections" strategy, returns which section gaps should contain an ad.
    /// E.g., with 4 sections and maxAds=2, returns [1, 3] (after 2nd and 4th section).
    static func sectionAdSlots(sectionCount: Int, maxAds: Int) -> Set<Int> {
        guard sectionCount > 1, maxAds > 0 else { return [] }
        let interval = max(1, sectionCount / (maxAds + 1))
        var slots = Set<Int>()
        var i = interval - 1
        while i < sectionCount && slots.count < maxAds {
            slots.insert(i)
            i += interval
        }
        return slots
    }
}
#endif
