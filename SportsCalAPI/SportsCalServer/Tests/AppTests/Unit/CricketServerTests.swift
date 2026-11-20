import XCTest
@testable import App
import SportsCalModel

/// ESPNCricketJob's sweep de-dupe and schedule merges, and cricket's exclusion from flat
/// `[Game]` routes for app versions that predate it.
final class CricketServerTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z")!

    private func match(_ id: String, league: Leagues = .cricketTests, status: String = "pre",
                       home: String? = nil, away: String? = nil, daysFromNow: Double = 0,
                       endDate: String? = nil) -> Game {
        let date = now.addingTimeInterval(daysFromNow * 86_400)
        return Game(idEvent: id, idLeague: "\(league.rawValue)", strHomeTeam: "New Zealand", strAwayTeam: "India",
                    intHomeScore: home, intAwayScore: away, strStatus: status,
                    strTimestamp: ISO8601DateFormatter().string(from: date),
                    isCompleted: status == "post", isoDate: date, endDate: endDate)
    }

    private func isoDay(_ daysFromNow: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: now.addingTimeInterval(daysFromNow * 86_400))
    }

    // MARK: - Sweep

    func testDayKeysSpanTheSweepWindow() {
        let days = ESPNCricketJob.dayKeys(now: now)
        XCTAssertEqual(days.count, ESPNCricketJob.daysBack + ESPNCricketJob.daysAhead + 1)
        XCTAssertEqual(days.first, 20261115)
        XCTAssertTrue(days.contains(20261120))
        XCTAssertEqual(days, days.sorted())
        XCTAssertEqual(ESPNCricketJob.isoDay(fromKey: 20261121), "2026-11-21")
    }

    func testMultiDayTestIsDedupedToTheLatestDaysCopy() {
        // A Test is on the panel every day it spans.
        let day1 = [match("T1", status: "in", home: "368", away: "45/0 (10 ov)"), match("O1", league: .cricketODIs)]
        let day2 = [match("T1", status: "in", home: "368", away: "159/1 (39 ov)")]
        let day3 = [match("T1", status: "pre")]  // a later panel lagging behind: never goes backwards
        let games = ESPNCricketJob.dedupedAcrossDays([day1, day2, day3])
        XCTAssertEqual(games.compactMap(\.idEvent), ["T1", "O1"])
        XCTAssertEqual(games.first?.intAwayScore, "159/1 (39 ov)")
        XCTAssertEqual(games.first?.strStatus, "in")
    }

    func testSweepReplacesPriorCopiesAndKeepsHistory() {
        let covered = Set((-5...120).map { isoDay(Double($0)) })
        let prior = [
            match("old", status: "post", daysFromNow: -20),                 // before the window: kept
            match("ancient", status: "post", daysFromNow: -400),            // past retention: dropped
            match("moved", daysFromNow: 10),                                // no longer on ESPN: dropped
            match("T1", status: "pre", daysFromNow: 0),
        ]
        let fresh = [match("T1", status: "in", home: "368", away: "159/1 (39 ov)"), match("new", daysFromNow: 30)]
        let merged = ESPNCricketJob.mergingSweep(fresh: fresh, prior: prior, coveredDays: covered, now: now)
        XCTAssertEqual(merged.compactMap(\.idEvent), ["old", "T1", "new"], "sorted by start")
        XCTAssertEqual(merged.first { $0.idEvent == "T1" }?.strStatus, "in")
    }

    func testFailedDayKeepsItsGames() {
        // Day +10 failed: its prior games survive.
        let covered = Set((-5...120).filter { $0 != 10 }.map { isoDay(Double($0)) })
        let merged = ESPNCricketJob.mergingSweep(fresh: [], prior: [match("kept", daysFromNow: 10)], coveredDays: covered, now: now)
        XCTAssertEqual(merged.compactMap(\.idEvent), ["kept"])
    }

    func testSweepNeverRegressesALiveMergedResult() {
        // The live merge finished the match while the sweep was still running.
        let prior = [match("T1", status: "post", home: "368 & 200", away: "300 & 180")]
        let fresh = [match("T1", status: "in", home: "368 & 200", away: "300 & 150/8")]
        let merged = ESPNCricketJob.mergingSweep(fresh: fresh, prior: prior, coveredDays: [], now: now)
        XCTAssertEqual(merged.map(\.strStatus), ["post"])
    }

    // MARK: - Live into schedule

    func testLiveMergesIntoScheduleByEventID() {
        let schedule = LiveEvent(events: [match("T1", status: "pre", endDate: "2026-11-23T23:59Z"), match("O1", league: .cricketODIs, daysFromNow: 5)])
        let live = LiveEvent(events: [match("T1", status: "in", home: "368", away: "159/1 (39 ov)", endDate: "2026-11-23T23:59Z"),
                                      match("I1", league: .ipl, status: "in")])
        let merged = ESPNCricketJob.mergingLive(schedule: schedule, live: live)
        XCTAssertEqual(merged?.events.compactMap(\.idEvent), ["T1", "O1", "I1"])
        XCTAssertEqual(merged?.events.first?.intAwayScore, "159/1 (39 ov)")
        XCTAssertEqual(merged?.events.first?.endDate, "2026-11-23T23:59Z", "multi-day end survives the merge")
        XCTAssertEqual(ESPNCricketJob.mergingLive(schedule: schedule, live: nil), schedule)
        XCTAssertEqual(ESPNCricketJob.mergingLive(schedule: nil, live: live), live)
    }

    func testMergeESPNIntoScheduleKeepsCricketInItsBucket() {
        let job = ESPNFetchJob()
        let schedule = LiveScore(soccer: LiveEvent(events: [TestGameFactory.make(idEvent: "S1", idLeague: "4328", strHomeTeam: "Arsenal", strAwayTeam: "Chelsea")]),
                                 cricket: LiveEvent(events: [match("T1")]))
        let live = LiveScore(cricket: LiveEvent(events: [match("T1", status: "in", home: "100/2")]))
        let merged = job.mergeESPNIntoSchedule(schedule: schedule, espn: live, resolver: TeamAliasResolver(teams: [], logger: .init(label: "test")))
        XCTAssertEqual(merged.cricket?.events.map(\.strStatus), ["in"])
        XCTAssertEqual(merged.soccer?.events.compactMap(\.idEvent), ["S1"])
    }

    func testScheduleRebuildCarriesCricket() {
        let existing = LiveEvent(events: [match("T1", status: "in")])
        XCTAssertEqual(ScheduleUpdateJob.carriedCricket(existing: existing, cached: [match("T1")]), existing)
        XCTAssertEqual(ScheduleUpdateJob.carriedCricket(existing: nil, cached: [match("T1")])?.events.count, 1,
                       "a flushed blob is re-seeded from the sweep cache")
        XCTAssertNil(ScheduleUpdateJob.carriedCricket(existing: LiveEvent(events: []), cached: nil))
    }

    func testStaleLivePruneLeavesARunningTestAlone() {
        var live = LiveScore(cricket: LiveEvent(events: [
            match("T1", status: "in", daysFromNow: -2, endDate: "2099-11-23T23:59Z"),
            match("T20", league: .ipl, status: "in", daysFromNow: -2),
        ]))
        _ = live.removeStaleLiveGames()
        XCTAssertEqual(live.cricket?.events.compactMap(\.idEvent), ["T1"])
    }

    func testCricketEndTailIsShorterThanGolfs() {
        XCTAssertEqual(Integrator.multiDayTail(for: .cricketTests), Integrator.cricketEndTail)
        XCTAssertEqual(Integrator.multiDayTail(for: .pga), Integrator.multiDayEventTail)
    }

    // MARK: - Old clients

    func testFlatRoutesExcludeCricketUnlessAskedFor() {
        let test = match("T1")
        let soccer = TestGameFactory.make(idEvent: "S1", idLeague: "4328", strHomeTeam: "Arsenal", strAwayTeam: "Chelsea")
        XCTAssertFalse(WidgetCollegeFilter().admits(test, favorites: ["New Zealand"]), "not even for a favorite")
        XCTAssertTrue(WidgetCollegeFilter().admits(soccer, favorites: []))
        XCTAssertTrue(WidgetCollegeFilter(includeCricket: true).admits(test, favorites: []))
        XCTAssertNotEqual(WidgetCollegeFilter().variantKey, WidgetCollegeFilter(includeCricket: true).variantKey)
        XCTAssertTrue(WidgetCollegeFilter(includeCricket: true).browsingAllFBS().includeCricket)
    }

    func testCricketPanelServesFutureAndRecentDaysOnly() {
        XCTAssertTrue(cricketPanelServes(20270101, now: now))
        XCTAssertTrue(cricketPanelServes(20261101, now: now))
        XCTAssertFalse(cricketPanelServes(20260901, now: now))
    }

    func testDurationsForPublicCalendar() {
        XCTAssertEqual(PublicGame.cricketDuration(.t20), 3.5 * 3600)
        XCTAssertEqual(PublicGame.cricketDuration(nil), 4 * 3600)
        let test = match("T1", endDate: "2026-11-23T23:59Z")
        XCTAssertEqual(PublicGame.endDate(test), ISO8601DateFormatter().date(from: "2026-11-23T23:59:00Z"),
                       "cricket's end is already the close of the last day")
    }
}
