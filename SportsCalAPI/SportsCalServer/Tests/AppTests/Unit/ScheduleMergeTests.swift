import XCTest
@testable import App
import SportsCalModel

/// Pins the ESPN→TheSportsDB schedule-merge matcher in ESPNFetchJob: the
/// match-key fallback chain (IDs → names → normalized names → alias canonical
/// key → event name), the pre-game score guard, stale-`401…` pruning, and
/// ESPN-only append dedup.
final class ScheduleMergeTests: XCTestCase {

    private let job = ESPNFetchJob()
    private let emptyResolver = TeamAliasResolver(teams: [])

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else {
            fatalError("bad test date: \(iso)")
        }
        return date
    }

    private func merge(schedule: [Game], espn: [Game], resolver: TeamAliasResolver? = nil) -> [Game] {
        let merged = job.mergeSportEvents(
            schedule: LiveEvent(events: schedule),
            espn: LiveEvent(events: espn),
            resolver: resolver ?? emptyResolver
        )
        return merged?.events ?? []
    }

    // MARK: - Match fallback chain

    func testMatchByTeamIDsAndDay_mergesDynamicFieldsPreservesIdentity() {
        let schedule = TestGameFactory.make(
            idEvent: "TSDB1", idHomeTeam: "134860", idAwayTeam: "134861",
            strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            intHomeScore: nil, intAwayScore: nil,
            strTimestamp: "2024-06-01T18:00:00",
            isoDate: date("2024-06-01T18:00:00Z")
        )
        // Same kickoff as the schedule entry. TheSportsDB and ESPN agree on scheduled
        // start time to the minute in practice (measured across La Liga and MLB fixtures:
        // zero drift), so the two sides of a real fixture always land well inside
        // `sameFixtureWindow`. See `testSameTeamsBeyondFixtureWindowDoNotMatch` for the
        // doubleheader case this window exists to separate.
        let espn = TestGameFactory.make(
            idEvent: "401555", idHomeTeam: "134860", idAwayTeam: "134861",
            strHomeTeam: "Los Angeles Lakers", strAwayTeam: "Boston Celtics",
            intHomeScore: "102", intAwayScore: "99",
            strStatus: "in", strProgress: "Q4 2:00",
            isoDate: date("2024-06-01T18:00:00Z")
        )

        let merged = merge(schedule: [schedule], espn: [espn])

        XCTAssertEqual(merged.count, 1)
        let game = merged[0]
        // Schedule identity preserved
        XCTAssertEqual(game.idEvent, "TSDB1")
        XCTAssertEqual(game.strTimestamp, "2024-06-01T18:00:00")
        XCTAssertEqual(game.isoDate, date("2024-06-01T18:00:00Z"))
        // ESPN dynamic fields merged
        XCTAssertEqual(game.intHomeScore, "102")
        XCTAssertEqual(game.intAwayScore, "99")
        XCTAssertEqual(game.strStatus, "in")
        XCTAssertEqual(game.strProgress, "Q4 2:00")
    }

    /// The other half of the `sameFixtureWindow` contract: the same two teams meeting
    /// twice on one UTC day (doubleheader, or an evening game that crosses UTC midnight
    /// into the next afternoon's date) must NOT be collapsed onto each other — that is
    /// what made finished results appear on games that hadn't started yet.
    func testSameTeamsBeyondFixtureWindowDoNotMatch() {
        let schedule = TestGameFactory.make(
            idEvent: "TSDB1", idHomeTeam: "134860", idAwayTeam: "134861",
            strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            intHomeScore: nil, intAwayScore: nil,
            strTimestamp: "2024-06-01T23:00:00",
            isoDate: date("2024-06-01T23:00:00Z")
        )
        // Same teams, same UTC day, but the afternoon game — 8h earlier, well outside
        // the window. Its final score must not be overlaid on the evening fixture.
        let espn = TestGameFactory.make(
            idEvent: "401555", idHomeTeam: "134860", idAwayTeam: "134861",
            strHomeTeam: "Los Angeles Lakers", strAwayTeam: "Boston Celtics",
            intHomeScore: "102", intAwayScore: "99",
            strStatus: "post", strProgress: "Final",
            isoDate: date("2024-06-01T15:00:00Z")
        )

        let merged = merge(schedule: [schedule], espn: [espn])

        let evening = merged.first { $0.idEvent == "TSDB1" }
        XCTAssertNotNil(evening, "the scheduled game must survive the merge")
        XCTAssertNil(evening?.intHomeScore, "the earlier game's score must not leak onto it")
        XCTAssertNotEqual(evening?.strStatus, "post", "an unplayed game must not be marked final")
    }

    func testPreGameESPNScoresDoNotClobberSchedule() {
        let schedule = TestGameFactory.make(
            idEvent: "TSDB1", idHomeTeam: "1", idAwayTeam: "2",
            strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            intHomeScore: nil, intAwayScore: nil,
            isoDate: date("2024-06-01T18:00:00Z")
        )
        let espn = TestGameFactory.make(
            idEvent: "401555", idHomeTeam: "1", idAwayTeam: "2",
            strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            intHomeScore: "0", intAwayScore: "0",
            strStatus: "pre",
            isoDate: date("2024-06-01T18:00:00Z")
        )

        let merged = merge(schedule: [schedule], espn: [espn])

        // ESPN's "0" placeholder scores must not replace nil pre-game scores —
        // the client shows a score view instead of the start time otherwise.
        XCTAssertNil(merged[0].intHomeScore)
        XCTAssertNil(merged[0].intAwayScore)
        XCTAssertEqual(merged[0].strStatus, "pre")
    }

    func testMatchByTeamNamesAndDay_whenIDsMissing() {
        let schedule = TestGameFactory.make(
            idEvent: "TSDB1",
            strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            isoDate: date("2024-06-01T18:00:00Z")
        )
        let espn = TestGameFactory.make(
            idEvent: "401555",
            strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            intHomeScore: "55", intAwayScore: "60", strStatus: "in",
            isoDate: date("2024-06-01T20:00:00Z")
        )

        let merged = merge(schedule: [schedule], espn: [espn])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].idEvent, "TSDB1")
        XCTAssertEqual(merged[0].intHomeScore, "55")
    }

    func testMatchByNormalizedNames_cityAbbreviationAndFCSuffix() {
        let schedule = [
            TestGameFactory.make(
                idEvent: "TSDB1",
                strHomeTeam: "LA Clippers", strAwayTeam: "Celtics",
                isoDate: date("2024-06-01T18:00:00Z")
            ),
            TestGameFactory.make(
                idEvent: "TSDB2", idLeague: "4328",
                strHomeTeam: "Barcelona FC", strAwayTeam: "Sevilla",
                isoDate: date("2024-06-02T18:00:00Z")
            ),
        ]
        let espn = [
            TestGameFactory.make(
                idEvent: "401001",
                strHomeTeam: "Los Angeles Clippers", strAwayTeam: "Celtics",
                intHomeScore: "70", intAwayScore: "65", strStatus: "in",
                isoDate: date("2024-06-01T20:00:00Z")
            ),
            TestGameFactory.make(
                idEvent: "401002", idLeague: "4328",
                strHomeTeam: "FC Barcelona", strAwayTeam: "Sevilla",
                intHomeScore: "2", intAwayScore: "1", strStatus: "in",
                isoDate: date("2024-06-02T19:00:00Z")
            ),
        ]

        let merged = merge(schedule: schedule, espn: espn)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first(where: { $0.idEvent == "TSDB1" })?.intHomeScore, "70")
        XCTAssertEqual(merged.first(where: { $0.idEvent == "TSDB2" })?.intHomeScore, "2")
    }

    func testMatchByAliasCanonicalKey() {
        // Resolver knows "Paris Saint-Germain" (team cache) and the curated
        // seed maps "psg" → that strTeam, so the two name variants collapse.
        let resolver = TeamAliasResolver(teams: [
            Team(idTeam: "133714", strTeam: "Paris Saint-Germain")
        ])
        let schedule = TestGameFactory.make(
            idEvent: "TSDB1", idLeague: "4334",
            strHomeTeam: "Paris Saint-Germain", strAwayTeam: "Lyon",
            isoDate: date("2024-06-01T18:00:00Z")
        )
        let espn = TestGameFactory.make(
            idEvent: "401003", idLeague: "4334",
            strHomeTeam: "PSG", strAwayTeam: "Lyon",
            intHomeScore: "3", intAwayScore: "0", strStatus: "in",
            isoDate: date("2024-06-01T19:00:00Z")
        )

        let merged = merge(schedule: [schedule], espn: [espn], resolver: resolver)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].idEvent, "TSDB1")
        XCTAssertEqual(merged[0].intHomeScore, "3")
    }

    func testGolfMatchesByEventNameAcrossDays() {
        // Golf carries the tournament name in strHomeTeam; the event-name path
        // has no day component, so a multi-day tournament still matches.
        let schedule = TestGameFactory.make(
            idEvent: "TSDB1", idLeague: "4425",
            strHomeTeam: "RBC Heritage", strAwayTeam: "TBD",
            isoDate: date("2024-06-01T12:00:00Z")
        )
        let espn = TestGameFactory.make(
            idEvent: "401004", idLeague: "4425",
            strHomeTeam: "RBC Heritage", strAwayTeam: "S. Scheffler",
            strStatus: "in",
            isoDate: date("2024-06-03T12:00:00Z")
        )

        let merged = merge(schedule: [schedule], espn: [espn])

        // One merged entry (matched), not schedule + appended ESPN duplicate
        XCTAssertEqual(merged.filter { $0.idEvent == "TSDB1" }.count, 1)
        XCTAssertEqual(merged.first(where: { $0.idEvent == "TSDB1" })?.strStatus, "in")
        XCTAssertEqual(merged.first(where: { $0.idEvent == "TSDB1" })?.strAwayTeam, "S. Scheffler")
    }

    func testTennisMatchDoesNotMatchByEventName() {
        // Regression: keying tennis head-to-heads by home player name (no day)
        // bled one live match's score across every schedule game of that player.
        let schedule = TestGameFactory.make(
            idEvent: "TSDB1", idLeague: "4464", idHomeTeam: "p1", idAwayTeam: "p2",
            strHomeTeam: "N. Djokovic", strAwayTeam: "R. Nadal",
            intHomeScore: nil, intAwayScore: nil,
            isoDate: date("2024-06-05T12:00:00Z")
        )
        // Same players, live on a DIFFERENT day — must not contaminate the schedule game.
        let espn = TestGameFactory.make(
            idEvent: "401005", idLeague: "4464", idHomeTeam: "p1", idAwayTeam: "p3",
            strHomeTeam: "N. Djokovic", strAwayTeam: "C. Alcaraz",
            intHomeScore: "2", intAwayScore: "1", strStatus: "in",
            isoDate: date("2024-06-01T12:00:00Z")
        )

        let merged = merge(schedule: [schedule], espn: [espn])

        let scheduleGame = merged.first(where: { $0.idEvent == "TSDB1" })
        XCTAssertNotNil(scheduleGame)
        XCTAssertNil(scheduleGame?.intHomeScore)
        XCTAssertEqual(scheduleGame?.strStatus, "pre")
    }

    // MARK: - Stale prune

    func testStaleESPNGamePrunedOnlyOnESPNReportedDays() {
        let reportedDay = date("2024-06-01T18:00:00Z")
        let unreportedDay = date("2024-06-02T18:00:00Z")
        let schedule = [
            // ESPN-style id on a day ESPN reported, but absent from the feed → stale, pruned
            TestGameFactory.make(idEvent: "401999", strHomeTeam: "Hawks", strAwayTeam: "Heat", isoDate: reportedDay),
            // Same shape on a day ESPN did NOT report → kept
            TestGameFactory.make(idEvent: "401888", strHomeTeam: "Bulls", strAwayTeam: "Knicks", isoDate: unreportedDay),
            // TSDB id on a reported day, unmatched → kept
            TestGameFactory.make(idEvent: "TSDB1", strHomeTeam: "Suns", strAwayTeam: "Jazz", isoDate: reportedDay),
        ]
        let espn = [
            TestGameFactory.make(idEvent: "401555", strHomeTeam: "Lakers", strAwayTeam: "Celtics", isoDate: reportedDay)
        ]

        let merged = merge(schedule: schedule, espn: espn)
        let ids = Set(merged.compactMap(\.idEvent))

        XCTAssertFalse(ids.contains("401999"))
        XCTAssertTrue(ids.contains("401888"))
        XCTAssertTrue(ids.contains("TSDB1"))
        XCTAssertTrue(ids.contains("401555")) // unmatched ESPN game appended
    }

    // MARK: - ESPN-only append + dedup

    func testUnmatchedESPNGameAppended() {
        let schedule = TestGameFactory.make(
            idEvent: "TSDB1", strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            isoDate: date("2024-06-01T18:00:00Z")
        )
        let espn = TestGameFactory.make(
            idEvent: "401777", strHomeTeam: "Warriors", strAwayTeam: "Nuggets",
            isoDate: date("2024-06-01T20:00:00Z")
        )

        let merged = merge(schedule: [schedule], espn: [espn])

        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains(where: { $0.idEvent == "401777" }))
    }

    func testUnmatchedESPNGameDroppedWhenScheduleHasSwappedHomeAway() {
        // Merge matching is order-sensitive, but append dedup indexes both
        // orders — a home/away swap must not produce a duplicate row.
        let schedule = TestGameFactory.make(
            idEvent: "TSDB1", strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            isoDate: date("2024-06-01T18:00:00Z")
        )
        let espn = TestGameFactory.make(
            idEvent: "401777", strHomeTeam: "Celtics", strAwayTeam: "Lakers",
            isoDate: date("2024-06-01T18:00:00Z")
        )

        let merged = merge(schedule: [schedule], espn: [espn])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].idEvent, "TSDB1")
    }

    func testUnmatchedESPNAliasDuplicateDroppedByCanonicalKey() {
        let resolver = TeamAliasResolver(teams: [
            Team(idTeam: "133714", strTeam: "Paris Saint-Germain")
        ])
        let schedule = TestGameFactory.make(
            idEvent: "TSDB1", idLeague: "4334",
            strHomeTeam: "Paris Saint-Germain", strAwayTeam: "Lyon",
            isoDate: date("2024-06-01T18:00:00Z")
        )
        // ESPN carries the same fixture twice under different aliases: the
        // exact-name row matches the schedule; the "PSG" row goes unmatched and
        // only the alias canonical key keeps it from appending as a duplicate.
        let espnExact = TestGameFactory.make(
            idEvent: "401771", idLeague: "4334",
            strHomeTeam: "Paris Saint-Germain", strAwayTeam: "Lyon",
            intHomeScore: "2", intAwayScore: "0", strStatus: "in",
            isoDate: date("2024-06-01T18:00:00Z")
        )
        let espnAlias = TestGameFactory.make(
            idEvent: "401772", idLeague: "4334",
            strHomeTeam: "PSG", strAwayTeam: "Lyon",
            isoDate: date("2024-06-01T18:00:00Z")
        )

        let merged = merge(schedule: [schedule], espn: [espnExact, espnAlias], resolver: resolver)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].idEvent, "TSDB1")
        XCTAssertEqual(merged[0].intHomeScore, "2")
    }

    // MARK: - Tennis identity stickiness

    func testMergePreservesScheduleTournamentNameAndRound() {
        let schedule = TestGameFactory.make(
            idEvent: "TSDB1", idLeague: "4464", idHomeTeam: "p1", idAwayTeam: "p2",
            strHomeTeam: "N. Djokovic", strAwayTeam: "C. Alcaraz",
            isoDate: date("2024-06-01T12:00:00Z"),
            tournamentName: "Wimbledon", round: "Quarterfinal"
        )
        let espn = TestGameFactory.make(
            idEvent: "401006", idLeague: "4464", idHomeTeam: "p1", idAwayTeam: "p2",
            strHomeTeam: "N. Djokovic", strAwayTeam: "C. Alcaraz",
            intHomeScore: "1", intAwayScore: "1", strStatus: "in",
            isoDate: date("2024-06-01T13:00:00Z")
        )

        let merged = merge(schedule: [schedule], espn: [espn])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].tournamentName, "Wimbledon")
        XCTAssertEqual(merged[0].round, "Quarterfinal")
        XCTAssertEqual(merged[0].strStatus, "in")
    }

    // MARK: - Nil-side handling

    func testNilScheduleReturnsESPN_andEmptyESPNReturnsSchedule() {
        let espnOnly = job.mergeSportEvents(
            schedule: nil,
            espn: LiveEvent(events: [TestGameFactory.make(idEvent: "4011", strHomeTeam: "A", strAwayTeam: "B", isoDate: date("2024-06-01T18:00:00Z"))]),
            resolver: emptyResolver
        )
        XCTAssertEqual(espnOnly?.events.first?.idEvent, "4011")

        let scheduleEvents = LiveEvent(events: [TestGameFactory.make(idEvent: "TSDB1", strHomeTeam: "A", strAwayTeam: "B", isoDate: date("2024-06-01T18:00:00Z"))])
        let scheduleOnly = job.mergeSportEvents(schedule: scheduleEvents, espn: LiveEvent(events: []), resolver: emptyResolver)
        XCTAssertEqual(scheduleOnly?.events.first?.idEvent, "TSDB1")
    }

    // MARK: - dayString

    func testDayStringPrefersISODateThenTimestampPrefixThenEmpty() {
        let withISO = TestGameFactory.make(idEvent: "1", strHomeTeam: "A", strAwayTeam: "B", isoDate: date("2024-06-01T23:30:00Z"))
        XCTAssertEqual(job.dayString(from: withISO), "2024-06-01")

        let withTimestamp = TestGameFactory.make(idEvent: "2", strHomeTeam: "A", strAwayTeam: "B", strTimestamp: "2024-07-04T18:00:00", isoDate: nil)
        XCTAssertEqual(job.dayString(from: withTimestamp), "2024-07-04")

        let withNeither = TestGameFactory.make(idEvent: "3", strHomeTeam: "A", strAwayTeam: "B", isoDate: nil)
        XCTAssertEqual(job.dayString(from: withNeither), "")
    }

    // MARK: - returnUpdatedEvents

    func testReturnUpdatedEventsMergesScoresOnNameMatchAndPassesThroughUnmatched() {
        let scheduled = TestGameFactory.make(
            idEvent: "TSDB1", strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            intHomeScore: nil, intAwayScore: nil,
            strTimestamp: "2024-06-01T18:00:00", isoDate: date("2024-06-01T18:00:00Z")
        )
        let espnMatched = TestGameFactory.make(
            idEvent: "401555", strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            intHomeScore: "88", intAwayScore: "90", strStatus: "in",
            isoDate: date("2024-06-01T20:00:00Z")
        )
        let espnUnmatched = TestGameFactory.make(
            idEvent: "401556", strHomeTeam: "Suns", strAwayTeam: "Jazz",
            isoDate: date("2024-06-01T20:00:00Z")
        )

        let result = job.returnUpdatedEvents(events: [scheduled], espnEvents: [espnMatched, espnUnmatched])

        XCTAssertEqual(result.events.count, 2)
        let matched = result.events.first(where: { $0.idEvent == "TSDB1" })
        XCTAssertEqual(matched?.intHomeScore, "88")
        XCTAssertEqual(matched?.strStatus, "in")
        XCTAssertTrue(result.events.contains(where: { $0.idEvent == "401556" }))
    }
}
