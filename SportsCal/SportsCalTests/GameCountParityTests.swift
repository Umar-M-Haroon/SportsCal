//
//  GameCountParityTests.swift
//  SportsCalTests
//
//  Asserts that every "today" view sees the same number of games for the
//  same date, on a known fixture. Catches the class of bug we hit twice
//  during the design system migration:
//
//    - gamesDict drift → EFRemix Today empty while Browse worked
//    - hidePastEvents → ModernDayPage hid finished games of today while
//      Calendar still counted them
//
//  If a future change diverges day-bounded counts, this test fires.
//

import XCTest
import SportsCalModel
@testable import SportsCal

@MainActor
final class GameCountParityTests: XCTestCase {

    func testDayBoundedCountsAgreeAcrossViewsOnGameDay() throws {
        // Arrange — realistic fixture spans Apr 14 with mixed sports/states.
        let storage = makeStorage(allSportsOn: true, hidePastEvents: false)
        let vm = makeViewModel(storage: storage)

        // RealisticFixtures uses Apr 14 2024 as "game day". Use the same.
        let cal = Calendar(identifier: .gregorian)
        let gameDay = cal.date(from: DateComponents(year: 2024, month: 4, day: 14))!

        // Act
        let snap = GameCountAudit.snapshot(for: gameDay, viewModel: vm, storage: storage)

        // Assert — Modern + Classic + raw totalGames-on-date all agree.
        // (filteredGames-on-date may legitimately differ if hidePastEvents
        // is on; we set it off above so it should also match.)
        XCTAssertEqual(
            snap.modernTodayCount, snap.classicTodayCount,
            "ModernDayPage and Classic/Ambient Today see different game counts on \(snap.dateLabel). Modern: \(snap.modernTodayCount), Classic: \(snap.classicTodayCount)"
        )
        XCTAssertEqual(
            snap.modernTodayCount, snap.totalGamesOnDate,
            "ModernDayPage doesn't surface every game in totalGames for \(snap.dateLabel). Modern: \(snap.modernTodayCount), totalGames: \(snap.totalGamesOnDate)"
        )
        XCTAssertEqual(
            snap.modernTodayCount, snap.filteredGamesOnDate,
            "filteredGames diverges from ModernDayPage with hidePastEvents off. Modern: \(snap.modernTodayCount), filteredGames: \(snap.filteredGamesOnDate)"
        )
        XCTAssertFalse(snap.hasDivergence,
                       "Day-bounded counts diverge: \(snap.dayBoundedCounts)")
    }

    func testHidePastEventsExplainsTheOnlyAcceptableDivergence() throws {
        // With hidePastEvents = true (the production default), filteredGames
        // legitimately drops past games of today — but Modern and Classic
        // Today should STILL match each other (both bypass the filter).
        let storage = makeStorage(allSportsOn: true, hidePastEvents: true)
        let vm = makeViewModel(storage: storage)

        let cal = Calendar(identifier: .gregorian)
        let gameDay = cal.date(from: DateComponents(year: 2024, month: 4, day: 14))!

        let snap = GameCountAudit.snapshot(for: gameDay, viewModel: vm, storage: storage)

        XCTAssertEqual(
            snap.modernTodayCount, snap.classicTodayCount,
            "Modern and Classic Today must stay aligned regardless of hidePastEvents"
        )
        XCTAssertEqual(
            snap.modernTodayCount, snap.totalGamesOnDate,
            "Modern Today must equal totalGames-on-date regardless of hidePastEvents"
        )
        // filteredGames may be ≤ modern when hidePastEvents drops finals.
        XCTAssertLessThanOrEqual(
            snap.filteredGamesOnDate, snap.modernTodayCount,
            "filteredGames-on-date should never exceed Modern Today"
        )
    }

    func testBrowseSumIncludesAllFetchedGames() throws {
        let storage = makeStorage(allSportsOn: true, hidePastEvents: false)
        let vm = makeViewModel(storage: storage)

        let snap = GameCountAudit.snapshot(for: Date(), viewModel: vm, storage: storage)

        let browseSum = snap.browsePerSport.map(\.total).reduce(0, +)
        XCTAssertEqual(
            browseSum, snap.totalGamesAllDates,
            "Sum of Browse per-sport counts (\(browseSum)) should equal totalGames (\(snap.totalGamesAllDates)). If they diverge, a sport bucket is missing or double-counting."
        )
    }

    func testSportPrefsHideTheirGamesFromModernTodayButNotTotalGames() throws {
        // With NBA off, basketball games on game day disappear from
        // ModernDayPage but remain in totalGames-on-date.
        let storage = makeStorage(allSportsOn: true, hidePastEvents: false)
        storage.shouldShowNBA = false
        storage.shouldShowWNBA = false
        let vm = makeViewModel(storage: storage)

        let cal = Calendar(identifier: .gregorian)
        let gameDay = cal.date(from: DateComponents(year: 2024, month: 4, day: 14))!

        let snap = GameCountAudit.snapshot(for: gameDay, viewModel: vm, storage: storage)

        XCTAssertLessThan(
            snap.modernTodayCount, snap.totalGamesOnDate,
            "Disabling NBA should remove basketball games from Modern Today (\(snap.modernTodayCount)) while totalGames-on-date (\(snap.totalGamesOnDate)) keeps them"
        )
    }

    // MARK: - Helpers

    private func makeStorage(allSportsOn: Bool, hidePastEvents: Bool) -> UserDefaultStorage {
        let s = UserDefaultStorage()
        s.shouldShowNBA = allSportsOn
        s.shouldShowNFL = allSportsOn
        s.shouldShowNHL = allSportsOn
        s.shouldShowSoccer = allSportsOn
        s.shouldShowMLB = allSportsOn
        s.shouldShowGolf = allSportsOn
        s.shouldShowTennis = allSportsOn
        s.shouldShowRacing = allSportsOn
        s.shouldShowWNBA = allSportsOn
        s.hidePastEvents = hidePastEvents
        return s
    }

    private func makeViewModel(storage: UserDefaultStorage) -> GameViewModel {
        // Reuse RealisticFixtures' game day data to avoid duplicating the
        // fixture wiring. RealisticFixtures returns a vm with its own
        // storage; we need our parameterized storage to drive the audit.
        let vm = RealisticFixtures.populatedViewModel()
        // Re-parent the storage so sport prefs flow through. The fixture's
        // applySnapshotFixtures has already loaded games/teams; only the
        // storage reference matters for the audit's filters.
        vm.appStorage = storage
        // Re-run filter pipeline so filteredGames respects the new storage.
        vm.filterSports(force: true, skipLiveUpdate: true)
        return vm
    }
}
