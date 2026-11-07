//
//  RaceWeekendTests.swift
//  SportsCalModelTests
//
//  Race day vs weekend start, winner vs leader, and which session gets emphasis.
//  Session times are prod's for the 2026 São Paulo and Las Vegas weekends.
//

import XCTest
@testable import SportsCalModel

final class RaceWeekendTests: XCTestCase {

    private var pacific: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ string: String) -> Date { DateParsers.parse(string)! }

    private func weekend(_ name: String, _ sessions: [(String, String?, String)], status: String? = "pre") -> Game {
        Game(
            idEvent: name, idLeague: "\(Leagues.formula1.rawValue)",
            strHomeTeam: name, strAwayTeam: "TBD",
            strStatus: status, strTimestamp: sessions.first?.2,
            isoDate: nil,
            sessions: sessions.map { EventSession(sessionType: $0.0, sessionName: $0.0, status: $0.1, date: $0.2) }
        )
    }

    /// Saturday Nov 7: FP1/FP2 done Friday, FP3, qualifying and the race to come.
    private var saoPaulo: Game {
        weekend("São Paulo Grand Prix", [
            ("FP1", "post", "2026-11-06T15:30Z"), ("FP2", "post", "2026-11-06T19:00Z"),
            ("FP3", "pre", "2026-11-07T14:30Z"), ("Qual", "pre", "2026-11-07T18:00Z"),
            ("Race", "pre", "2026-11-08T17:00Z"),
        ])
    }

    private var lasVegas: Game {
        weekend("Las Vegas Grand Prix", [
            ("FP1", "pre", "2026-11-20T00:30Z"), ("FP2", "pre", "2026-11-20T04:00Z"),
            ("FP3", "pre", "2026-11-21T00:30Z"), ("Qual", "pre", "2026-11-21T04:00Z"),
            ("Race", "pre", "2026-11-22T04:00Z"),
        ])
    }

    private var mexico: Game {
        weekend("Mexico City Grand Prix", [
            ("FP1", "post", "2026-10-30T18:30Z"), ("FP2", "post", "2026-10-30T22:00Z"),
            ("FP3", "post", "2026-10-31T17:30Z"), ("Qual", "post", "2026-10-31T21:00Z"),
            ("Race", "post", "2026-11-01T20:00Z"),
        ], status: "post")
    }

    private let saturday = DateParsers.parse("2026-11-07T12:00Z")!   // 4 AM Pacific, Sat
    // MARK: - Next event

    func testInProgressWeekendIsTheNextEvent() {
        let next = Game.nextEvent(in: [mexico, lasVegas, saoPaulo], now: saturday, calendar: pacific)
        XCTAssertEqual(next?.idEvent, "São Paulo Grand Prix")
    }

    func testAfterTheRaceTheNextWeekendIsNext() {
        let raced = weekend("São Paulo Grand Prix", [
            ("Qual", "post", "2026-11-07T18:00Z"), ("Race", "post", "2026-11-08T17:00Z"),
        ])
        let monday = date("2026-11-09T18:00Z")
        XCTAssertEqual(Game.nextEvent(in: [raced, lasVegas], now: monday, calendar: pacific)?.idEvent, "Las Vegas Grand Prix")
    }

    func testFinishedRaceEarlierTodayIsNotNext() {
        let raced = weekend("São Paulo Grand Prix", [("Race", "post", "2026-11-08T17:00Z")])
        let sundayEvening = date("2026-11-09T02:00Z")
        XCTAssertEqual(Game.nextEvent(in: [raced, lasVegas], now: sundayEvening, calendar: pacific)?.idEvent, "Las Vegas Grand Prix")
    }

    func testSummaryDateIsRaceDay() {
        XCTAssertEqual(saoPaulo.summaryDate, date("2026-11-08T17:00Z"))
        XCTAssertEqual(saoPaulo.raceStartDate, date("2026-11-08T17:00Z"))
    }

    // MARK: - In progress

    func testWeekendInProgress() {
        XCTAssertTrue(saoPaulo.isRaceWeekendInProgress(now: saturday, calendar: pacific))
        XCTAssertFalse(lasVegas.isRaceWeekendInProgress(now: saturday, calendar: pacific))
        XCTAssertFalse(mexico.isRaceWeekendInProgress(now: saturday, calendar: pacific))
    }

    func testWeekendStartingTodayIsInProgress() {
        // Thursday Nov 19, Pacific: Las Vegas FP1 is tonight (00:30Z Fri).
        let thursday = date("2026-11-19T20:00Z")
        XCTAssertTrue(lasVegas.isRaceWeekendInProgress(now: thursday, calendar: pacific))
    }

    // MARK: - Focused session

    func testFutureWeekendHighlightsNothing() {
        XCTAssertNil(lasVegas.focusedRaceSession(now: saturday, calendar: pacific))
    }

    func testCurrentWeekendHighlightsTheNextSession() {
        XCTAssertEqual(saoPaulo.focusedRaceSession(now: saturday, calendar: pacific)?.sessionType, "FP3")
    }

    func testLiveSessionIsAlwaysHighlighted() {
        let live = weekend("São Paulo Grand Prix", [
            ("FP3", "in", "2026-11-07T14:30Z"), ("Race", "pre", "2026-11-08T17:00Z"),
        ])
        XCTAssertEqual(live.focusedRaceSession(now: saturday, calendar: pacific)?.sessionType, "FP3")
    }

    func testFinishedWeekendHighlightsNothing() {
        XCTAssertNil(mexico.focusedRaceSession(now: saturday, calendar: pacific))
    }

    // MARK: - Winner vs leader

    func testFinishedRaceHasAWinner() {
        XCTAssertTrue(mexico.isRaceFinished)
        XCTAssertEqual(mexico.raceTopLabel, "Winner")
    }

    func testFinishedQualifyingIsStillALeader() {
        let afterQualifying = weekend("São Paulo Grand Prix", [
            ("Qual", "post", "2026-11-07T18:00Z"), ("Race", "pre", "2026-11-08T17:00Z"),
        ])
        XCTAssertFalse(afterQualifying.isRaceFinished)
        XCTAssertEqual(afterQualifying.raceTopLabel, "Leader")
        XCTAssertEqual(saoPaulo.raceTopLabel, "Leader")
    }

    func testRaceWithoutSessionsUsesTheGameStatus() {
        let done = Game(idLeague: "\(Leagues.formula1.rawValue)", strHomeTeam: "GP", strAwayTeam: "TBD",
                        strStatus: "post", isCompleted: true, isoDate: nil)
        XCTAssertEqual(done.raceTopLabel, "Winner")
        let running = Game(idLeague: "\(Leagues.formula1.rawValue)", strHomeTeam: "GP", strAwayTeam: "TBD",
                           strStatus: "in", isoDate: nil)
        XCTAssertEqual(running.raceTopLabel, "Leader")
    }

    func testRaceStartDateIsTheRaceNotFP1() {
        XCTAssertEqual(mexico.raceStartDate, date("2026-11-01T20:00Z"))
        XCTAssertNotEqual(mexico.raceStartDate, mexico.isoDate)
    }
}
