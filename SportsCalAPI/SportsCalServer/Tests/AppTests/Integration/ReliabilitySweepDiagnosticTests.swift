@testable import App
import XCTVapor
import SportsCalModel
import Foundation

/// Live-network diagnostics for the Aug-2026 reliability sweep. Hits real ESPN through the
/// same Vapor client (and timeout config) prod uses, so a failure here reproduces the server's
/// behaviour rather than a curl's. Opt-in via RELIABILITY_SWEEP=1 — these are not hermetic.
final class ReliabilitySweepDiagnosticTests: XCTestCase {

    private func makeApp() -> Application {
        let app = Application(.testing)
        // Mirror configure(): bounded outbound HTTP.
        app.http.client.configuration.timeout = .init(connect: .seconds(5), read: .seconds(20))
        return app
    }

    private func skipUnlessEnabled() throws {
        guard ProcessInfo.processInfo.environment["RELIABILITY_SWEEP"] == "1" else {
            throw XCTSkip("set RELIABILITY_SWEEP=1")
        }
    }

    /// DBUpdatejob's structured-tennis build: 4 season fetches (~86 MB total).
    func testTennisSeasonFetchThroughVaporClient() async throws {
        try skipUnlessEnabled()
        let app = makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let year = 2026
        for tour in [Leagues.atp, Leagues.wta] {
            for y in [year - 1, year] {
                let start = Date()
                do {
                    let board = try await Integrator.getESPNScoreboard(for: tour, app.client, dates: y)
                    let games = LiveEvent(events: board, league: tour)?.events ?? []
                    print("OK  \(tour) \(y): tournaments=\(board.events.count) games=\(games.count) in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
                } catch {
                    print("FAIL \(tour) \(y) after \(String(format: "%.1f", Date().timeIntervalSince(start)))s: \(error)")
                }
            }
        }
    }

    /// ESPNTennisJob's per-minute fetch. `dates: nil` + usesSingleYearSeason => season query.
    func testTennisJobPerTickFetchSize() async throws {
        try skipUnlessEnabled()
        let app = makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        for tour in [Leagues.atp, Leagues.wta] {
            let start = Date()
            do {
                let board = try await Integrator.getESPNScoreboard(for: tour, app.client)
                print("OK  \(tour) per-tick: tournaments=\(board.events.count) in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
            } catch {
                print("FAIL \(tour) per-tick after \(String(format: "%.1f", Date().timeIntervalSince(start)))s: \(error)")
            }
        }
    }

    /// ESPNFetchJob's live path for MLB — the bucket that is empty in prod while a game is live.
    func testMLBLiveScoreboard() async throws {
        try skipUnlessEnabled()
        let app = makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let board = try await Integrator.getScoreboard(sport: .mlb, client: app.client)
        let games = LiveEvent(events: board, league: .mlb)?.events ?? []
        let inProgress = games.filter { $0.strStatus == "in" }
        print("MLB: scoreboardEvents=\(board.events.count) games=\(games.count) inProgress=\(inProgress.count)")
        for g in games {
            let away = String(describing: g.strAwayTeam)
            let home = String(describing: g.strHomeTeam)
            let status = String(describing: g.strStatus)
            print("   \(away) @ \(home) status=\(status) \(String(describing: g.intAwayScore))-\(String(describing: g.intHomeScore))")
        }
        XCTAssertFalse(games.isEmpty, "MLB scoreboard produced no games")
    }
}
