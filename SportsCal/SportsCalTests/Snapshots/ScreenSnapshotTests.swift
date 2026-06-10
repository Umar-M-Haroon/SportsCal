//
//  ScreenSnapshotTests.swift
//  SportsCalTests
//
//  Hero screen snapshots for Figma AI design review.
//  7 iOS views: DayPage populated + GameDetailView NBA live + GameDetailView NFL final
//              + RaceDetailView F1 + TournamentDetailView Masters + BrowsePage + SettingsView
//

#if canImport(SnapshotTesting) && os(iOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import Scoreline
import SportsCalModel

@MainActor
final class ScreenSnapshotTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        let expectation = XCTestExpectation(description: "prewarm badges")
        Task {
            await RealisticFixtures.prewarmBadges()
            expectation.fulfill()
        }
        XCTWaiter().wait(for: [expectation], timeout: 15)
    }

    private func wrap<V: View>(_ view: V, viewModel: GameViewModel? = nil) -> some View {
        let vm = viewModel ?? RealisticFixtures.populatedViewModel()
        return view
            .environment(vm)
            .environment(Fixtures.favorites())
            .environment(Fixtures.storage())
            .environment(Fixtures.engagementTracker())
            .environment(Fixtures.subscriptionManager())
            .environment(Fixtures.adManager())
    }

    // MARK: - DayPage (hero list)

    func test_dayPage_gameDay() throws {
        // DayPage renders wall-clock-relative text ("in 2 hr", live elapsed),
        // so its pixels drift between runs and can't be asserted stably.
        guard ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" else {
            throw XCTSkip("DayPage snapshot is time-relative; set RECORD_SNAPSHOTS=1 to regenerate the PNG.")
        }
        let view = wrap(DayPage(
            shouldShowSportsCalProAlert: .constant(false),
            spotlightGameID: .constant(nil)
        ))
        assertReviewSnapshots(of: view, named: "hero-DayPage", record: true)
    }

    // MARK: - GameDetailView — NBA (Celtics vs Lakers)

    func test_gameDetail_nba_live() {
        let game = RealisticFixtures.nbaLive
        let view = wrap(GameDetailView(
            game: game,
            homeTeam: RealisticFixtures.nbaHomeTeam,
            awayTeam: RealisticFixtures.nbaAwayTeam
        ))
        assertReviewSnapshots(of: view, named: "hero-GameDetail-NBA")
    }

    // MARK: - GameDetailView — NFL playoff final

    func test_gameDetail_nfl_final() {
        let game = RealisticFixtures.nflFinal
        let view = wrap(GameDetailView(
            game: game,
            homeTeam: RealisticFixtures.nflHomeTeam,
            awayTeam: RealisticFixtures.nflAwayTeam
        ))
        assertReviewSnapshots(of: view, named: "hero-GameDetail-NFL")
    }

    // MARK: - RaceDetailView — Monaco GP live

    func test_raceDetail_monaco() {
        let view = wrap(RaceDetailView(game: RealisticFixtures.monacoLive))
        assertReviewSnapshots(of: view, named: "hero-RaceDetail-Monaco")
    }

    // MARK: - TournamentDetailView — Masters live

    func test_tournamentDetail_masters() {
        let view = wrap(TournamentDetailView(game: RealisticFixtures.mastersLive))
        assertReviewSnapshots(of: view, named: "hero-Tournament-Masters")
    }

    // MARK: - BrowsePage

    func test_browsePage() {
        let view = wrap(BrowsePage())
        assertReviewSnapshots(of: view, named: "hero-BrowsePage")
    }

    // MARK: - SettingsView

    func test_settingsView() {
        let view = wrap(NavigationStack { SettingsView(sheetType: .constant(nil)) })
        assertReviewSnapshots(of: view, named: "hero-SettingsView")
    }
}
#endif
