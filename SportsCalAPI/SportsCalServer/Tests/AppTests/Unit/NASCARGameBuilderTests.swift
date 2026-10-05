import XCTest
import Foundation
@testable import App
import SportsCalModel

/// Builds NASCAR games from feeds recorded on 2026-10-04: the finished Kansas race
/// (5628) and Las Vegas (5630) at lap 135 of 267.
final class NASCARGameBuilderTests: XCTestCase {
    private func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Unit
            .deletingLastPathComponent()      // AppTests
            .appendingPathComponent("Fixtures/\(name)")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: fixture))
    }

    private func race(_ id: Int) throws -> NASCARRace {
        let list = try load("nascar_race_list.json", as: NASCARRaceListResponse.self)
        return try XCTUnwrap(list.series1?.first { $0.raceID == id })
    }

    private func date(_ iso: String) -> Date {
        DateParsers.parse(iso)!
    }

    // MARK: - Finished race

    func testFinishedRaceUsesOfficialResults() throws {
        let weekend = try load("nascar_weekend_final.json", as: NASCARWeekendFeed.self)
        let live = try load("nascar_live_feed.json", as: NASCARLiveFeed.self)
        let game = NASCARGameBuilder.game(race: try race(5628), weekend: weekend, live: live, now: date("2026-10-04T23:10:00Z"))

        XCTAssertEqual(game.idEvent, "nascar-5628")
        XCTAssertEqual(game.idLeague, "4393")
        XCTAssertTrue(game.isNASCAR)
        XCTAssertTrue(game.isMotorsportSeries)
        XCTAssertEqual(game.strStatus, "post")
        XCTAssertEqual(game.strProgress, "Final")
        XCTAssertEqual(game.strAwayTeam, "Kyle Larson")
        XCTAssertEqual(game.isoDate, date("2026-09-27T19:00:00Z"))
        XCTAssertEqual(game.seasonPhase, .postseason)

        let board = try XCTUnwrap(game.leaderboardEntries)
        XCTAssertEqual(board.count, 36)
        let winner = try XCTUnwrap(board.first?.stockCar)
        XCTAssertEqual(winner.carNumber, "5")
        XCTAssertEqual(winner.manufacturer, "Chevrolet")
        XCTAssertEqual(winner.lapsLed, 235)
        XCTAssertEqual(winner.startPosition, 2)
        XCTAssertEqual(board.first?.constructor, "Hendrick Motorsports")
        XCTAssertNil(board.first?.gap)
        XCTAssertEqual(board[1].gap, "+0.565", "diff_time is milliseconds")
        XCTAssertEqual(board.last?.gap, "Engine", "a car out of the race shows why")

        let raceSession = try XCTUnwrap(game.sessions?.first { $0.sessionType == "race" })
        XCTAssertEqual(raceSession.raceState?.flag, .checkered)
        XCTAssertEqual(raceSession.raceState?.lap, 267)
        XCTAssertEqual(raceSession.raceState?.cautions, 5)
        XCTAssertEqual(raceSession.raceState?.stageEndLaps, [80, 165, 267])
        XCTAssertEqual(raceSession.raceState?.broadcast, "USA")

        // Practice and qualifying were rained out and are marked so, not left upcoming.
        let canceled = game.sessions?.filter { $0.sessionType != "race" } ?? []
        XCTAssertEqual(canceled.count, 2)
        XCTAssertTrue(canceled.allSatisfy { $0.status == "post" && $0.progress == "Canceled" })
    }

    // MARK: - Live race

    func testLiveRaceUsesLiveFeed() throws {
        let weekend = try load("nascar_weekend_upcoming.json", as: NASCARWeekendFeed.self)
        let live = try load("nascar_live_feed.json", as: NASCARLiveFeed.self)
        let game = NASCARGameBuilder.game(race: try race(5630), weekend: weekend, live: live, now: date("2026-10-04T23:10:00Z"))

        XCTAssertEqual(game.strStatus, "in")
        XCTAssertEqual(game.strProgress, "Lap 135/267 · Stage 2")
        XCTAssertEqual(game.strAwayTeam, "Austin Cindric", "the (C) Chase marker is stripped")

        let board = try XCTUnwrap(game.leaderboardEntries)
        XCTAssertEqual(board.count, live.vehicles.count)
        XCTAssertEqual(board.first?.constructor, "Team Penske", "team joined from the entry list")
        XCTAssertEqual(board.first?.stockCar?.lapsLed, 5)
        XCTAssertEqual(board.first?.stockCar?.inPlayoffs, true)
        XCTAssertEqual(board[1].gap, "+1.500")
        XCTAssertTrue(board.contains { $0.gap == "+1 Lap" }, "negative delta is laps down")

        let raceSession = try XCTUnwrap(game.sessions?.first { $0.sessionType == "race" })
        XCTAssertEqual(raceSession.raceState?.stage, 2)
        XCTAssertEqual(raceSession.raceState?.stageEndLap, 165)
        XCTAssertEqual(raceSession.raceState?.flag, .green)

        // Practice and qualifying are already in the weekend feed.
        let practice = try XCTUnwrap(game.sessions?.first { $0.sessionType == "practice" })
        XCTAssertEqual(practice.status, "post")
        XCTAssertEqual(practice.leaderboard.first?.name, "William Byron")
        let qualifying = try XCTUnwrap(game.sessions?.first { $0.sessionType == "qual" })
        XCTAssertEqual(qualifying.leaderboard.first?.name, "Denny Hamlin")
    }

    func testLiveFeedForAnotherRaceIsIgnored() throws {
        let weekend = try load("nascar_weekend_upcoming.json", as: NASCARWeekendFeed.self)
        let live = try load("nascar_live_feed.json", as: NASCARLiveFeed.self)
        // Two days before Las Vegas, the feed (race 5630) must not touch race 5628's game.
        let game = NASCARGameBuilder.game(race: try race(5630), weekend: weekend, live: live, now: date("2026-10-02T12:00:00Z"))
        XCTAssertEqual(game.strStatus, "pre", "a race feed outside its race window isn't live")
        XCTAssertNil(game.strProgress)
    }

    func testRaceWithoutResultsIsOverAfterItsWindow() throws {
        let game = NASCARGameBuilder.game(race: try race(5630), weekend: nil, live: nil, now: date("2026-10-06T12:00:00Z"))
        XCTAssertEqual(game.strStatus, "post")
    }

    func testProgressDuringCaution() {
        let state = RaceState(lap: 92, totalLaps: 267, flag: .yellow, stage: 2, stageEndLap: 165, stageEndLaps: [80, 165, 267])
        XCTAssertEqual(NASCARGameBuilder.raceProgress(status: "in", state: state), "Caution · Lap 92/267")
        let last = RaceState(lap: 200, totalLaps: 267, flag: .green, stage: 3, stageEndLap: 267, stageEndLaps: [80, 165, 267])
        XCTAssertEqual(NASCARGameBuilder.raceProgress(status: "in", state: last), "Lap 200/267 · Final Stage")
    }

    // MARK: - Standings / detail

    func testStandingsMarkChaseField() throws {
        let rows = try load("nascar_points.json", as: [NASCARPointsRow].self)
        let standings = NASCARGameBuilder.standings(rows, season: 2026)
        XCTAssertEqual(standings.playoffSpots, 16)
        XCTAssertEqual(standings.drivers.first?.name, "Kyle Larson")
        XCTAssertEqual(standings.drivers[15].aboveCutLine, 1435)
        XCTAssertNil(standings.drivers[16].aboveCutLine)
        XCTAssertFalse(standings.drivers[16].inPlayoffs)
    }

    func testRaceDetail() throws {
        let detail = NASCARGameBuilder.raceDetail(
            raceID: 5628,
            weekend: try load("nascar_weekend_final.json", as: NASCARWeekendFeed.self),
            lapTimes: try load("nascar_lap_times.json", as: NASCARLapTimesFeed.self),
            notes: try load("nascar_lap_notes.json", as: NASCARLapNotesFeed.self),
            pits: try load("nascar_pit_data.json", as: [NASCARPitRecord].self)
        )
        XCTAssertEqual(detail.stages.count, 2)
        XCTAssertEqual(detail.stages.first?.finishers.first?.driver, "Kyle Larson")
        XCTAssertEqual(detail.cautions.count, 5)
        XCTAssertFalse(detail.leaders.contains { $0.endLap == 0 }, "lap 0 is pace laps, not a lead")
        XCTAssertEqual(detail.notes.count, 66)
        XCTAssertEqual(detail.notes, detail.notes.sorted { $0.lap < $1.lap })
        XCTAssertEqual(detail.notes.last?.flag, .checkered)
        XCTAssertEqual(detail.pitStops.count, 4)
        XCTAssertEqual(detail.pitStops.first { $0.carNumber == "5" }?.tires, 4)
        XCTAssertEqual(detail.lapPositions.count, 6)
        XCTAssertEqual(detail.lapPositions.first?.positions.count, 268, "lap 0 through 267")
    }

    // MARK: - Live window

    func testWeekendActiveWindow() throws {
        let vegas = try race(5630)
        XCTAssertTrue(NASCARService.isWeekendActive(vegas, now: date("2026-10-03T20:00:00Z")), "30 min before practice")
        XCTAssertTrue(NASCARService.isWeekendActive(vegas, now: date("2026-10-04T08:00:00Z")), "overnight between sessions")
        XCTAssertTrue(NASCARService.isWeekendActive(vegas, now: date("2026-10-04T23:00:00Z")), "during the race")
        XCTAssertFalse(NASCARService.isWeekendActive(vegas, now: date("2026-10-01T12:00:00Z")))
        XCTAssertFalse(NASCARService.isWeekendActive(vegas, now: date("2026-10-05T12:00:00Z")))
    }

    func testReplacingGamesSwapsByEventID() {
        let old = Game(idEvent: "nascar-1", idLeague: "4393", strHomeTeam: "Race", strAwayTeam: "A", strStatus: "pre", isoDate: nil)
        let f1 = Game(idEvent: "401", idLeague: "4370", strHomeTeam: "GP", strAwayTeam: "B", isoDate: nil)
        let new = Game(idEvent: "nascar-1", idLeague: "4393", strHomeTeam: "Race", strAwayTeam: "C", strStatus: "in", isoDate: nil)
        let added = Game(idEvent: "nascar-2", idLeague: "4393", strHomeTeam: "Race 2", strAwayTeam: "D", isoDate: nil)
        let result = ESPNFetchJob.replacingGames(in: LiveEvent(events: [old, f1]), with: [new, added])
        XCTAssertEqual(result.events.map(\.idEvent), ["nascar-1", "401", "nascar-2"])
        XCTAssertEqual(result.events.first?.strStatus, "in")
    }

    // MARK: - Old clients

    func testFlatRoutesHideNASCARWithoutOptIn() {
        let cup = Game(idEvent: "nascar-1", idLeague: "4393", strHomeTeam: "Race", strAwayTeam: "A", isoDate: nil)
        let f1 = Game(idEvent: "401", idLeague: "4370", strHomeTeam: "GP", strAwayTeam: "B", isoDate: nil)
        XCTAssertFalse(WidgetCollegeFilter().admits(cup, favorites: []))
        XCTAssertTrue(WidgetCollegeFilter().admits(f1, favorites: []))
        XCTAssertTrue(WidgetCollegeFilter(includeMotorsport: true).admits(cup, favorites: []))
    }
}
