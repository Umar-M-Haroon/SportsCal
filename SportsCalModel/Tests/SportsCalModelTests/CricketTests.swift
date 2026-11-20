import XCTest
@testable import SportsCalModel

final class CricketTests: XCTestCase {
    private func games() throws -> [Game] {
        try JSONDecoder().decode(ESPNCricketBoard.self, from: Data(cricketPanelFixture.utf8)).games()
    }

    private func game(_ id: String) throws -> Game {
        try XCTUnwrap(games().first { $0.idEvent == id }, "no game \(id)")
    }

    func testCarriesInternationalsAndDropsTheRest() throws {
        let ids = Set(try games().compactMap(\.idEvent))
        // NZ v India Test, Pakistan v Sri Lanka Test, Australia v England T20I.
        XCTAssertEqual(ids, ["1539442", "1550712", "1528706"])
        // Dropped: Plunket Shield, Abu Dhabi T10, Syed Mushtaq Ali Trophy, and a
        // women's T20I between two associates.
    }

    func testLiveTest() throws {
        let game = try game("1539442")
        XCTAssertEqual(game.sportType, .cricket)
        XCTAssertEqual(game.idLeague, "\(Leagues.cricketTests.rawValue)")
        XCTAssertEqual(game.idHomeTeam?.hasPrefix(CricketCompetition.teamIDPrefix), true)
        XCTAssertEqual(game.strStatus, "in")
        XCTAssertFalse(game.hasDoneStatus)
        XCTAssertEqual(game.tournamentName, "India tour of New Zealand 2026/27")
        XCTAssertNotNil(game.endDate, "a Test runs to its end date")

        let cricket = try XCTUnwrap(game.cricket)
        XCTAssertEqual(cricket.format, .test)
        XCTAssertEqual(cricket.session, "Day 2")
        XCTAssertEqual(cricket.summary, "India trail by 209 runs")
        XCTAssertEqual(game.lastPlay, "India trail by 209 runs")
        XCTAssertEqual(cricket.battingSide, .away)
        XCTAssertEqual(cricket.currentInnings?.runs, 159)
        XCTAssertEqual(cricket.currentInnings?.wickets, 1)
        XCTAssertEqual(cricket.scoreText(for: .home), "368")
    }

    func testFinishedTestKeepsESPNWinnerAndTarget() throws {
        let game = try game("1550712")
        XCTAssertTrue(game.hasDoneStatus)
        XCTAssertEqual(game.intHomeScore, "325 & 90/2 (13 ov, target 90)")
        XCTAssertEqual(game.scoreboardExtras?.homeWinner, true)
        XCTAssertEqual(game.scoreboardExtras?.awayWinner, false)
        let cricket = try XCTUnwrap(game.cricket)
        XCTAssertEqual(cricket.innings.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(cricket.innings.map(\.side), [.away, .home, .away, .home])
        XCTAssertEqual(cricket.scoreText(for: .home), "325 & 90/2")
        XCTAssertEqual(cricket.scoreText(for: .away), "98 & 316")
        XCTAssertEqual(cricket.target, 90)
        XCTAssertNil(cricket.currentInnings, "nothing is current once the match is over")
    }

    func testScheduledT20I() throws {
        let game = try game("1528706")
        XCTAssertEqual(game.idLeague, "\(Leagues.cricketT20Is.rawValue)")
        XCTAssertNil(game.intHomeScore)
        XCTAssertNil(game.lastPlay)
        XCTAssertNil(game.endDate, "a one-day match has no real end date")
        XCTAssertEqual(game.cricket?.format, .t20)
        XCTAssertEqual(game.cricket?.scheduledOvers, 20)
        XCTAssertEqual(game.round, "1st T20I")
    }

    func testScoreText() {
        XCTAssertEqual(CricketScoreText.target(in: "184 (40.5/50 ov, target 246)"), 246)
        XCTAssertEqual(CricketScoreText.scheduledOvers(in: "184 (40.5/50 ov, target 246)"), 50)
        XCTAssertEqual(CricketScoreText.scheduledOvers(in: "99/3 (9.2/10 ov, target 99)"), 10)
        XCTAssertNil(CricketScoreText.scheduledOvers(in: "144/2 (40 ov)"))
        XCTAssertNil(CricketScoreText.target(in: "392/9d"))
        XCTAssertTrue(CricketScoreText.isDeclared("392/9d"))
        XCTAssertFalse(CricketScoreText.isDeclared("392/9"))
        XCTAssertFalse(CricketScoreText.isDeclared("137"))
    }

    func testInningsMaths() {
        let innings = CricketInnings(side: .away, number: 2, runs: 99, wickets: 3, overs: 9.2)
        XCTAssertEqual(innings.balls, 56)
        XCTAssertEqual(innings.oversText, "9.2 ov")
        XCTAssertEqual(innings.scoreText, "99/3")
        XCTAssertEqual(CricketInnings(side: .home, number: 1, runs: 137, wickets: 10).scoreText, "137")
        let chase = CricketMatchExtras(format: .odi, innings: [
            CricketInnings(side: .home, number: 1, runs: 245, wickets: 10, overs: 49.1),
            CricketInnings(side: .away, number: 2, runs: 184, wickets: 6, overs: 40, isCurrent: true),
        ], target: 246, scheduledOvers: 50)
        XCTAssertEqual(chase.runsRequired, 62)
        XCTAssertEqual(chase.requiredRunRate ?? 0, 6.2, accuracy: 0.001)
    }

    func testRouting() {
        func route(_ espnID: Int?, _ name: String?, _ classID: Int?, _ teams: [String]) -> Leagues? {
            CricketCompetition.league(espnLeagueID: espnID, leagueName: name, internationalClassID: classID, teamNames: teams)
        }
        XCTAssertEqual(route(8048, "Indian Premier League", 0, ["Mumbai Indians", "Chennai Super Kings"]), .ipl)
        XCTAssertEqual(route(99999, "SA20, 2027/28", 0, ["Paarl Royals", "MI Cape Town"]), .sa20)
        XCTAssertEqual(route(1, "The Hundred Women's Competition", 0, ["Oval Invincibles Women", "London Spirit Women"]), .theHundredWomen)
        XCTAssertEqual(route(1, "ICC Men's T20 World Cup", 3, ["Nepal", "United States of America"]), .cricketT20Is)
        XCTAssertNil(route(1, "ICC Men's T20 World Cup Sub Regional Africa Qualifier Group C", 3, ["Gambia", "Lesotho"]))
        XCTAssertNil(route(1, "ICC Cricket World Cup Qualifier Play-off", 2, ["Italy", "Namibia"]))
        XCTAssertEqual(route(1, "Ireland tour of Namibia 2026/27", 2, ["Namibia", "Ireland"]), .cricketODIs)
        XCTAssertEqual(route(1, "India Women tour of South Africa 2026/27", 10, ["South Africa Women", "India Women"]), .womensCricketInternationals)
        XCTAssertNil(route(1, "Australia Under-19s tour of India", 14, ["India Under-19s", "Australia Under-19s"]))
        XCTAssertEqual(route(8044, "Big Bash League", 0, []).map(SportType.init(league:)), .cricket)
    }

    func testOwnWireKeyAndRoundTrip() throws {
        let game = try game("1539442")
        let score = LiveScore(soccer: LiveEvent(events: []), cricket: LiveEvent(events: [game]))
        let data = try JSONEncoder().encode(score)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["cricket"])
        XCTAssertEqual((json["soccer"] as? [String: Any])?["events"] as? [Any] as? NSArray, [])
        let back = try JSONDecoder().decode(LiveScore.self, from: data)
        XCTAssertEqual(back.cricket?.events.first?.cricket, game.cricket)
        XCTAssertEqual(LiveScore.wireKeys(for: .cricket, college: false, motorsport: false), [.cricket])
        XCTAssertEqual(score.slice(.cricket).cricket?.events.count, 1)
    }

    func testMultiDayTestSurvivesStalePrune() throws {
        var score = LiveScore(cricket: LiveEvent(events: [try game("1539442")]))
        // Day 2 of the Test: a day and a half after the toss, still before the end date.
        let now = try XCTUnwrap(DateParsers.parse("2026-11-20T10:00Z"))
        XCTAssertEqual(score.removeStaleLiveGames(now: now), 0)
        XCTAssertEqual(score.cricket?.events.count, 1)
    }
}
