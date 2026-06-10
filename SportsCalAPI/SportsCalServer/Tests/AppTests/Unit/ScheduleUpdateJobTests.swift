import XCTest
@testable import App
import SportsCalModel

/// Pins the pure helpers of ScheduleUpdateJob (DBUpdatejob.swift): team
/// extraction/merge, game counting, the schedule-refresh staleness decision,
/// per-league event normalization, and ESPN enrichment merging.
final class ScheduleUpdateJobTests: XCTestCase {

    private let job = ScheduleUpdateJob()

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else {
            fatalError("bad test date: \(iso)")
        }
        return date
    }

    // MARK: - extractTeamsFromGames

    func testExtractTeamsFromGames_dedupesById_skipsEmptyIDs() {
        let games = [
            TestGameFactory.make(idEvent: "1", idHomeTeam: "100", idAwayTeam: "200",
                                 strHomeTeam: "Lakers", strAwayTeam: "Celtics",
                                 isoDate: date("2024-06-01T18:00:00Z")),
            // Same home team id under a different display name — first wins
            TestGameFactory.make(idEvent: "2", idHomeTeam: "100", idAwayTeam: "300",
                                 strHomeTeam: "Los Angeles Lakers", strAwayTeam: "Suns",
                                 isoDate: date("2024-06-02T18:00:00Z")),
            // Empty ids are skipped entirely
            TestGameFactory.make(idEvent: "3", idHomeTeam: "", idAwayTeam: "",
                                 strHomeTeam: "Nobody", strAwayTeam: "NoOne",
                                 isoDate: date("2024-06-03T18:00:00Z")),
        ]

        let teams = job.extractTeamsFromGames(games)
        let byID = Dictionary(uniqueKeysWithValues: teams.compactMap { team in
            team.idTeam.map { ($0, team) }
        })

        XCTAssertEqual(teams.count, 3)
        XCTAssertEqual(byID["100"]?.strTeam, "Lakers")
        XCTAssertEqual(byID["200"]?.strTeam, "Celtics")
        XCTAssertEqual(byID["300"]?.strTeam, "Suns")
    }

    // MARK: - mergeTeams

    func testMergeTeams_apiTeamsOverrideGameTeams_gameOnlySurvive() {
        let gameTeams = [
            Team(idTeam: "100", strTeam: "Lakers", strTeamShort: nil),
            Team(idTeam: "300", strTeam: "Suns", strTeamShort: nil),
        ]
        let apiTeams = [
            Team(idTeam: "100", strTeam: "Los Angeles Lakers", strTeamShort: "LAL"),
        ]

        let merged = job.mergeTeams(apiTeams: apiTeams, gameTeams: gameTeams)
        let byID = Dictionary(uniqueKeysWithValues: merged.compactMap { team in
            team.idTeam.map { ($0, team) }
        })

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(byID["100"]?.strTeam, "Los Angeles Lakers")
        XCTAssertEqual(byID["100"]?.strTeamShort, "LAL")
        XCTAssertEqual(byID["300"]?.strTeam, "Suns")
    }

    // MARK: - countGames

    func testCountGames_sumsAllSportBuckets_ignoresNil() {
        let game = { (id: String) in
            TestGameFactory.make(idEvent: id, strHomeTeam: "A", strAwayTeam: "B",
                                 isoDate: self.date("2024-06-01T18:00:00Z"))
        }
        let score = TestGameFactory.liveScore(
            nba: [game("1"), game("2")],
            mlb: [game("3")],
            golf: [game("4")],
            racing: [game("5"), game("6"), game("7")]
        )

        XCTAssertEqual(job.countGames(in: score), 7)

        let empty = TestGameFactory.liveScore()
        XCTAssertEqual(job.countGames(in: empty), 0)
    }

    // MARK: - shouldRefreshSchedules

    func testShouldRefreshSchedules() {
        let now = date("2024-06-01T12:00:00Z")

        // No schedule cached → refresh
        XCTAssertTrue(ScheduleUpdateJob.shouldRefreshSchedules(
            hasSchedule: false, teamsCount: 10, lastUpdate: now, now: now))
        // Schedule but empty teams → refresh
        XCTAssertTrue(ScheduleUpdateJob.shouldRefreshSchedules(
            hasSchedule: true, teamsCount: 0, lastUpdate: now, now: now))
        // Fresh (30 min ago) → use cache
        XCTAssertFalse(ScheduleUpdateJob.shouldRefreshSchedules(
            hasSchedule: true, teamsCount: 10, lastUpdate: now.addingTimeInterval(-1800), now: now))
        // Stale (2 h ago) → refresh
        XCTAssertTrue(ScheduleUpdateJob.shouldRefreshSchedules(
            hasSchedule: true, teamsCount: 10, lastUpdate: now.addingTimeInterval(-7200), now: now))
        // No timestamp → refresh to set baseline
        XCTAssertTrue(ScheduleUpdateJob.shouldRefreshSchedules(
            hasSchedule: true, teamsCount: 10, lastUpdate: nil, now: now))
        // Exactly 1 h is not yet stale (strict >)
        XCTAssertFalse(ScheduleUpdateJob.shouldRefreshSchedules(
            hasSchedule: true, teamsCount: 10, lastUpdate: now.addingTimeInterval(-3600), now: now))
    }

    // MARK: - normalizeLeagueEvents

    func testNormalizeLeagueEvents_dedupesDropsNilTimestampBackfillsISODate() {
        let kept = TestGameFactory.make(
            idEvent: "E1", strHomeTeam: "A", strAwayTeam: "B",
            strTimestamp: "2024-06-01T18:00:00", isoDate: date("2024-06-01T18:00:00Z"))
        // Duplicate idEvent from an overlapping season fetch — collapsed to first
        let duplicate = TestGameFactory.make(
            idEvent: "E1", strHomeTeam: "A (dup)", strAwayTeam: "B",
            strTimestamp: "2024-06-01T18:00:00", isoDate: date("2024-06-01T18:00:00Z"))
        // No timestamp — dropped
        let noTimestamp = TestGameFactory.make(
            idEvent: "E2", strHomeTeam: "C", strAwayTeam: "D",
            strTimestamp: nil, isoDate: date("2024-06-02T18:00:00Z"))
        // Missing isoDate — backfilled from strTimestamp
        let needsBackfill = TestGameFactory.make(
            idEvent: "E3", strHomeTeam: "E", strAwayTeam: "F",
            strTimestamp: "2024-06-03T18:00:00", isoDate: nil)

        let normalized = ScheduleUpdateJob.normalizeLeagueEvents([kept, duplicate, noTimestamp, needsBackfill])
        let ids = normalized.compactMap(\.idEvent)

        XCTAssertEqual(ids, ["E1", "E3"])
        XCTAssertEqual(normalized.first(where: { $0.idEvent == "E1" })?.strHomeTeam, "A")
        XCTAssertEqual(normalized.first(where: { $0.idEvent == "E3" })?.isoDate,
                       date("2024-06-03T18:00:00Z"))
    }

    // MARK: - mergeEnrichment

    private func espnEnriched(idEvent: String, home: String, away: String,
                              homeScore: String? = "50", awayScore: String? = "48",
                              status: String? = "in", day: Date) -> Game {
        Game(
            idEvent: idEvent,
            strHomeTeam: home, strAwayTeam: away,
            intHomeScore: homeScore, intAwayScore: awayScore,
            strStatus: status,
            isoDate: day,
            venueName: "Test Arena",
            homeRecord: "30-10", awayRecord: "25-15"
        )
    }

    func testMergeEnrichment_matchesByNamesAndDay_preservesIdentity() {
        let schedule = LiveEvent(events: [TestGameFactory.make(
            idEvent: "TSDB1", strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            intHomeScore: nil, intAwayScore: nil,
            strTimestamp: "2024-06-01T18:00:00", isoDate: date("2024-06-01T18:00:00Z"))])
        let espn = LiveEvent(events: [espnEnriched(
            idEvent: "401555", home: "Lakers", away: "Celtics",
            day: date("2024-06-01T20:00:00Z"))])

        let merged = job.mergeEnrichment(schedule: schedule, espn: espn).events

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].idEvent, "TSDB1")
        XCTAssertEqual(merged[0].strTimestamp, "2024-06-01T18:00:00")
        XCTAssertEqual(merged[0].homeRecord, "30-10")
        XCTAssertEqual(merged[0].venueName, "Test Arena")
        XCTAssertEqual(merged[0].intHomeScore, "50")
    }

    func testMergeEnrichment_fallsBackToTeamIDs() {
        let schedule = LiveEvent(events: [TestGameFactory.make(
            idEvent: "TSDB1", idHomeTeam: "100", idAwayTeam: "200",
            strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            isoDate: date("2024-06-01T18:00:00Z"))])
        var espnGame = espnEnriched(
            idEvent: "401555", home: "Los Angeles Lakers", away: "Boston Celtics",
            day: date("2024-06-01T20:00:00Z"))
        espnGame = Game(
            idEvent: espnGame.idEvent, idHomeTeam: "100", idAwayTeam: "200",
            strHomeTeam: espnGame.strHomeTeam, strAwayTeam: espnGame.strAwayTeam,
            intHomeScore: espnGame.intHomeScore, intAwayScore: espnGame.intAwayScore,
            strStatus: espnGame.strStatus, isoDate: espnGame.isoDate,
            venueName: espnGame.venueName, homeRecord: espnGame.homeRecord,
            awayRecord: espnGame.awayRecord)

        let merged = job.mergeEnrichment(schedule: schedule, espn: LiveEvent(events: [espnGame])).events

        XCTAssertEqual(merged[0].idEvent, "TSDB1")
        XCTAssertEqual(merged[0].homeRecord, "30-10")
    }

    func testMergeEnrichment_fallsBackToNormalizedNames() {
        let schedule = LiveEvent(events: [TestGameFactory.make(
            idEvent: "TSDB1", strHomeTeam: "LA Clippers", strAwayTeam: "Celtics",
            isoDate: date("2024-06-01T18:00:00Z"))])
        let espn = LiveEvent(events: [espnEnriched(
            idEvent: "401555", home: "Los Angeles Clippers", away: "Celtics",
            day: date("2024-06-01T20:00:00Z"))])

        let merged = job.mergeEnrichment(schedule: schedule, espn: espn).events

        XCTAssertEqual(merged[0].idEvent, "TSDB1")
        XCTAssertEqual(merged[0].venueName, "Test Arena")
    }

    func testMergeEnrichment_preGameScoresNotClobbered() {
        let schedule = LiveEvent(events: [TestGameFactory.make(
            idEvent: "TSDB1", strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            intHomeScore: nil, intAwayScore: nil,
            isoDate: date("2024-06-01T18:00:00Z"))])
        let espn = LiveEvent(events: [espnEnriched(
            idEvent: "401555", home: "Lakers", away: "Celtics",
            homeScore: "0", awayScore: "0", status: "pre",
            day: date("2024-06-01T18:00:00Z"))])

        let merged = job.mergeEnrichment(schedule: schedule, espn: espn).events

        XCTAssertNil(merged[0].intHomeScore)
        XCTAssertNil(merged[0].intAwayScore)
        // Enrichment fields still merge for pre-game events
        XCTAssertEqual(merged[0].homeRecord, "30-10")
    }

    func testMergeEnrichment_unmatchedScheduleGamePassesThrough() {
        let schedule = LiveEvent(events: [TestGameFactory.make(
            idEvent: "TSDB1", strHomeTeam: "Suns", strAwayTeam: "Jazz",
            isoDate: date("2024-06-01T18:00:00Z"))])
        let espn = LiveEvent(events: [espnEnriched(
            idEvent: "401555", home: "Lakers", away: "Celtics",
            day: date("2024-06-01T18:00:00Z"))])

        let merged = job.mergeEnrichment(schedule: schedule, espn: espn).events

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].idEvent, "TSDB1")
        XCTAssertNil(merged[0].homeRecord)
    }
}
