@testable import App
import XCTVapor
import SportsCalModel
import Foundation

/// Live-network diagnostics for the Aug-2026 reliability sweep. Hits real ESPN through the
/// same Vapor client (and timeout config) prod uses, so a failure here reproduces the server's
/// behaviour rather than a curl's. Opt-in via RELIABILITY_SWEEP=1 — these are not hermetic and
/// are excluded from CI.
final class ReliabilitySweepDiagnosticTests: XCTestCase {

    /// Runs `body` against a configured Application and always shuts it down, on success or
    /// throw. `defer { Task { … } }` would detach the shutdown from the test's lifetime and
    /// let the Application deinit first, tripping Vapor's "shutdown was not called" precondition.
    private func withApp<T>(_ body: (Application) async throws -> T) async throws -> T {
        let app = Application(.testing)
        // Mirror configure(): bounded outbound HTTP.
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

    /// DBUpdatejob's structured-tennis build: 4 season fetches. This is the path the Akamai
    /// 403 broke — it must produce games, not fall through to the sticky stale cache.
    func testTennisSeasonFetchThroughVaporClient() async throws {
        try skipUnlessEnabled()
        try await withApp { app in
            let year = Calendar.current.component(.year, from: Date())
            var failures: [String] = []
            var totalGames = 0
            for tour in [Leagues.atp, Leagues.wta] {
                for y in [year - 1, year] {
                    do {
                        let board = try await Integrator.getESPNScoreboard(for: tour, app.client, dates: y)
                        let games = LiveEvent(events: board, league: tour)?.events ?? []
                        totalGames += games.count
                        print("OK  \(tour) \(y): tournaments=\(board.events.count) games=\(games.count)")
                    } catch {
                        failures.append("\(tour) \(y): \(error)")
                    }
                }
            }
            XCTAssertTrue(failures.isEmpty, "tennis season fetches failed:\n" + failures.joined(separator: "\n"))
            XCTAssertGreaterThan(totalGames, 1000, "season boards should carry the full draw")
        }
    }

    /// ESPNTennisJob's per-tick fetch must stay on day boards. A regression to the season
    /// board is ~20 MB per tour per minute, which is what pegged the box before.
    func testTennisJobPerTickStaysOnDayBoards() async throws {
        try skipUnlessEnabled()
        try await withApp { app in
            for tour in [Leagues.atp, Leagues.wta] {
                for day in ESPNTennisJob.dayKeys() {
                    let board = try await Integrator.getESPNScoreboard(for: tour, app.client, dates: day)
                    // A day board carries the in-progress tournaments only; a season board
                    // would be 60+ for ATP and 125+ for WTA.
                    XCTAssertLessThan(board.events.count, 30,
                                      "\(tour) day \(day) returned \(board.events.count) tournaments — season board regression?")
                }
            }
        }
    }

    /// ESPNFetchJob's live path for MLB — the bucket that was empty in prod while a game
    /// was in progress, because every ESPN call was being 403'd.
    func testMLBScoreboardReturnsGames() async throws {
        try skipUnlessEnabled()
        try await withApp { app in
            let board = try await Integrator.getScoreboard(sport: .mlb, client: app.client)
            let games = LiveEvent(events: board, league: .mlb)?.events ?? []
            print("MLB: scoreboardEvents=\(board.events.count) games=\(games.count) inProgress=\(games.filter { $0.strStatus == "in" }.count)")
            // Deliberately asserts the fetch+decode path works, not that games exist —
            // an off-day or the All-Star break legitimately yields zero.
            XCTAssertEqual(games.count, board.events.count, "every scoreboard event should decode to a Game")
        }
    }
}
