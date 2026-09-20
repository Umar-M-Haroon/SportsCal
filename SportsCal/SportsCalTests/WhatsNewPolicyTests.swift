//
//  WhatsNewPolicyTests.swift
//  SportsCalTests
//

import XCTest
import SwiftUI
import SportsCalModel
@testable import Scoreline

final class WhatsNewPolicyTests: XCTestCase {

    private let releases = [
        WhatsNewRelease(version: "3.4", features: []),
        WhatsNewRelease(version: "3.3", features: []),
    ]

    private func show(app: String, lastSeen: String?, fresh: Bool = false) -> String? {
        WhatsNewPolicy.releaseToShow(appVersion: app, lastSeen: lastSeen, isFreshInstall: fresh, releases: releases)?.version
    }

    func testCompareTreatsMissingComponentsAsZero() {
        XCTAssertEqual(WhatsNewPolicy.compare("3.3", "3.3.0"), .orderedSame)
        XCTAssertEqual(WhatsNewPolicy.compare("3.10", "3.9"), .orderedDescending)
        XCTAssertEqual(WhatsNewPolicy.compare("3.2.1", "3.3"), .orderedAscending)
    }

    func testUpgraderFromPreWhatsNewBuildSeesCurrentNotes() {
        XCTAssertEqual(show(app: "3.3", lastSeen: nil), "3.3")
    }

    func testFreshInstallSeesNothing() {
        XCTAssertNil(show(app: "3.3", lastSeen: nil, fresh: true))
    }

    func testAlreadySeenIsNotShownAgain() {
        XCTAssertNil(show(app: "3.3", lastSeen: "3.3"))
        XCTAssertNil(show(app: "3.3.1", lastSeen: "3.3"))
    }

    func testHotfixCarriesNotesForUsersWhoSkippedTheRelease() {
        XCTAssertEqual(show(app: "3.3.1", lastSeen: "3.2.1"), "3.3")
    }

    func testSkippingVersionsShowsOnlyNewest() {
        XCTAssertEqual(show(app: "3.4", lastSeen: "3.2"), "3.4")
    }

    func testVersionWithoutNotesShowsNothing() {
        XCTAssertNil(show(app: "3.2.1", lastSeen: nil))
    }

    /// The A-League CTA has to clear the same `hiddenCompetitions` entry that
    /// `seedDefaultHiddenCompetitions` writes, and turn soccer on, or the sheet's
    /// one-tap promise silently does nothing.
    @MainActor
    func testALeagueCTAUnhidesTheLeagueAndEnablesSoccer() {
        let defaults = UserDefaults.standard
        let savedHidden = defaults.stringArray(forKey: "hiddenCompetitions")
        let savedSeeded = defaults.stringArray(forKey: "seededHiddenCompetitions")
        let savedSoccer = defaults.object(forKey: "shouldShowSoccer")
        defer {
            defaults.set(savedHidden, forKey: "hiddenCompetitions")
            defaults.set(savedSeeded, forKey: "seededHiddenCompetitions")
            defaults.set(savedSoccer, forKey: "shouldShowSoccer")
        }

        defaults.removeObject(forKey: "hiddenCompetitions")
        defaults.removeObject(forKey: "seededHiddenCompetitions")
        defaults.set(false, forKey: "shouldShowSoccer")

        // init() seeds A-League into hiddenCompetitions, as on a real install.
        let storage = UserDefaultStorage()
        let action = WhatsNewAction.showCompetition(.A_League, sport: .soccer)
        XCTAssertTrue(storage.hiddenCompetitions.contains(Leagues.A_League.leagueName), "seeded-hidden")
        XCTAssertFalse(action.isSatisfied(in: storage), "starts-unsatisfied")

        action.applyPreferences(storage: storage)

        XCTAssertFalse(storage.hiddenCompetitions.contains(Leagues.A_League.leagueName), "unhidden-after-apply")
        XCTAssertTrue(storage.shouldShowSoccer, "soccer-on-after-apply")
        XCTAssertTrue(action.isSatisfied(in: storage), "satisfied-after-apply")
    }

    /// A Focus Filter masks `effectiveShouldShow`, so reading it here used to make
    /// the CTA skip turning the sport on (and show "On" while it was off).
    @MainActor
    func testCTAWritesTheUserPreferenceWhileAFocusFilterIsActive() {
        let group = UserDefaults(suiteName: "group.Komodo.SportsCal")
        let defaults = UserDefaults.standard
        let savedSoccer = defaults.object(forKey: "shouldShowSoccer")
        let savedFocusActive = group?.object(forKey: "focusFilterActive")
        defer {
            defaults.set(savedSoccer, forKey: "shouldShowSoccer")
            group?.set(savedFocusActive, forKey: "focusFilterActive")
        }

        defaults.set(false, forKey: "shouldShowSoccer")
        // Focus says "show soccer" while the user's own preference is off.
        group?.set(true, forKey: "focusFilterActive")
        group?.set(true, forKey: "focus_shouldShowSoccer")

        let storage = UserDefaultStorage()
        let action = WhatsNewAction.enableSport(.soccer)
        XCTAssertFalse(action.isSatisfied(in: storage), "focus override must not report the sport as on")

        action.applyPreferences(storage: storage)

        XCTAssertTrue(storage.shouldShowSoccer, "CTA must write the user preference")
    }

    func testReleaseCatalogIsNewestFirstAndUnique() {
        let versions = WhatsNewRelease.all.map(\.version)
        XCTAssertEqual(Set(versions).count, versions.count)
        XCTAssertEqual(versions, versions.sorted { WhatsNewPolicy.compare($0, $1) == .orderedDescending })
    }
}
