import XCTest
@testable import SportsCalModel

/// The shared standings ordering and the shared period labels.
final class StandingsAndPeriodTests: XCTestCase {

    private func load(_ file: String) throws -> StandingsResponse {
        try XCTUnwrap(JSONLoader.load(file: file, type: StandingsResponse.self) as? StandingsResponse)
    }

    private func entries(_ response: StandingsResponse) -> [Entry] {
        response.children?.first?.standings?.entries ?? []
    }

    // MARK: Standings

    func testHockeyRanksByPointsAndNumbersInSortedOrder() throws {
        let rows = StandingsStyle.hockey.ranked(entries(try load("NHLStandings")))
        XCTAssertEqual(rows.map(\.rank), Array(1...rows.count))
        let points = rows.map { $0.entry.statValue("points") ?? 0 }
        XCTAssertEqual(points, points.sorted(by: >))
        XCTAssertEqual(StandingsStyle.hockey.columns(for: rows.map(\.entry)).map(\.title), ["GP", "W", "L", "OTL", "PTS"])
    }

    func testBasketballRanksByWinPercent() throws {
        let rows = StandingsStyle.basketball.ranked(entries(try load("BasketballStandings")))
        let pct = rows.map { $0.entry.statValue("winPercent") ?? 0 }
        XCTAssertEqual(pct, pct.sorted(by: >))
        XCTAssertEqual(rows.first?.entry.streak?.isEmpty, false)
    }

    func testFootballKeepsSeedOrder() throws {
        let rows = StandingsStyle.football.ranked(entries(try load("NFLStandings")))
        let seeds = rows.map { $0.entry.statValue("playoffSeed") ?? 0 }
        XCTAssertEqual(seeds, seeds.sorted())
        XCTAssertNotNil(rows.first?.entry.clinchMarker)
        // A T column only when some team has a tie.
        let hasTies = rows.contains { ($0.entry.statValue("ties") ?? 0) > 0 }
        XCTAssertEqual(StandingsStyle.football.columns(for: rows.map(\.entry)).contains(.ties), hasTies)
    }

    func testCollegeSortsByConferenceRecordWhenPresent() {
        func entry(_ name: String, overall: Double, conference: String) -> Entry {
            Entry(team: nil, note: nil, stats: [
                Stat(name: "winPercent", displayName: nil, shortDisplayName: nil, description: nil, abbreviation: nil,
                     type: "winpercent", value: overall, displayValue: nil, id: nil, summary: nil),
                Stat(name: "vs. Conf.", displayName: nil, shortDisplayName: nil, description: nil, abbreviation: nil,
                     type: "vsconf", value: nil, displayValue: conference, id: name, summary: conference),
            ])
        }
        // Better overall, worse in conference: conference record decides.
        let rows = StandingsStyle.collegeFootball.ranked([
            entry("a", overall: 0.9, conference: "5-3"),
            entry("b", overall: 0.7, conference: "8-0"),
        ])
        XCTAssertEqual(rows.map { $0.entry.conferenceRecord }, ["8-0", "5-3"])
        XCTAssertTrue(StandingsStyle.collegeFootball.columns(for: rows.map(\.entry)).contains(.conferenceRecord))
    }

    // MARK: Periods

    func testPeriodLabels() {
        XCTAssertEqual(Leagues.nba.periodLabel(5), "OT")
        XCTAssertEqual(Leagues.nba.periodLabel(6), "2OT")
        XCTAssertEqual(Leagues.ncaaMBBTournament.periodLabel(2), "H2")
        XCTAssertEqual(Leagues.ncaaMBBTournament.periodLabel(3), "OT")
        XCTAssertEqual(Leagues.nfl.periodLabel(5), "OT")
        XCTAssertEqual(Leagues.nhl.periodLabel(4), "OT")
        XCTAssertEqual(Leagues.nhl.periodLabel(5, phase: .regular), "SO")
        XCTAssertEqual(Leagues.nhl.periodLabel(5, phase: .postseason), "2OT")
        XCTAssertEqual(Leagues.English_Premier_League.periodLabel(5), "PEN")
        XCTAssertEqual(Leagues.mlb.periodLabel(9), "9")
        XCTAssertEqual(Leagues.mlb.periodName(9), "9th")
    }

    func testPeriodLengths() {
        XCTAssertEqual(Leagues.nba.periodLengthSeconds(1), 720)
        XCTAssertEqual(Leagues.wnba.periodLengthSeconds(1), 600)
        XCTAssertEqual(Leagues.ncaaMBBTournament.periodLengthSeconds(2), 1200)
        XCTAssertEqual(Leagues.nhl.periodLengthSeconds(4, phase: .regular), 300)
        XCTAssertEqual(Leagues.nhl.periodLengthSeconds(4, phase: .postseason), 1200)
        XCTAssertNil(Leagues.nhl.periodLengthSeconds(5, phase: .regular))
        XCTAssertNil(Leagues.mlb.periodLengthSeconds(1))
    }

    // MARK: Scoreboard extras

    func testSoccerScoreboardCarriesWinnerAndIncidentsOverTheWire() throws {
        let scoreboard = try XCTUnwrap(JSONLoader.load(file: "Premier-League-Scoreboard", type: Scoreboard.self) as? Scoreboard)
        let games = try XCTUnwrap(LiveEvent(events: scoreboard, league: .English_Premier_League)).events
        let game = try XCTUnwrap(games.first { $0.soccerDetails?.isEmpty == false })
        let goal = try XCTUnwrap(game.soccerDetails?.first { $0.kind == .goal })
        XCTAssertNotNil(goal.athlete)
        XCTAssertNotNil(goal.side)
        XCTAssertTrue(game.homeWinner != nil || game.awayWinner != nil)

        // Round trip: the wire keeps it, and a slimmed copy drops only the timeline.
        let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(decoded.scoreboardExtras, game.scoreboardExtras)
        XCTAssertNil(game.scoreboardExtras?.withoutHeavyDetail.soccerDetails)
        XCTAssertEqual(game.scoreboardExtras?.withoutHeavyDetail.homeWinner, game.homeWinner)
    }

    func testCollegeSeedMergeLetsAFreshNilWin() {
        XCTAssertNil(Game.mergedSeed(fresh: nil, stale: 12, idLeague: "\(Leagues.ncaaf.rawValue)"))
        XCTAssertEqual(Game.mergedSeed(fresh: nil, stale: 3, idLeague: "\(Leagues.nba.rawValue)"), 3)
    }
}
