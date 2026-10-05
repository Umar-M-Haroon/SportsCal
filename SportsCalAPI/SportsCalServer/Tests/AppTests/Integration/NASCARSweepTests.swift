@testable import App
import XCTVapor
import SportsCalModel
import Foundation

/// Runs the NASCAR service against the real cf.nascar.com feeds: the schedule build, the
/// live path, standings and race detail. Opt-in via RELIABILITY_SWEEP=1 — hits the
/// network, excluded from CI. The feeds are undocumented, so this is the canary for a
/// schema change.
final class NASCARSweepTests: XCTestCase {
    private func withApp<T>(_ body: (Application) async throws -> T) async throws -> T {
        let app = Application(.testing)
        app.http.client.configuration.timeout = .init(connect: .seconds(5), read: .seconds(30))
        app.kv = InMemoryKeyValueStore()
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

    func testScheduleLiveStandingsAndDetail() async throws {
        try skipUnlessEnabled()
        try await withApp { app in
            let games = try await NASCARService.scheduleGames(app: app, isDebug: true)
            XCTAssertGreaterThan(games.count, 30, "two seasons of Cup races")
            let finished = games.filter { $0.strStatus == "post" }
            // The schedule copy is trimmed: top 15 of each race (full results come from the endpoint).
            let withResults = finished.filter { game in
                (game.sessions?.first { $0.sessionType == "race" }?.leaderboard.count ?? 0) == 15
            }
            let bytes = try JSONEncoder().encode(LiveScore(racing: LiveEvent(events: games))).count
            print("NASCAR games=\(games.count) finished=\(finished.count) withResults=\(withResults.count) bytes=\(bytes)")
            XCTAssertGreaterThan(withResults.count, 20, "finished races carry their top 15")
            XCTAssertLessThan(bytes, 1_000_000, "every current client downloads this in /schedules")
            for game in games.filter({ $0.strStatus != "pre" }).suffix(3) {
                print("  \(game.strHomeTeam) @ \(game.venueName ?? "-") \(game.strStatus ?? "-") \(game.strProgress ?? "-") leader=\(game.strAwayTeam) sessions=\(game.sessions?.map { "\($0.shortName):\($0.status ?? "-")" } ?? [])")
            }

            let live = await NASCARService.liveGames(app: app, isDebug: true)
            print("NASCAR live-window games=\(live.map { "\($0.strHomeTeam) \($0.strStatus ?? "-") \($0.strProgress ?? "-")" })")

            let standings = try await NASCARService.standings(app: app, isDebug: true)
            XCTAssertGreaterThan(standings.drivers.count, 30)
            print("NASCAR standings leader=\(standings.drivers.first?.name ?? "-") chase=\(standings.drivers.filter(\.inPlayoffs).count)")

            let latest = try XCTUnwrap(withResults.compactMap { $0.idEvent.flatMap(NASCARGameBuilder.raceID(fromEventID:)) }.max())
            let detail = try await NASCARService.raceDetail(raceID: latest, app: app, isDebug: true)
            print("NASCAR detail race=\(latest) laps=\(detail.lapPositions.first?.positions.count ?? 0) cars=\(detail.lapPositions.count) notes=\(detail.notes.count) stages=\(detail.stages.count) cautions=\(detail.cautions.count) pits=\(detail.pitStops.count)")
            XCTAssertFalse(detail.lapPositions.isEmpty)
            let fullRace = try XCTUnwrap(detail.sessions?.first { $0.sessionType == "race" })
            XCTAssertGreaterThan(fullRace.leaderboard.count, 30, "the endpoint carries the whole field")
            XCTAssertFalse(detail.notes.isEmpty)
        }
    }
}
