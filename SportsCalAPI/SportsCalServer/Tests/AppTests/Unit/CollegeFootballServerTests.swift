import XCTest
@testable import App
import SportsCalModel

/// College football shares the football bucket with the NFL. These pin the places where
/// that sharing could leak: ESPN-ID translation, the live→schedule merge, the flat-`[Game]`
/// widget endpoint, and which calendar years make up a season.
final class CollegeFootballServerTests: XCTestCase {

    private let job = ESPNFetchJob()
    private let college = "\(Leagues.ncaaf.rawValue)"
    private let nfl = "\(Leagues.nfl.rawValue)"

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func collegeGame(id: String = "401856708", home: String = "Missouri Tigers", away: String = "Florida Gators",
                             homeID: String = "ncaaf-142", awayID: String = "ncaaf-57", homeSeed: Int? = nil, awaySeed: Int? = nil,
                             at iso: String = "2026-10-03T19:30:00Z") -> Game {
        Game(idEvent: id, idLeague: college, idHomeTeam: homeID, idAwayTeam: awayID,
             strHomeTeam: home, strAwayTeam: away, strStatus: "pre", isoDate: date(iso),
             homeSeed: homeSeed, awaySeed: awaySeed, homeConference: "sec", awayConference: "sec")
    }

    private func nflGame(id: String = "401772800", homeID: String = "2", awayID: String = "8",
                         at iso: String = "2026-10-03T19:30:00Z") -> Game {
        Game(idEvent: id, idLeague: nfl, idHomeTeam: homeID, idAwayTeam: awayID,
             strHomeTeam: "Buffalo Bills", strAwayTeam: "Detroit Lions", strStatus: "in", isoDate: date(iso))
    }

    // MARK: - ESPN ID translation

    func testCollegeGamesTranslateInTheirOwnBucket() {
        XCTAssertEqual(ESPNFetchJob.mappingBucket(for: collegeGame(), fallback: "nfl"), "ncaaf")
        XCTAssertEqual(ESPNFetchJob.mappingBucket(for: nflGame(), fallback: "nfl"), "nfl")
        let unknown = Game(idEvent: "x", idLeague: nil, strHomeTeam: "A", strAwayTeam: "B", isoDate: nil)
        XCTAssertEqual(ESPNFetchJob.mappingBucket(for: unknown, fallback: "soccer"), "soccer")
    }

    // MARK: - Live → schedule merge

    func testNFLBoardDoesNotPruneSameDayCollegeGames() {
        // The schedule's college game has an ESPN-style ID and isn't on this (NFL-only)
        // board. A board reporting the day used to prune every unmatched `401…` row on it.
        let merged = job.mergeSportEvents(
            schedule: LiveEvent(events: [collegeGame()]),
            espn: LiveEvent(events: [nflGame()]),
            resolver: TeamAliasResolver(teams: [])
        )?.events ?? []
        XCTAssertTrue(merged.contains { $0.idEvent == "401856708" })
    }

    func testCollegeAndNFLNeverMatchOnOverlappingESPNTeamIDs() {
        // Auburn is ESPN team 2 and so are the Bills: same IDs, same day, same kickoff.
        let schedule = collegeGame(home: "Auburn Tigers", away: "Arkansas Razorbacks", homeID: "2", awayID: "8")
        let merged = job.mergeSportEvents(
            schedule: LiveEvent(events: [schedule]),
            espn: LiveEvent(events: [nflGame(homeID: "2", awayID: "8")]),
            resolver: TeamAliasResolver(teams: [])
        )?.events ?? []
        let auburn = merged.first { $0.idEvent == "401856708" }
        XCTAssertEqual(auburn?.strHomeTeam, "Auburn Tigers")
        XCTAssertEqual(auburn?.strStatus, "pre", "took the NFL game's live status")
        XCTAssertEqual(auburn?.homeConference, "sec")
    }

    // MARK: - Widget endpoint opt-in

    func testWidgetFilterHidesCollegeByDefault() {
        let filter = WidgetCollegeFilter()
        XCTAssertFalse(filter.admits(collegeGame(awaySeed: 8), favorites: []))
        XCTAssertTrue(filter.admits(nflGame(), favorites: []))
    }

    private func americanGame() -> Game {
        Game(idEvent: "401862787", idLeague: college, idHomeTeam: "2429", idAwayTeam: "235",
             strHomeTeam: "Charlotte 49ers", strAwayTeam: "Memphis Tigers", strStatus: "pre",
             isoDate: date("2026-10-03T19:30:00Z"), homeConference: "american", awayConference: "american")
    }

    func testWidgetFilterAppliesSelectionWhenOptedIn() {
        let filter = WidgetCollegeFilter(includeCollege: true, selection: .default)
        XCTAssertTrue(filter.admits(collegeGame(awaySeed: 8), favorites: []))
        let unranked = americanGame()
        XCTAssertFalse(filter.admits(unranked, favorites: []))
        XCTAssertTrue(filter.admits(unranked, favorites: ["Memphis Tigers"]), "a followed team always passes")
        XCTAssertTrue(WidgetCollegeFilter(includeCollege: true, selection: .allFBS).admits(unranked, favorites: []))
        let american = CollegeFootballSelection(conferences: [.american])
        XCTAssertTrue(WidgetCollegeFilter(includeCollege: true, selection: american).admits(unranked, favorites: []))
        XCTAssertFalse(WidgetCollegeFilter(includeCollege: true, selection: american).admits(collegeGame(), favorites: []))
    }

    func testWidgetSelectionParsing() {
        XCTAssertEqual(WidgetCollegeFilter.selection(from: nil), .default)
        XCTAssertEqual(WidgetCollegeFilter.selection(from: ""), .followedOnly)
        XCTAssertEqual(WidgetCollegeFilter.selection(from: "bogus"), .default)
        XCTAssertEqual(WidgetCollegeFilter.selection(from: "top25,sec,big12"),
                       CollegeFootballSelection(top25: true, conferences: [.sec, .big12]))
    }

    func testWidgetFilterCanDropTheNFL() {
        let filter = WidgetCollegeFilter(includeCollege: true, selection: .allFBS, includeNFL: false)
        XCTAssertFalse(filter.admits(nflGame(), favorites: []))
        XCTAssertTrue(filter.admits(collegeGame(), favorites: []))
        // Only the NFL is dropped, not every other sport the request asked for.
        let nba = Game(idEvent: "n", idLeague: "4387", strHomeTeam: "A", strAwayTeam: "B", isoDate: nil)
        XCTAssertTrue(filter.admits(nba, favorites: []))
    }

    // MARK: - Season fetch years

    func testScheduleFetchesNextJanuaryFromNovember() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(ScheduleUpdateJob.collegeFootballScheduleYears(now: date("2026-10-03T12:00:00Z"), calendar: calendar), [2026])
        XCTAssertEqual(ScheduleUpdateJob.collegeFootballScheduleYears(now: date("2026-11-20T12:00:00Z"), calendar: calendar), [2026, 2027])
        XCTAssertEqual(ScheduleUpdateJob.collegeFootballScheduleYears(now: date("2027-01-05T12:00:00Z"), calendar: calendar), [2026, 2027])
        XCTAssertEqual(ScheduleUpdateJob.collegeFootballScheduleYears(now: date("2027-03-01T12:00:00Z"), calendar: calendar), [2027])
    }

    // MARK: - Opt-in payloads

    private func json(_ object: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    private func object(_ string: String) -> NSDictionary {
        try! JSONSerialization.jsonObject(with: Data(string.utf8)) as! NSDictionary
    }

    func testStripRemovesOnlyTheTopLevelCollegeKeyInAnyPosition() {
        let nested: [String: Any] = ["events": [["strHomeTeam": "ncaaf \"quoted\" {not a brace}", "ncaaf": 1]]]
        for order in [["ncaaf", "nfl", "nba"], ["nfl", "ncaaf", "nba"], ["nfl", "nba", "ncaaf"]] {
            let raw = "{" + order.map { key -> String in
                let value = key == "ncaaf" ? #"{"events":[{"a":[1,{"b":"}"}]}]}"# : json(nested)
                return #""\#(key)" : \#(value)"#
            }.joined(separator: " , ") + "}"
            let stripped = CollegePayload.strippingCollege(raw)
            let result = object(stripped)
            XCTAssertNil(result["ncaaf"], "\(order)")
            XCTAssertEqual(result["nfl"] as? NSDictionary, nested as NSDictionary)
            XCTAssertEqual(result["nba"] as? NSDictionary, nested as NSDictionary)
        }
    }

    func testStripLeavesPayloadsWithoutCollegeByteIdentical() {
        let raw = #"{"nfl":{"events":[{"strHomeTeam":"Has \"ncaaf\" in it","ncaaf":true}]},"nba":null}"#
        XCTAssertEqual(CollegePayload.strippingCollege(raw), raw)
        XCTAssertEqual(CollegePayload.strippingCollege("not json"), "not json")
        XCTAssertEqual(CollegePayload.strippingCollege(#"{"ncaaf":{}}"#), "{}")
    }

    func testStrippedLiveScoreDecodesWithNFLOnly() throws {
        let score = LiveScore(nfl: LiveEvent(events: [nflGame(), collegeGame(awaySeed: 8)]))
        let raw = String(data: try JSONEncoder().encode(score), encoding: .utf8)!
        let withCollege = try JSONDecoder().decode(LiveScore.self, from: Data(raw.utf8))
        XCTAssertEqual(withCollege.nfl?.events.count, 2)
        let stripped = CollegePayload.strippingCollege(raw)
        XCTAssertFalse(stripped.contains("ncaaf"))
        let without = try JSONDecoder().decode(LiveScore.self, from: Data(stripped.utf8))
        XCTAssertEqual(without.nfl?.events.map(\.idEvent), ["401772800"])
    }

    // MARK: - ESPN budget

    func testBudgetOrdersByTierThenLeastRecentlyFetched() {
        let power = collegeGame(id: "power")                                   // SEC, unranked
        let oneRanked = collegeGame(id: "one", awaySeed: 8)
        let bothRankedOld = collegeGame(id: "both-old", homeSeed: 25, awaySeed: 8)
        let bothRankedNew = collegeGame(id: "both-new", homeSeed: 3, awaySeed: 4)
        let american = americanGame()                                          // not featured
        let order = CollegePBPPolicy.ordered(
            [power, american, oneRanked, bothRankedNew, bothRankedOld],
            lastFetched: ["both-new": date("2026-10-03T19:00:00Z"), "both-old": date("2026-10-03T18:00:00Z")]
        )
        XCTAssertEqual(order.map(\.idEvent), ["both-old", "both-new", "one", "power"])
    }

    func testGrantFollowsPriorityAndSkipsGamesThatNeedNoFetch() {
        // Already in priority order; "b" has unchanged plays, so it costs nothing.
        let ordered = ["a", "b", "c", "d", "e"]
        let grant = CollegePBPPolicy.grant(ordered, limit: 2, needsFetch: { $0 != "b" })
        XCTAssertEqual(grant.granted, ["a", "c"])
        XCTAssertEqual(grant.deferred, 2)
        let none = CollegePBPPolicy.grant(ordered, limit: 12, needsFetch: { _ in false })
        XCTAssertEqual(none.granted, [])
        XCTAssertEqual(none.deferred, 0)
    }

    func testOnDemandFetchesForOneEventShareOneFetch() async {
        let fetches = FetchCounter()
        let fetcher = OnDemandPlayFetches()
        await withTaskGroup(of: CachedPlays?.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await fetcher.run(eventID: "401") {
                        await fetches.increment()
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        return CachedPlays(eventID: "401", lastPlayId: "", plays: [], isFinal: false, fetchedAt: Date())
                    }
                }
            }
            for await result in group { XCTAssertEqual(result?.eventID, "401") }
        }
        let count = await fetches.count
        XCTAssertEqual(count, 1)
        // Once it's done, the next caller starts a fresh fetch.
        _ = await fetcher.run(eventID: "401") { await fetches.increment(); return nil }
        let after = await fetches.count
        XCTAssertEqual(after, 2)
    }

    func testStrippedMemoReusesTheStrippedCopyAndStaysBounded() {
        let memo = StrippedMemo(capacity: 2)
        var builds = 0
        func strip(_ s: String) -> String { builds += 1; return CollegePayload.strippingCollege(s) }
        let json = #"{"nfl":{"events":[]},"ncaaf":{"events":[]}}"#
        XCTAssertEqual(memo.value(for: "a", source: json, build: strip), #"{"nfl":{"events":[]}}"#)
        _ = memo.value(for: "a", source: String(json), build: strip)
        XCTAssertEqual(builds, 1, "equal source → no second strip")
        _ = memo.value(for: "a", source: #"{"ncaaf":{"events":[]},"nba":null}"#, build: strip)
        XCTAssertEqual(builds, 2, "changed source → re-strip")
        _ = memo.value(for: "b", source: json, build: strip)
        _ = memo.value(for: "c", source: json, build: strip)
        _ = memo.value(for: "a", source: #"{"ncaaf":{"events":[]},"nba":null}"#, build: strip)
        XCTAssertEqual(builds, 5, "\"a\" was evicted at capacity 2")
    }

    func testBrowseIgnoresTheSelectionSoTheCacheStaysBounded() {
        let picky = WidgetCollegeFilter(includeCollege: true, selection: CollegeFootballSelection(conferences: [.mac]), includeNFL: true)
        let browse = picky.browsingAllFBS()
        XCTAssertEqual(browse.selection, .allFBS)
        XCTAssertEqual(browse.variantKey,
                       WidgetCollegeFilter(includeCollege: true, selection: CollegeFootballSelection(conferences: [.sec]), includeNFL: true).browsingAllFBS().variantKey)
    }

    func testPushToStartOnlyStartsCollegeGamesForInstallsThatOptedIn() throws {
        let college = collegeGame(id: "c1", homeSeed: 1, awaySeed: nil)
        let nfl = Game(idEvent: "n1", idLeague: "4391", strHomeTeam: "Buffalo Bills", strAwayTeam: "Miami Dolphins", isoDate: nil)
        let old = PushToStartInstall(installID: "i", token: "t", favorites: [], eventIDs: [], environment: .production)
        let opted = PushToStartInstall(installID: "i", token: "t", favorites: [], eventIDs: [], environment: .production, college: true)
        XCTAssertFalse(old.accepts(college))
        XCTAssertTrue(old.accepts(nfl))
        XCTAssertTrue(opted.accepts(college))
        // A record stored before the field existed decodes as "not opted in".
        let legacy = #"{"installID":"i","token":"t","favorites":["Duke Blue Devils"],"eventIDs":[],"environment":"production"}"#
        let decoded = try JSONDecoder().decode(PushToStartInstall.self, from: Data(legacy.utf8))
        XCTAssertFalse(decoded.wantsCollege)
        let registration = try JSONDecoder().decode(PushToStartRegistration.self, from: Data(#"{"token":"t","favorites":[]}"#.utf8))
        XCTAssertNil(registration.college)
    }

    func testCollegeTeamIDsAreUnwrappedForESPN() {
        XCTAssertEqual(Leagues.collegeESPNTeamID("ncaaf-57"), "57")
        XCTAssertNil(Leagues.collegeESPNTeamID("134920"))
    }

    func testOnDemandCollegeSummaryGoesStaleAfter90Seconds() {
        let now = date("2026-10-03T20:00:00Z")
        func plays(age: TimeInterval, final: Bool = false) -> CachedPlays {
            CachedPlays(eventID: "1", lastPlayId: "", plays: [], isFinal: final, fetchedAt: now.addingTimeInterval(-age))
        }
        XCTAssertFalse(CollegePBPPolicy.isStale(plays(age: 60), isCollege: true, now: now))
        XCTAssertTrue(CollegePBPPolicy.isStale(plays(age: 91), isCollege: true, now: now))
        XCTAssertFalse(CollegePBPPolicy.isStale(plays(age: 600, final: true), isCollege: true, now: now))
        XCTAssertFalse(CollegePBPPolicy.isStale(plays(age: 600), isCollege: false, now: now), "the NFL is refreshed by the job")
    }
}

private actor FetchCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
