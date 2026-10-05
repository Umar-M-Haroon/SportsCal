@testable import App
import XCTVapor
import SportsCalModel
import Foundation

/// IMSA and WEC against the real feeds (TheSportsDB needs SportsDB_API_KEY; Al Kamel's
/// public results sites). Opt-in via RELIABILITY_SWEEP=1: hits the network, and the
/// first run walks a whole season of result files.
final class AlKamelSweepTests: XCTestCase {
    private func run(_ series: AlKamelSeries, minimumWithResults: Int) async throws {
        guard ProcessInfo.processInfo.environment["RELIABILITY_SWEEP"] == "1" else { throw XCTSkip("set RELIABILITY_SWEEP=1") }
        let app = Application(.testing)
        app.http.client.configuration.timeout = .init(connect: .seconds(5), read: .seconds(60))
        app.kv = InMemoryKeyValueStore()

        let games = try await AlKamelService.scheduleGames(series, app: app, isDebug: true)
        let thisYear = games.filter { $0.season == "2026" }
        print("AK \(series) games=\(games.count) 2026=\(thisYear.count)")
        XCTAssertFalse(thisYear.contains { $0.strHomeTeam.lowercased().contains("hyperpole") || $0.strHomeTeam.lowercased().contains("qualifying") },
                       "sessions are never races")
        XCTAssertFalse(thisYear.contains { $0.strStatus == "in" }, "no race is live in this window")
        for game in thisYear {
            let race = game.sessions?.last { $0.sessionType == "race" }
            print("  \(game.strHomeTeam) \(game.strTimestamp ?? "-") \(game.strStatus ?? "-") race=\(race?.leaderboard.count ?? 0) sessions=\(game.sessions?.map { "\($0.shortName)(\($0.leaderboard.count))" } ?? [])")
        }
        let withResults = thisYear.filter { ($0.sessions?.last { $0.sessionType == "race" }?.leaderboard.count ?? 0) > 10 }
        XCTAssertGreaterThanOrEqual(withResults.count, minimumWithResults)

        let latest = try XCTUnwrap(withResults.last)
        let id = try XCTUnwrap(latest.idEvent?.replacingOccurrences(of: "\(series.rawValue)-", with: ""))
        let detail = try await AlKamelService.raceDetail(series, tsdbRaceID: id, app: app, isDebug: true)
        let race = try XCTUnwrap(detail.sessions?.last { $0.sessionType == "race" })
        let classes = Dictionary(grouping: race.leaderboard) { $0.stockCar?.vehicleClass ?? "-" }
        for (name, rows) in classes.sorted(by: { $0.key < $1.key }) {
            let winner = rows.first { $0.stockCar?.classPosition == 1 }
            print("  \(latest.strHomeTeam) \(name): #\(winner?.stockCar?.carNumber ?? "-") \(winner?.name ?? "-") \(winner?.stockCar?.vehicle ?? "-") (\(rows.count) cars)")
        }
        XCTAssertGreaterThan(classes.count, 1, "multi-class")
        XCTAssertTrue(race.leaderboard.allSatisfy { !($0.stockCar?.drivers ?? []).isEmpty }, "every car has its crew")
        print("  raceState duration=\(race.raceState?.duration ?? -1) laps=\(race.raceState?.lap ?? -1)")

        if series == .imsa {
            let standings: ClassStandings
            do {
                standings = try await AlKamelService.standings(.imsa, app: app, isDebug: true)
            } catch {
                print("  standings error: \(String(reflecting: error))")
                try await app.asyncShutdown()
                throw error
            }
            print("  standings classes=\(standings.classes.map { "\($0.name):\($0.drivers.first?.name ?? "-")" })")
            XCTAssertGreaterThanOrEqual(standings.classes.count, 3)
        }
        try await app.asyncShutdown()
    }

    func testIMSA() async throws { try await run(.imsa, minimumWithResults: 8) }
    func testWEC() async throws { try await run(.wec, minimumWithResults: 4) }
}
