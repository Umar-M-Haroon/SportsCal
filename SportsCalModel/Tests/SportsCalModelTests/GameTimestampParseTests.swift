import XCTest
@testable import SportsCalModel

/// Verifies that `Game.isoDate` is backfilled from `strTimestamp` across the four
/// timestamp shapes the server has historically emitted. The pre-refactor decoder
/// allocated fresh `ISO8601DateFormatter` + `DateFormatter` instances per game and
/// tried the same four parses sequentially; this test pins the semantics so the
/// shared `DateParsers` cache cannot silently regress them.
final class GameTimestampParseTests: XCTestCase {

    private func decode(timestamp: String) throws -> Game {
        let json = """
        {"strHomeTeam": "A", "strAwayTeam": "B", "strTimestamp": "\(timestamp)"}
        """.data(using: .utf8)!
        return try JSONDecoder().decode(Game.self, from: json)
    }

    func testISO8601WithSecondsAndTimezone() throws {
        let game = try decode(timestamp: "2026-05-20T01:27:14Z")
        XCTAssertEqual(game.isoDate, Date(timeIntervalSince1970: 1779240434))
    }

    func testDashedSeconds_UTC() throws {
        // Matches the `yyyy-MM-dd'T'HH:mm:ss` fallback (no trailing Z).
        let game = try decode(timestamp: "2026-05-20T01:27:14")
        XCTAssertEqual(game.isoDate, Date(timeIntervalSince1970: 1779240434))
    }

    func testDashedNoSeconds() throws {
        let game = try decode(timestamp: "2026-05-20T01:27")
        XCTAssertEqual(game.isoDate, Date(timeIntervalSince1970: 1779240420))
    }

    func testDashedZ_NoSeconds() throws {
        let game = try decode(timestamp: "2026-05-20T01:27Z")
        XCTAssertEqual(game.isoDate, Date(timeIntervalSince1970: 1779240420))
    }

    func testMalformedTimestampLeavesIsoDateNil() throws {
        let game = try decode(timestamp: "not a date")
        XCTAssertNil(game.isoDate)
    }

    func testExplicitIsoDatePreferredOverTimestamp() throws {
        // When the server already provides isoDate, the timestamp fallback must not overwrite it.
        // JSONDecoder default decodes the numeric as `referenceDate` (2001-01-01) seconds offset.
        let json = """
        {"strHomeTeam": "A", "strAwayTeam": "B",
         "strTimestamp": "2026-05-20T01:27:14Z",
         "isoDate": 1000000000}
        """.data(using: .utf8)!
        let game = try JSONDecoder().decode(Game.self, from: json)
        XCTAssertNotEqual(game.isoDate, Date(timeIntervalSince1970: 1779240434))
        XCTAssertNotNil(game.isoDate)
    }
}
