@testable import App
import XCTVapor
import SportsCalModel
import Foundation

/// Exercises every ESPN-backed league through the real server fetch path, so we can see
/// which leagues actually return games rather than inferring it from prod's cached blobs.
/// Opt-in via RELIABILITY_SWEEP=1 — hits the network, excluded from CI.
final class ESPNCoverageSweepTests: XCTestCase {

    /// See the note in ReliabilitySweepDiagnosticTests: a detached shutdown lets the
    /// Application deinit before it runs.
    private func withApp<T>(_ body: (Application) async throws -> T) async throws -> T {
        let app = Application(.testing)
        app.http.client.configuration.timeout = .init(connect: .seconds(5), read: .seconds(20))
        do {
            let result = try await body(app)
            try? await app.asyncShutdown()
            return result
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
    }

    private func skipUnlessEnabled() throws {
        guard ProcessInfo.processInfo.environment["RELIABILITY_SWEEP"] == "1" else {
            throw XCTSkip("set RELIABILITY_SWEEP=1")
        }
    }

    /// Today's board for every league that has an ESPN slug: the live-score path.
    /// This is the regression test for the Akamai 403 — before the User-Agent fix every
    /// one of these failed.
    func testEveryLeagueTodayBoard() async throws {
        try skipUnlessEnabled()
        try await withApp { app in
            var failures: [String] = []
            for league in Leagues.allCases where league.espnSlug != nil {
                do {
                    let board = try await Integrator.getESPNScoreboard(for: league, app.client)
                    let games = LiveEvent(events: board, league: league)?.events ?? []
                    let live = games.filter { $0.strStatus == "in" }.count
                    // String(format:) with %@ is Darwin-only; keep this portable.
                    print("\(league) slug=\(league.espnSlug ?? "-") events=\(board.events.count) games=\(games.count) live=\(live)")
                } catch {
                    failures.append("\(league) [\(league.espnSlug ?? "-")]: \(error)")
                }
            }
            XCTAssertTrue(failures.isEmpty, "leagues failing to fetch:\n" + failures.joined(separator: "\n"))
        }
    }

    /// The forward window is the schedule backfill for leagues TheSportsDB publishes late.
    /// Drives the real `ESPNFetchJob` helper rather than a copy of its loop, so a regression
    /// in the production function actually fails this test.
    func testForwardWindowRecoversNBASeason() async throws {
        try skipUnlessEnabled()
        try await withApp { app in
            let start = Date()
            let games = try await ESPNFetchJob.forwardWindowGames(
                league: .nba, daysAhead: 120, client: app.client
            )
            let elapsed = Date().timeIntervalSince(start)
            print("NBA forward window: 120 days -> \(games.count) unique games in \(String(format: "%.1f", elapsed))s")

            XCTAssertGreaterThan(games.count, 200, "forward window should recover the bulk of the NBA season")
            // Dedup contract: the day pair and ESPN's timezone-shifted boundaries can list
            // the same event twice.
            let ids = games.compactMap(\.idEvent)
            XCTAssertEqual(ids.count, Set(ids).count, "forward window returned duplicate event ids")
        }
    }
}
