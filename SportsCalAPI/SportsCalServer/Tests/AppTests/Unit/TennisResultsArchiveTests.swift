import XCTest
@testable import App
import SportsCalModel

final class TennisResultsArchiveTests: XCTestCase {
    /// A trimmed ESPN month board: a combined event, so the WTA draw sits on the ATP board.
    private let board = """
    {"events":[{"name":"Roland Garros","groupings":[
      {"grouping":{"slug":"mens-singles"},"competitions":[
        {"id":"1","date":"2025-06-08T13:10Z","round":{"displayName":"Final"},
         "status":{"type":{"name":"STATUS_FINAL","completed":true}},
         "competitors":[
           {"id":"3782","homeAway":"home","winner":true,"athlete":{"displayName":"Carlos Alcaraz"},
            "linescores":[{"value":4},{"value":6,"tiebreak":4},{"value":7,"tiebreak":7},{"value":7,"tiebreak":7},{"value":7,"tiebreak":10}]},
           {"id":"3623","homeAway":"away","winner":false,"athlete":{"displayName":"Jannik Sinner"},
            "linescores":[{"value":6},{"value":7,"tiebreak":7},{"value":6,"tiebreak":3},{"value":6,"tiebreak":2},{"value":6,"tiebreak":2}]}]},
        {"id":"2","date":"2025-05-26T10:00Z","round":{"displayName":"Qualifying Final"},
         "status":{"type":{"name":"STATUS_FINAL","completed":true}},
         "competitors":[{"id":"10","homeAway":"home","winner":true,"athlete":{"displayName":"A"}},
                        {"id":"11","homeAway":"away","athlete":{"displayName":"B"}}]},
        {"id":"3","date":"2025-06-01T10:00Z","round":{"displayName":"Round 4"},
         "status":{"type":{"name":"STATUS_WALKOVER","completed":true}},
         "competitors":[{"id":"3623","homeAway":"home","athlete":{"displayName":"Jannik Sinner"}},
                        {"id":"3782","homeAway":"away","winner":true,"athlete":{"displayName":"Carlos Alcaraz"}}]},
        {"id":"4","date":"2025-06-09T10:00Z","round":{"displayName":"Final"},
         "status":{"type":{"name":"STATUS_SCHEDULED","completed":false}},
         "competitors":[{"id":"-3","homeAway":"home","athlete":{"displayName":"TBD"}},
                        {"id":"-4","homeAway":"away","athlete":{"displayName":"TBD"}}]}]},
      {"grouping":{"slug":"womens-singles"},"competitions":[
        {"id":"5","date":"2025-06-07T13:10Z","round":{"displayName":"Final"},
         "status":{"type":{"name":"STATUS_FINAL","completed":true}},
         "competitors":[{"id":"20","homeAway":"home","winner":true,"athlete":{"displayName":"Coco Gauff"}},
                        {"id":"21","homeAway":"away","athlete":{"displayName":"Aryna Sabalenka"}}]}]},
      {"grouping":{"slug":"mens-doubles"},"competitions":[
        {"id":"6","date":"2025-06-07T13:10Z","round":{"displayName":"Final"},
         "status":{"type":{"name":"STATUS_FINAL","completed":true}},
         "competitors":[{"id":"30","homeAway":"home","winner":true},{"id":"31","homeAway":"away"}]}]}
    ]}]}
    """

    private func decoded() throws -> TennisArchiveBoard {
        try JSONDecoder().decode(TennisArchiveBoard.self, from: Data(board.utf8))
    }

    func testKeepsFinishedMainDrawSinglesOfTheTourOnly() throws {
        let atp = TennisResultsArchive.matches(in: try decoded(), tour: .atp)
        XCTAssertEqual(atp.map(\.i), ["1", "3"])
        let final = try XCTUnwrap(atp.first)
        XCTAssertEqual(final.d, "2025-06-08")
        XCTAssertEqual(final.w, "h")
        XCTAssertEqual(final.s, [[4, 6], [6, 7, 4], [7, 6, 3], [7, 6, 2], [7, 6, 2]])
        XCTAssertEqual(atp.last?.m, "w/o")
        XCTAssertEqual(TennisResultsArchive.matches(in: try decoded(), tour: .wta).map(\.i), ["5"])
    }

    func testHeadToHeadReadsTheArchiveAndSkipsWalkoversInTheRecord() async throws {
        let kv = RedisCapableKV()
        let matches = TennisResultsArchive.matches(in: try decoded(), tour: .atp)
        let now = Date()
        let month = try XCTUnwrap(TennisResultsArchive.months(through: now).last)
        try await kv.setJSON(TennisResultsArchive.key(tour: .atp, year: month.year, month: month.month, isDebug: false),
                             value: matches, ttl: nil)
        let index = TennisH2HIndex()
        let h2h = await index.headToHead(player: "3623", opponent: "3782", kv: kv, isDebug: false)
        XCTAssertEqual(h2h.meetings.map(\.id), ["1", "3"], "newest first")
        XCTAssertEqual(h2h.opponentWins, 1, "the walkover isn't counted")
        XCTAssertEqual(h2h.playerWins, 0)
        XCTAssertEqual(h2h.meetings.first?.scoreText(from: "3623"), "6-4 7-6(4) 6-7(3) 6-7(2) 6-7(2)")
    }

    func testMonthsRunNewestFirstBackToTheFirstSeason() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-02-10T00:00:00Z"))
        let months = TennisResultsArchive.months(through: date)
        XCTAssertEqual(months.first?.year, 2026)
        XCTAssertEqual(months.first?.month, 2)
        XCTAssertEqual(months.last?.year, TennisResultsArchive.firstYear)
        XCTAssertEqual(months.last?.month, 1)
        XCTAssertEqual(months.count, (2026 - TennisResultsArchive.firstYear) * 12 + 2)
    }
}
