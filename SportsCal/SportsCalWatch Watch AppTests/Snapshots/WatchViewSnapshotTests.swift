//
//  WatchViewSnapshotTests.swift
//  SportsCalWatch Watch AppTests
//
//  Snapshot tests for the watchOS app rows and detail views.
//

#if canImport(SnapshotTesting) && os(watchOS)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import SportsCalWatch_Watch_App
import SportsCalModel

@MainActor
final class WatchViewSnapshotTests: XCTestCase {

    private func team(_ name: String, short: String) -> Team {
        Team(idTeam: nil, strTeam: name, strTeamShort: short, strAlternate: short, strTeamBadge: nil)
    }

    // MARK: - WatchGameRow (team sports)

    func test_watchGameRow_basketball_live() {
        let game = DebugGameFactory.createFakeLiveGame(sport: .basketball)
        let teams = DebugGameFactory.fakeTeams(for: game)
        let view = WatchGameRow(
            game: game,
            teams: [teams.home, teams.away],
            isFavorite: false
        )
        assertWatchReviewSnapshots(of: view, named: "WatchGameRow-basketball-live")
    }

    // MARK: - WatchRaceRow (F1)

    func test_watchRaceRow_live() {
        let game = DebugGameFactory.createFakeLiveRace()
        let view = WatchRaceRow(game: game)
        assertWatchReviewSnapshots(of: view, named: "WatchRaceRow-live")
    }

    // MARK: - WatchTournamentRow (golf)

    func test_watchTournamentRow_golf_major() {
        let game = DebugGameFactory.createFakeLiveTournament(sport: .golf, isMajor: true)
        let view = WatchTournamentRow(game: game)
        assertWatchReviewSnapshots(of: view, named: "WatchTournamentRow-golf-major")
    }

    // MARK: - WatchTennisRow

    func test_watchTennisRow_live() {
        let game = DebugGameFactory.createFakeLiveTournament(sport: .tennis)
        let view = WatchTennisRow(game: game)
        assertWatchReviewSnapshots(of: view, named: "WatchTennisRow-live")
    }

    // MARK: - WatchRaceDetailView

    func test_watchRaceDetailView() {
        let game = DebugGameFactory.createFakeLiveRace()
        let view = WatchRaceDetailView(game: game)
        assertWatchReviewSnapshots(of: view, named: "WatchRaceDetailView")
    }

    // MARK: - WatchTournamentDetailView

    func test_watchTournamentDetailView() {
        let game = DebugGameFactory.createFakeLiveTournament(sport: .golf)
        let view = WatchTournamentDetailView(game: game)
        assertWatchReviewSnapshots(of: view, named: "WatchTournamentDetailView")
    }
}
#endif
