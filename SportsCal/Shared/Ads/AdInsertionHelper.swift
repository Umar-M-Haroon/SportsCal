//
//  AdInsertionHelper.swift
//  SportsCal
//
//  Created by Umar Haroon on 2026-04-08.
//

import Foundation

/// A globally-capped, duplicate-free ad layout for a single scrollable feed.
///
/// The previous design applied `AdConfiguration.maxAdsPerScreen` independently
/// inside *every* section, so a feed with N ad-bearing sections could show up to
/// N × maxAds ads (e.g. `ModernDayPage`'s Live + Your Teams + For You + sport
/// gaps → up to 12 from a pool of only 5 preloaded creatives, with repeats).
///
/// `FeedAdPlan` is the result of allocating ads from ONE budget across the whole
/// feed: each placed ad gets a *distinct* sequential creative slot (0, 1, …),
/// so the same creative never shows twice on one screen. It is a plain value
/// type (compiles on every platform) built fresh each render from the feed's
/// data, so it never mutates view state during `body` evaluation.
struct FeedAdPlan {
    /// region key → (row index within that region → creative slot)
    fileprivate(set) var rowAds: [String: [Int: Int]] = [:]
    /// section-gap index → creative slot
    fileprivate(set) var gapAds: [Int: Int] = [:]

    /// Creative slot for a row inside a flat-list region, or nil if no ad there.
    func slot(region: String, row: Int) -> Int? { rowAds[region]?[row] }
    /// Creative slot for a between-sections gap, or nil if no ad there.
    func gapSlot(_ index: Int) -> Int? { gapAds[index] }
}

#if os(iOS)
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

/// Builds a `FeedAdPlan` by drawing from a single global budget. Offer regions
/// in the order they appear in the feed; once the budget is spent, later offers
/// allocate nothing. Each allocated ad consumes one unit of budget and is given
/// the next sequential creative slot, so no creative repeats within the feed.
struct FeedAdPlanner {
    private let cap: Int
    private var slot = 0
    private(set) var plan = FeedAdPlan()

    init(cap: Int) { self.cap = max(0, cap) }

    /// Remaining global ad budget for this feed.
    private var remaining: Int { max(0, cap - slot) }

    /// Offer a flat list of `count` rows under `region`. Allocates ads at the
    /// adaptive interval, capped by the remaining global budget. Lists shorter
    /// than `minimumRows` are skipped so tiny sections don't get ads.
    mutating func offerFlatList(region: String, count: Int, minimumRows: Int = 5) {
        guard remaining > 0, count >= minimumRows else { return }
        let interval = AdConfiguration.adaptiveInterval(forGameCount: count)
        let indices = AdInsertionHelper.gameAdIndices(
            totalGames: count, every: interval, maxAds: remaining)
        guard !indices.isEmpty else { return }
        var map: [Int: Int] = [:]
        for i in indices {
            map[i] = slot
            slot += 1
        }
        plan.rowAds[region] = map
    }

    /// Offer a single lead ad under `region` (rendered at row 0), if budget
    /// remains. Used for standalone placements that aren't tied to a list.
    mutating func offerSingle(region: String) {
        guard remaining > 0 else { return }
        plan.rowAds[region] = [0: slot]
        slot += 1
    }

    /// Offer `sectionCount` section gaps, distributing ads evenly via
    /// `AdInsertionHelper.sectionAdSlots`, capped by the remaining budget.
    mutating func offerSectionGaps(sectionCount: Int) {
        guard remaining > 0, sectionCount > 1 else { return }
        let gaps = AdInsertionHelper.sectionAdSlots(
            sectionCount: sectionCount, maxAds: remaining).sorted()
        for g in gaps {
            guard remaining > 0 else { break }
            plan.gapAds[g] = slot
            slot += 1
        }
    }
}
#endif
