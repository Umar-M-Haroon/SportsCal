//
//  GridironBaseballTests.swift
//  SportsCalModelTests
//
//  Baseball pitchers / doubleheaders / play grouping and football drives / weeks,
//  against trimmed real ESPN payloads (2025-07-26 CLE @ KC doubleheader, the PHI @ NYY
//  summary from the same day, and 2025 NFL week 7 LAR @ JAX).
//

import XCTest
@testable import SportsCalModel

final class GridironBaseballTests: XCTestCase {

    private func doubleheader() throws -> [Game] {
        let board = try XCTUnwrap(JSONLoader.load(file: "MLBDoubleheaderScoreboard", type: Scoreboard.self) as? Scoreboard)
        return try XCTUnwrap(LiveEvent(events: board, league: .mlb)?.events)
    }

    // MARK: Scoreboard extras

    func testFeaturedPitchersReadRecordsByName() throws {
        let game = try XCTUnwrap(try doubleheader().first)
        let pitchers = try XCTUnwrap(game.featuredPitchers)
        let win = try XCTUnwrap(pitchers.first { $0.role == .win })
        let loss = try XCTUnwrap(pitchers.first { $0.role == .loss })
        // ESPN's stats lead with saves; the line must be W-L, not "(0)".
        XCTAssertTrue(win.line?.range(of: #"^\(\d+-\d+\)$"#, options: .regularExpression) != nil, win.line ?? "nil")
        XCTAssertTrue(loss.line?.range(of: #"^\(\d+-\d+\)$"#, options: .regularExpression) != nil, loss.line ?? "nil")
        XCTAssertNotNil(win.side)
        XCTAssertNotEqual(win.side, loss.side)
    }

    func testProbableRecordDropsParentheses() {
        XCTAssertEqual(ProbablePitcher.seasonLine(record: "(9-5, 4.17)", statistics: nil), "9-5, 4.17 ERA")
        XCTAssertEqual(ProbablePitcher.seasonLine(record: nil, statistics: nil), nil)
    }

    func testDoubleheaderGameNumbersFromNotes() throws {
        let games = try doubleheader()
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(Set(games.compactMap(\.doubleheaderGame)), [1, 2])
        XCTAssertEqual(ScoreboardExtras.doubleheaderGame(notes: [CompetitionNote(text: nil, headline: "MLB Speedway Classic", type: "event")]), nil)
    }

    func testHitsAndErrorsDecoded() throws {
        let game = try XCTUnwrap(try doubleheader().first)
        XCTAssertNotNil(game.homeHits)
        XCTAssertNotNil(game.awayErrors)
    }

    // MARK: Baseball play-by-play

    private func pitchSummary() throws -> ESPNSummaryResponse {
        try XCTUnwrap(JSONLoader.load(file: "MLBPitchSummary", type: ESPNSummaryResponse.self) as? ESPNSummaryResponse)
    }

    func testBaseballPlaysFoldIntoHalfInnings() throws {
        let plays = try pitchSummary().allPlays
        let halves = plays.baseballHalfInnings()
        XCTAssertEqual(halves.map(\.id), ["1-top", "1-bottom"])
        let results = halves.flatMap(\.atBats)
        XCTAssertTrue(results.allSatisfy { !($0.result.text ?? "").isEmpty })
        XCTAssertFalse(results.contains { $0.result.isPitch })
        // Turner's leadoff double came on the seventh pitch.
        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.result.text, "Turner hit a ground rule double.")
        XCTAssertEqual(first.pitches.count, 7)
        XCTAssertLessThan(plays.displayedPlayCount(isBaseball: true), plays.count / 3)
    }

    func testUntaggedBaseballPlaysStillGroup() {
        let plays = [
            Play(id: "1", text: "Top of the 1st", period: .init(number: 1, type: "Top")),
            Play(id: "2", text: nil, period: .init(number: 1, type: "Top")),
            Play(id: "3", text: "Judge homered", period: .init(number: 1, type: "Bottom")),
        ]
        XCTAssertEqual(plays.baseballHalfInnings().map { $0.atBats.count }, [1, 1])
    }

    func testCurrentSeriesContext() throws {
        let series = try XCTUnwrap(pitchSummary().currentSeries)
        XCTAssertEqual(series.gameNumber, 2)
        XCTAssertEqual(series.totalGames, 3)
        XCTAssertEqual(series.displayText, "Game 2 of 3 · PHI wins series 2-1")
    }

    // MARK: Football

    func testDriveHeadersSplitPlays() throws {
        let summary = try XCTUnwrap(JSONLoader.load(file: "NFLDrivesSummary", type: ESPNSummaryResponse.self) as? ESPNSummaryResponse)
        let drives = try XCTUnwrap(summary.drives?.summaries)
        XCTAssertEqual(drives.count, 3)
        XCTAssertEqual(drives[0].team, "JAX")
        XCTAssertEqual(drives[0].result, "Punt")
        XCTAssertEqual(drives[1].isScore, true)
        let groups = summary.allPlays.groupedIntoDrives(drives)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map(\.plays.count), summary.drives?.previous?.map { $0.plays?.count ?? 0 })
        let extras = summary.extras(league: .nfl, isFinal: false)
        XCTAssertEqual(extras.drives?.count, 3)
    }

    func testFootballWeekEncodedOnlyForFootball() throws {
        let nfl = Game(idLeague: "\(Leagues.nfl.rawValue)", strHomeTeam: "A", strAwayTeam: "B", isoDate: nil, sportsDBRound: 7)
        let nba = Game(idLeague: "\(Leagues.nba.rawValue)", strHomeTeam: "A", strAwayTeam: "B", isoDate: nil, sportsDBRound: 7)
        let nflJSON = try XCTUnwrap(String(data: JSONEncoder().encode(nfl), encoding: .utf8))
        let nbaJSON = try XCTUnwrap(String(data: JSONEncoder().encode(nba), encoding: .utf8))
        XCTAssertTrue(nflJSON.contains("\"intRound\":7"))
        XCTAssertFalse(nbaJSON.contains("intRound"))
        let decoded = try JSONDecoder().decode(Game.self, from: Data(nflJSON.utf8))
        XCTAssertEqual(decoded.footballWeek, 7)
        let playoff = Game(idLeague: "\(Leagues.nfl.rawValue)", strHomeTeam: "A", strAwayTeam: "B", isoDate: nil, seasonPhase: .postseason, sportsDBRound: 160)
        XCTAssertNil(playoff.footballWeek)
    }

    func testLiveActivityCarriesTimeouts() {
        let situation = GameSituation(down: 3, distance: 4, possession: .home, homeTimeouts: 2, awayTimeouts: 3)
        let la = LiveActivitySituation(situation)
        XCTAssertEqual(la?.homeTimeouts, 2)
        XCTAssertEqual(la?.awayTimeouts, 3)
    }
}
