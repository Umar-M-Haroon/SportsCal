@testable import App
import SportsCalModel
import XCTest

final class TeamCompetitionBuilderTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-24T12:00:00Z")!

    private func game(_ league: Int, _ home: String, _ away: String, _ day: String?) -> String {
        let date = day.map { "\"dateEvent\":\"\($0)\"," } ?? ""
        return "{\(date)\"idLeague\":\"\(league)\",\"idHomeTeam\":\"\(home)\",\"idAwayTeam\":\"\(away)\",\"strHomeTeam\":\"H\",\"strAwayTeam\":\"A\"}"
    }

    func testCollectsEveryCompetitionAndAddsTheDomesticCup() throws {
        // Arsenal (1) plays the Premier League and the Champions League; PSV (3) the
        // Eredivisie and the Champions League; Real Madrid (2) La Liga.
        let soccer = [
            game(4328, "1", "9", "2026-11-29"),
            game(4480, "1", "3", "2026-11-25"),
            game(4337, "3", "8", "2026-11-30"),
            game(4335, "2", "7", "2026-12-01"),
        ].joined(separator: ",")
        let blob = "{\"soccer\":{\"events\":[\(soccer)]},\"standings\":{\"rows\":[1,2]}}"
        let index = TeamCompetitionBuilder.index(from: blob, now: now)

        XCTAssertEqual(index.teams["1"], [4328, 4480, 4482]) // EPL, UCL, FA Cup by rule
        XCTAssertEqual(index.teams["2"], [4335, 4483])       // La Liga, Copa del Rey
        XCTAssertEqual(index.teams["3"], [4337, 4480])       // no cup rule for the Eredivisie
        XCTAssertEqual(Set(index.leagues(forTeam: "1")),
                       [.English_Premier_League, .UEFA_Champions_League, .FA_Cup])
        XCTAssertEqual(index.leagues(forTeam: "1").first, .English_Premier_League)
    }

    func testOldGamesDontCountButUndatedOnesDo() {
        let blob = "{\"soccer\":{\"events\":[\(game(4329, "5", "6", "2025-01-10")),\(game(4328, "5", "6", "2026-12-02")),\(game(4346, "11", "12", nil))]}}"
        let index = TeamCompetitionBuilder.index(from: blob, now: now)
        // Team 5 was in the Championship two seasons ago; only its current league counts.
        XCTAssertEqual(index.teams["5"], [4328, 4482])
        XCTAssertEqual(index.teams["11"], [4346])
    }

    func testSkipsIndividualSportsAndUnknownLeagues() {
        let blob = "{\"golf\":{\"events\":[\(game(4425, "p1", "p2", "2026-12-01"))]},\"x\":{\"events\":[\(game(999999, "t1", "t2", "2026-12-01"))]}}"
        XCTAssertTrue(TeamCompetitionBuilder.index(from: blob, now: now).teams.isEmpty)
    }

    func testBodyRoundTripsAsTheModelType() throws {
        let blob = "{\"nba\":{\"events\":[\(game(4387, "134862", "134865", "2026-11-25"))]}}"
        let body = try XCTUnwrap(TeamCompetitionBuilder.body(from: blob, now: now))
        let decoded = try JSONDecoder().decode(TeamCompetitionIndex.self, from: Data(body.utf8))
        XCTAssertEqual(decoded.teams["134862"], [4387])
    }
}
