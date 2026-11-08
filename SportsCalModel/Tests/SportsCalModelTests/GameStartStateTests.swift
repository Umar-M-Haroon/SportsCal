//
//  GameStartStateTests.swift
//  SportsCalModelTests
//
//  College football abbreviations, pre-game "0–0" scores and TBD kickoff times.
//

import XCTest
@testable import SportsCalModel

final class GameStartStateTests: XCTestCase {

    /// ESPN's FBS board for Nov 7/14 2026: BYU at Utah (noon ET, pre), Baylor at BYU
    /// (`timeValid: false`, parked at 05:00Z), FSU at Boston College (pre).
    private func pregameGames() throws -> [Game] {
        let board = try XCTUnwrap(JSONLoader.load(file: "CollegeFootballPregameScoreboard", type: Scoreboard.self) as? Scoreboard)
        return try XCTUnwrap(LiveEvent(events: board, league: .ncaaf)).events
    }

    private func game(home: String, in games: [Game]) throws -> Game {
        try XCTUnwrap(games.first { $0.strHomeTeam == home })
    }

    // MARK: - Abbreviations

    func testCollegeGamesCarryESPNAbbreviations() throws {
        let games = try pregameGames()
        let utah = try game(home: "Utah Utes", in: games)
        XCTAssertEqual(utah.homeAbbreviation, "UTAH")
        XCTAssertEqual(utah.awayAbbreviation, "BYU")
        XCTAssertEqual(utah.teamCode(home: true), "UTAH")
        XCTAssertEqual(utah.teamCode(home: false), "BYU")
        let bc = try game(home: "Boston College Eagles", in: games)
        XCTAssertEqual(bc.teamCode(home: true), "BC")
        XCTAssertEqual(bc.teamCode(home: false), "FSU")
    }

    func testAbbreviationsSurviveTheWire() throws {
        let utah = try game(home: "Utah Utes", in: try pregameGames())
        let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(utah))
        XCTAssertEqual(decoded.homeAbbreviation, "UTAH")
        XCTAssertEqual(decoded.awayAbbreviation, "BYU")
    }

    func testProLeaguesDoNotShipAbbreviations() throws {
        let board = try XCTUnwrap(JSONLoader.load(file: "NFLScoreboard", type: Scoreboard.self) as? Scoreboard)
        let games = try XCTUnwrap(LiveEvent(events: board, league: .nfl)).events
        XCTAssertFalse(games.isEmpty)
        XCTAssertTrue(games.allSatisfy { $0.homeAbbreviation == nil && $0.awayAbbreviation == nil })
    }

    func testOldServerCollegeFallbackUsesTheLeadingCode() {
        // An older server sends no abbreviation: never build "BCO"/"UBR" from the mascot.
        let byu = Game(idLeague: "102", strHomeTeam: "BYU Cougars", strAwayTeam: "UCLA Bruins", isoDate: nil)
        XCTAssertEqual(byu.teamCode(home: true), "BYU")
        XCTAssertEqual(byu.teamCode(home: false), "UCLA")
        let tamu = Game(idLeague: "102", strHomeTeam: "Utah Utes", strAwayTeam: "TCU Horned Frogs", isoDate: nil)
        XCTAssertEqual(tamu.teamCode(home: false), "TCU")
        // No leading code: the generic fallback.
        XCTAssertEqual(tamu.teamCode(home: true), Team.shortCode(strTeamShort: nil, name: "Utah Utes"))
        // Pro games keep the existing derivation.
        let nba = Game(idLeague: "4387", strHomeTeam: "New York Knicks", strAwayTeam: "LA Clippers", isoDate: nil)
        XCTAssertEqual(nba.teamCode(home: true), "NYK")
    }

    func testShortCodeKeepsACollegeTeamsOwnCode() {
        XCTAssertEqual(Team.shortCode(strTeamShort: "BC", name: "Boston College Eagles", idTeam: "ncaaf-103"), "BC")
        XCTAssertEqual(Team.shortCode(strTeamShort: "UCLA", name: "UCLA Bruins", idTeam: "ncaaf-26"), "UCLA")
        XCTAssertEqual(Team(idTeam: "ncaaf-41", strTeam: "UConn Huskies", strTeamShort: "CONN").shortCode, "CONN")
        // Pro teams are unchanged: a 2-letter code still becomes the tricode.
        XCTAssertEqual(Team.shortCode(strTeamShort: "NY", name: "New York Knicks", idTeam: "134862"), "NYK")
    }

    // MARK: - Pre-game scores

    func testPregameZerosAreDropped() throws {
        for game in try pregameGames() {
            XCTAssertEqual(game.strStatus, "pre")
            XCTAssertNil(game.intHomeScore, game.strHomeTeam)
            XCTAssertNil(game.intAwayScore, game.strHomeTeam)
        }
    }

    func testPregameZerosAreDroppedOnDecode() throws {
        // What prod serves today: "pre" with "0"–"0".
        let json = #"{"idEvent":"1","idLeague":"102","strHomeTeam":"Utah Utes","strAwayTeam":"BYU Cougars","intHomeScore":"0","intAwayScore":"0","strStatus":"pre","strTimestamp":"2026-11-07T17:00Z"}"#
        let game = try JSONDecoder().decode(Game.self, from: Data(json.utf8))
        XCTAssertNil(game.intHomeScore)
        XCTAssertNil(game.intAwayScore)
    }

    /// TheSportsDB leaves some finished games at "NS" with the real result. Only the
    /// 0–0 placeholder goes; a real score survives, on init and on decode.
    func testStaleNotStartedStatusKeepsARealResult() throws {
        let game = Game(idEvent: "ns-1", strHomeTeam: "Home", strAwayTeam: "Away",
                        intHomeScore: "2", intAwayScore: "0", strStatus: "NS", isoDate: nil)
        XCTAssertEqual(game.intHomeScore, "2")
        XCTAssertEqual(game.intAwayScore, "0")
        let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(decoded.intHomeScore, "2")
        XCTAssertEqual(decoded.intAwayScore, "0")
    }

    func testStartedAndFinishedScoresAreKept() {
        let live = Game(strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "0", intAwayScore: "0", strStatus: "in", isoDate: nil)
        XCTAssertEqual(live.intHomeScore, "0")
        let final = Game(strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "21", intAwayScore: "17", strStatus: "post", isoDate: nil)
        XCTAssertEqual(final.intHomeScore, "21")
        let tsdbFinal = Game(strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "2", intAwayScore: "1", strStatus: "FT", isoDate: nil)
        XCTAssertEqual(tsdbFinal.intAwayScore, "1")
        let tsdbNotStarted = Game(strHomeTeam: "A", strAwayTeam: "B", intHomeScore: "0", intAwayScore: "0", strStatus: "NS", isoDate: nil)
        XCTAssertNil(tsdbNotStarted.intHomeScore)
    }

    // MARK: - TBD kickoff

    func testTimeValidFalseIsTBD() throws {
        let games = try pregameGames()
        let tbd = try game(home: "BYU Cougars", in: games)
        XCTAssertEqual(tbd.timeTBD, true)
        XCTAssertTrue(tbd.isTimeTBD)
        let noon = try game(home: "Utah Utes", in: games)
        XCTAssertNil(noon.timeTBD)
        XCTAssertFalse(noon.isTimeTBD)
    }

    func testTBDSurvivesTheWireOnlyBeforeKickoff() throws {
        let tbd = try game(home: "BYU Cougars", in: try pregameGames())
        let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(tbd))
        XCTAssertTrue(decoded.isTimeTBD)
        let started = tbd.updated(strStatus: "in")
        let decodedStarted = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(started))
        XCTAssertNil(decodedStarted.timeTBD)
        XCTAssertFalse(decodedStarted.isTimeTBD)
    }

    /// Baylor at BYU is parked at 05:00Z on Nov 14 (midnight ET). Its anchor is noon
    /// ET that day, which is Nov 14 in Los Angeles too.
    func testTBDAnchorIsTheGamesDayEverywhere() throws {
        let placeholder = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-14T05:00:00Z"))
        let anchor = Game.tbdAnchorDate(placeholder)
        XCTAssertEqual(anchor, ISO8601DateFormatter().date(from: "2026-11-14T17:00:00Z"))
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(pacific.component(.day, from: anchor), 14)
    }

    func testOldServerMidnightEasternCollegeGameIsTBD() {
        // No `timeTBD` key (older server): ESPN's midnight-Eastern placeholder still reads as TBD.
        let est = Game(idLeague: "102", strHomeTeam: "A", strAwayTeam: "B", strStatus: "pre", strTimestamp: "2026-11-14T05:00Z", isoDate: nil)
        XCTAssertTrue(est.isTimeTBD)
        let edt = Game(idLeague: "102", strHomeTeam: "A", strAwayTeam: "B", strStatus: "pre", strTimestamp: "2026-10-17T04:00Z", isoDate: nil)
        XCTAssertTrue(edt.isTimeTBD)
        let noon = Game(idLeague: "102", strHomeTeam: "A", strAwayTeam: "B", strStatus: "pre", strTimestamp: "2026-11-07T17:00Z", isoDate: nil)
        XCTAssertFalse(noon.isTimeTBD)
        // Only college: a pro game at midnight ET is a real time.
        let nba = Game(idLeague: "4387", strHomeTeam: "A", strAwayTeam: "B", strStatus: "pre", strTimestamp: "2026-11-14T05:00Z", isoDate: nil)
        XCTAssertFalse(nba.isTimeTBD)
    }
}
