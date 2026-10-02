import XCTest
@testable import SportsCalModel

final class SeasonPhaseTests: XCTestCase {
    private struct SportsDBSchedule: Decodable { let schedule: [Game] }

    /// A trimmed slice of TheSportsDB's real 2025-26 NHL schedule (Sep 2026): 5 preseason
    /// rows, 10 of week 1, every row of weeks 16 and 26, and the playoff rounds. Week 16
    /// holds 54 January games plus 46 first-round playoff games TheSportsDB misfiled there.
    private func nhlSchedule() throws -> [Game] {
        let decoded = try JSONLoader.load(file: "NHLSportsDBSchedule2025", type: SportsDBSchedule.self)
        return try XCTUnwrap(decoded as? SportsDBSchedule).schedule
    }

    func testSportsDBRoundCodes() {
        XCTAssertEqual(SeasonPhase(sportsDBRound: 500), .preseason)
        XCTAssertEqual(SeasonPhase(sportsDBRound: 400), .playIn)
        XCTAssertEqual(SeasonPhase(sportsDBRound: 125), .postseason)
        XCTAssertEqual(SeasonPhase(sportsDBRound: 200), .postseason)
        XCTAssertEqual(SeasonPhase(sportsDBRound: 0), .regular)
        XCTAssertEqual(SeasonPhase(sportsDBRound: 26), .regular)
    }

    func testESPNSeasonTypes() {
        XCTAssertEqual(SeasonPhase(espnSeasonType: 1), .preseason)
        XCTAssertEqual(SeasonPhase(espnSeasonType: 2), .regular)
        XCTAssertEqual(SeasonPhase(espnSeasonType: 3), .postseason)
        XCTAssertEqual(SeasonPhase(espnSeasonType: 5), .playIn)
        XCTAssertNil(SeasonPhase(espnSeasonType: 4))
    }

    func testDecodesSeasonAndRoundFromSportsDB() throws {
        let games = try nhlSchedule()
        XCTAssertEqual(games.count, 184)
        XCTAssertTrue(games.allSatisfy { $0.season == "2025-2026" })
        XCTAssertTrue(games.allSatisfy { $0.sportsDBRound != nil })
    }

    func testAssignPhasesFixesMisfiledPlayoffGames() throws {
        let games = SeasonPhase.assignPhases(try nhlSchedule(), league: .nhl)
        func phases(round: Int) -> [SeasonPhase?] {
            games.filter { $0.sportsDBRound == round }.map(\.seasonPhase)
        }

        XCTAssertEqual(phases(round: 500), Array(repeating: .preseason, count: 5))
        XCTAssertTrue(phases(round: 26).allSatisfy { $0 == .regular })
        XCTAssertTrue(phases(round: 1).allSatisfy { $0 == .regular })
        for round in [125, 150, 200] {
            XCTAssertTrue(phases(round: round).allSatisfy { $0 == .postseason }, "round \(round)")
        }

        // Week 16: the January games stay regular, the April/May ones become playoffs.
        let week16 = games.filter { $0.sportsDBRound == 16 }
        let regular = week16.filter { $0.seasonPhase == .regular }
        let moved = week16.filter { $0.seasonPhase == .postseason }
        XCTAssertEqual(regular.count, 54)
        XCTAssertEqual(moved.count, 46)
        let regularSeasonEnd = try XCTUnwrap(
            games.filter { $0.sportsDBRound == 26 }.compactMap(\.isoDate).max()
        )
        XCTAssertTrue(moved.allSatisfy { ($0.isoDate ?? .distantPast) > regularSeasonEnd })
        XCTAssertTrue(regular.allSatisfy { ($0.isoDate ?? .distantFuture) < regularSeasonEnd })
    }

    func testAssignPhasesSkipsLeaguesWithoutPhases() throws {
        let game = Game(idLeague: "4328", strHomeTeam: "A", strAwayTeam: "B",
                        isoDate: Date(), season: "2025-2026", sportsDBRound: 150)
        let result = SeasonPhase.assignPhases([game], league: .English_Premier_League)
        XCTAssertNil(result.first?.seasonPhase)
    }

    func testWireFormatOmitsRegularAndRound() throws {
        let regular = Game(strHomeTeam: "A", strAwayTeam: "B", isoDate: nil,
                           season: "2025-2026", seasonPhase: .regular, sportsDBRound: 12)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(regular), encoding: .utf8))
        XCTAssertTrue(json.contains("\"strSeason\":\"2025-2026\""))
        XCTAssertFalse(json.contains("seasonPhase"))
        XCTAssertFalse(json.contains("intRound"))

        let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(regular))
        XCTAssertNil(decoded.seasonPhase)
        XCTAssertEqual(decoded.resolvedSeasonPhase, .regular)

        let playoff = Game(strHomeTeam: "A", strAwayTeam: "B", isoDate: nil,
                           season: "2025-2026", seasonPhase: .postseason)
        let roundTripped = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(playoff))
        XCTAssertEqual(roundTripped.seasonPhase, .postseason)
    }

    func testUnknownPhaseDoesNotFailDecode() throws {
        let json = #"{"strHomeTeam":"A","strAwayTeam":"B","seasonPhase":"allstar"}"#
        let game = try JSONDecoder().decode(Game.self, from: Data(json.utf8))
        XCTAssertNil(game.seasonPhase)
        XCTAssertEqual(game.resolvedSeasonPhase, .regular)
    }

    func testIntRoundAcceptsNumber() throws {
        let json = #"{"strHomeTeam":"A","strAwayTeam":"B","intRound":500}"#
        XCTAssertEqual(try JSONDecoder().decode(Game.self, from: Data(json.utf8)).sportsDBRound, 500)
    }

    func testSeasonLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func date(_ year: Int, _ month: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: 15))!
        }

        XCTAssertEqual(Leagues.nba.seasonLabel(for: date(2026, 10), calendar: calendar), "2026-2027")
        XCTAssertEqual(Leagues.nba.seasonLabel(for: date(2027, 4), calendar: calendar), "2026-2027")
        XCTAssertEqual(Leagues.mlb.seasonLabel(for: date(2026, 3), calendar: calendar), "2026")
        XCTAssertEqual(Leagues.nfl.seasonLabel(for: date(2027, 1), calendar: calendar), "2026")
        XCTAssertEqual(Leagues.nfl.seasonLabel(for: date(2026, 8), calendar: calendar), "2026")
        // ESPN-only single-year leagues must match ESPN's `season.year` label, or a
        // game that arrives without one starts a second "2026–27" season block.
        XCTAssertEqual(Leagues.wnba.seasonLabel(for: date(2026, 8), calendar: calendar), "2026")
        XCTAssertEqual(Leagues.MLS.seasonLabel(for: date(2026, 10), calendar: calendar), "2026")

        XCTAssertEqual(Leagues.nba.seasonLabel(espnYear: 2027), "2026-2027")
        XCTAssertEqual(Leagues.nfl.seasonLabel(espnYear: 2026), "2026")
        XCTAssertNil(Leagues.English_Premier_League.seasonLabel(espnYear: 2026))

        XCTAssertEqual(Game.seasonDisplayName("2025-2026"), "2025–26 Season")
        XCTAssertEqual(Game.seasonDisplayName("2026"), "2026 Season")
    }

    func testResolvedPhaseFallsBackToPlayoffContext() {
        let game = Game(strHomeTeam: "A", strAwayTeam: "B", isoDate: nil,
                        playoff: PlayoffContext(seriesTitle: "East Final"))
        XCTAssertEqual(game.resolvedSeasonPhase, .postseason)
    }
}
