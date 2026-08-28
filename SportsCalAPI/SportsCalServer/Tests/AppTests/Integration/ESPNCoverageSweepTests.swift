@testable import App
import XCTVapor
import SportsCalModel
import Foundation

/// Exercises every ESPN-backed league through the real server fetch path, so we can see
/// which leagues actually return games rather than inferring it from prod's cached blobs.
/// Opt-in via RELIABILITY_SWEEP=1 — hits the network.
final class ESPNCoverageSweepTests: XCTestCase {

    private func makeApp() -> Application {
        let app = Application(.testing)
        app.http.client.configuration.timeout = .init(connect: .seconds(5), read: .seconds(20))
        return app
    }

    private func skipUnlessEnabled() throws {
        guard ProcessInfo.processInfo.environment["RELIABILITY_SWEEP"] == "1" else {
            throw XCTSkip("set RELIABILITY_SWEEP=1")
        }
    }

    /// Today's board for every league that has an ESPN slug: the live-score path.
    func testEveryLeagueTodayBoard() async throws {
        try skipUnlessEnabled()
        let app = makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        var failures: [String] = []
        for league in Leagues.allCases where league.espnSlug != nil {
            do {
                let board = try await Integrator.getESPNScoreboard(for: league, app.client)
                let games = LiveEvent(events: board, league: league)?.events ?? []
                let live = games.filter { $0.strStatus == "in" }.count
                print(String(format: "%-28@ slug=%-22@ events=%4d games=%5d live=%2d",
                             "\(league)" as NSString, "\(league.espnSlug ?? "-")" as NSString,
                             board.events.count, games.count, live))
            } catch {
                failures.append("\(league) [\(league.espnSlug ?? "-")]: \(error)")
                print("FAIL \(league) [\(league.espnSlug ?? "-")]: \(error)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "leagues failing to fetch:\n" + failures.joined(separator: "\n"))
    }

    /// Mirrors what `ESPNFetchJob.fetchForwardScheduleWindowIfStale` does for one league at
    /// the real 120-day horizon and concurrency, to confirm the backfill actually recovers
    /// the NBA season TheSportsDB is missing — and that it costs seconds, not minutes.
    func testForwardWindowRecoversNBASeason() async throws {
        try skipUnlessEnabled()
        let app = makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        df.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let days: [Int] = (1...120).compactMap { offset in
            guard let d = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { return nil }
            return Int(df.string(from: d))
        }

        let start = Date()
        var games: [Game] = []
        var iterator = days.makeIterator()
        await withTaskGroup(of: [Game].self) { group in
            func addNext() {
                guard let ymd = iterator.next() else { return }
                group.addTask {
                    guard let board = try? await Integrator.getESPNScoreboard(for: .nba, app.client, dates: ymd) else { return [] }
                    return LiveEvent(events: board, league: .nba)?.events ?? []
                }
            }
            for _ in 0..<6 { addNext() }
            while let g = await group.next() { games.append(contentsOf: g); addNext() }
        }
        var seen = Set<String>()
        games = games.filter { g in guard let id = g.idEvent else { return true }; return seen.insert(id).inserted }

        let elapsed = Date().timeIntervalSince(start)
        print("NBA forward window: \(days.count) days -> \(games.count) unique games in \(String(format: "%.1f", elapsed))s")
        XCTAssertGreaterThan(games.count, 200, "forward window should recover the bulk of the NBA season")
    }

    /// Season-wide coverage for the leagues whose new season we care about right now.
    /// Prints per-month counts so a truncated season is obvious.
    func testUpcomingSeasonCoverage() async throws {
        try skipUnlessEnabled()
        let app = makeApp()
        defer { Task { try? await app.asyncShutdown() } }

        let cal = Calendar(identifier: .gregorian)
        for league in [Leagues.nba, .nhl, .nfl, .mlb] {
            var byMonth: [String: Int] = [:]
            // Walk a season's worth of days via the per-day board (the same call
            // `/schedules/date/:date` makes) — the day query is the only one that
            // carries fixtures for these leagues.
            for offset in stride(from: 0, to: 210, by: 7) {
                guard let day = cal.date(byAdding: .day, value: offset, to: Date()) else { continue }
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyyMMdd"
                fmt.timeZone = .init(secondsFromGMT: 0)
                guard let dates = Int(fmt.string(from: day)) else { continue }
                guard let board = try? await Integrator.getESPNScoreboard(for: league, app.client, dates: dates) else { continue }
                let key = String(fmt.string(from: day).prefix(6))
                byMonth[key, default: 0] += board.events.count
            }
            print("\(league) sampled (1 day per week): \(byMonth.sorted { $0.key < $1.key })")
        }
    }
}
