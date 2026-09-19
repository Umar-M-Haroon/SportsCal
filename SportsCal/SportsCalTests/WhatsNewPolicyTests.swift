//
//  WhatsNewPolicyTests.swift
//  SportsCalTests
//

import XCTest
import SwiftUI
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

    func testReleaseCatalogIsNewestFirstAndUnique() {
        let versions = WhatsNewRelease.all.map(\.version)
        XCTAssertEqual(Set(versions).count, versions.count)
        XCTAssertEqual(versions, versions.sorted { WhatsNewPolicy.compare($0, $1) == .orderedDescending })
    }
}
