@testable import App
import XCTVapor
import SportsCalModel
import Foundation

/// IndyCar against the real feeds (TheSportsDB needs SportsDB_API_KEY). Opt-in via
/// RELIABILITY_SWEEP=1: hits the network.
final class IndyCarSweepTests: XCTestCase {
    func testScheduleDetailAndStandings() async throws {
        guard ProcessInfo.processInfo.environment["RELIABILITY_SWEEP"] == "1" else { throw XCTSkip("set RELIABILITY_SWEEP=1") }
        let app = Application(.testing)
        app.http.client.configuration.timeout = .init(connect: .seconds(5), read: .seconds(30))
        app.kv = InMemoryKeyValueStore()

        let now = Date()
        let games = try await IndyCarService.scheduleGames(app: app, isDebug: true, now: now)
        let thisYear = games.filter { $0.season == "2026" }
        print("INDY games=\(games.count) 2026=\(thisYear.count)")
        for game in thisYear where (game.sessions?.count ?? 0) < 2 || (game.sessions?.last?.leaderboard.isEmpty ?? true) {
            print("  ODD \(game.strHomeTeam) \(game.strTimestamp ?? "-") sessions=\(game.sessions?.map(\.sessionName) ?? [])")
        }
        for game in thisYear.prefix(4) {
            print("  \(game.strHomeTeam) @ \(game.venueName ?? "-") \(game.strStatus ?? "-") leader=\(game.strAwayTeam) sessions=\(game.sessions?.map { "\($0.shortName):\($0.status ?? "-"):\($0.leaderboard.count)" } ?? [])")
        }
        XCTAssertEqual(thisYear.count, 18, "one game per race; sessions are not races")
        XCTAssertGreaterThan(thisYear.filter { ($0.sessions?.count ?? 0) >= 2 }.count, 14, "practice/qualifying grouped under races")
        let finished = thisYear.filter { $0.strStatus == "post" }
        let withResults = finished.filter { ($0.sessions?.last?.leaderboard.count ?? 0) > 10 }
        print("INDY finished=\(finished.count) withResults=\(withResults.count)")
        XCTAssertGreaterThan(withResults.count, 10, "ESPN matched to the TheSportsDB weekend")

        let latest = try XCTUnwrap(finished.last?.idEvent?.replacingOccurrences(of: "indycar-", with: ""))
        let detail = try await IndyCarService.raceDetail(tsdbRaceID: latest, app: app, isDebug: true, now: now)
        let race = try XCTUnwrap(detail.sessions?.last { $0.sessionType == "race" })
        let winner = try XCTUnwrap(race.leaderboard.first)
        print("INDY detail winner=\(winner.name) car=\(winner.stockCar?.carNumber ?? "-") team=\(winner.constructor ?? "-") engine=\(winner.stockCar?.manufacturer ?? "-") led=\(winner.stockCar?.lapsLed ?? -1) rows=\(race.leaderboard.count)")
        XCTAssertFalse(winner.stockCar?.carNumber.isEmpty ?? true)

        let standings: NASCARStandings
        do {
            standings = try await IndyCarService.standings(app: app, isDebug: true)
        } catch {
            print("INDY standings error: \(String(reflecting: error))")
            throw error
        }
        print("INDY standings leader=\(standings.drivers.first?.name ?? "-") pts=\(standings.drivers.first?.points ?? 0) car=\(standings.drivers.first?.carNumber ?? "-") rows=\(standings.drivers.count)")
        XCTAssertGreaterThan(standings.drivers.count, 20)
        try await app.asyncShutdown()
    }
}
