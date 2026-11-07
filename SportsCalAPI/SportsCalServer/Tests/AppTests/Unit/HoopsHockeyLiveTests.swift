import XCTest
@testable import App
import SportsCalModel

/// Basketball fouls/runs and hockey strength on the server: the NHL feed's decode and
/// status text, the play-by-play tally reaching the snapshot, and both surviving the
/// ESPN ticks that replace the situation whole.
final class HoopsHockeyLiveTests: XCTestCase {

    // MARK: - NHL api-web

    /// The shape of a `scoreboard/now` game. Period, clock and descriptor match captured
    /// payloads; the `situation` block follows api-web's play-by-play (unconfirmed live).
    private func nhlGame(period: Int = 2, type: String = "REG", gameType: Int = 2, clock: String = "08:12",
                         seconds: Int = 492, intermission: Bool = false, situation: String? = nil) throws -> NHLGame {
        let situationJSON = situation ?? "null"
        let json = """
        {"id": 2026020262, "gameState": "LIVE", "gameType": \(gameType), "startTimeUTC": "2026-11-07T00:00:00Z",
         "period": \(period), "periodDescriptor": {"number": \(period), "periodType": "\(type)", "maxRegulationPeriods": 3},
         "clock": {"timeRemaining": "\(clock)", "secondsRemaining": \(seconds), "running": true, "inIntermission": \(intermission)},
         "situation": \(situationJSON),
         "homeTeam": {"abbrev": "TOR", "score": 2, "name": {"default": "Toronto Maple Leafs"}},
         "awayTeam": {"abbrev": "BOS", "score": 1, "name": {"default": "Boston Bruins"}}}
        """
        return try JSONDecoder().decode(NHLGame.self, from: Data(json.utf8))
    }

    func testProgressMatchesESPNsFormat() throws {
        XCTAssertEqual(try nhlGame().progress, "8:12 - 2nd")
        XCTAssertEqual(try nhlGame(clock: "12:34").progress, "12:34 - 2nd")
        XCTAssertEqual(try nhlGame(intermission: true).progress, "End of 2nd")
        XCTAssertEqual(try nhlGame(period: 4, type: "OT", clock: "03:21").progress, "3:21 - OT")
        XCTAssertEqual(try nhlGame(period: 5, type: "OT", gameType: 3, clock: "15:00").progress, "15:00 - 2OT")
        XCTAssertEqual(try nhlGame(period: 5, type: "SO").progress, "SO")
    }

    func testPowerPlayFromTheSituationCode() throws {
        let game = try nhlGame(situation: #"{"situationCode": "1451", "timeRemaining": "01:42", "secondsRemaining": 102}"#)
        let s = try XCTUnwrap(game.toGame()?.situation)
        XCTAssertEqual(s.period, 2)
        XCTAssertEqual(s.clock, 492)
        XCTAssertEqual(s.powerPlaySide, .home)
        XCTAssertEqual(s.powerPlayClockText, "1:42")
    }

    func testNoSituationBlockIsEvenStrength() throws {
        let s = try XCTUnwrap(try nhlGame().toGame()?.situation)
        XCTAssertTrue(s.hasHockeyState)
        XCTAssertNil(s.powerPlaySide)
        let ot = try XCTUnwrap(try nhlGame(period: 4, type: "OT").toGame()?.situation)
        XCTAssertEqual(ot.homeSkaters, 3, "regular-season overtime is 3-on-3")
    }

    func testMalformedSituationNeverCostsTheGame() throws {
        let game = try nhlGame(situation: #"{"situationCode": {"weird": true}, "secondsRemaining": "x"}"#)
        XCTAssertNotNil(game.toGame())
        let numeric = try nhlGame(situation: #"{"situationCode": 651}"#)
        XCTAssertEqual(numeric.toGame()?.situation?.emptyNetSide, .away, "651 is 0651")
    }

    // MARK: - Merging

    private func nhl(_ id: String, home: String = "2", away: String = "1", situation: GameSituation?) -> Game {
        var game = TestGameFactory.make(
            idEvent: id, idLeague: "\(Leagues.nhl.rawValue)",
            strHomeTeam: "Toronto Maple Leafs", strAwayTeam: "Boston Bruins",
            intHomeScore: home, intAwayScore: away, strStatus: "in",
            strTimestamp: "2026-11-07T00:00:00", isoDate: nil
        )
        game.situation = situation
        return game
    }

    func testESPNTickKeepsTheNHLPowerPlay() {
        var pp = GameSituation(period: 2, clock: 500)
        pp.applyNHLSituationCode("1451")
        let cached = TestGameFactory.liveScore(nhl: [nhl("espn-1", situation: pp)])
        let espn = nhl("espn-1", situation: GameSituation(period: 2, clock: 495, homeWinProbability: 0.6))
        let merged = LiveMerge.overlay(cached: cached, sport: .hockey, fresh: [espn], strategy: .eventID,
                                       race: LiveMerge.RaceOptions(source: ESPNLiveSource.sourceName))
            .liveScore.nhl?.events.first?.situation
        XCTAssertEqual(merged?.powerPlaySide, .home)
        XCTAssertEqual(merged?.clock, 495)
    }

    func testNHLEvenStrengthClearsThePowerPlay() {
        var pp = GameSituation(period: 2, clock: 500)
        pp.applyNHLSituationCode("1451")
        let cached = TestGameFactory.liveScore(nhl: [nhl("espn-1", situation: pp)])
        var even = GameSituation(period: 2, clock: 480)
        even.setEvenStrength()
        let merged = LiveMerge.overlay(cached: cached, sport: .hockey, fresh: [nhl("nhl-9", situation: even)],
                                       strategy: .teamsAndDay, race: LiveMerge.RaceOptions(source: "nhl-apiweb"))
            .liveScore.nhl?.events.first?.situation
        XCTAssertNil(merged?.powerPlaySide)
    }

    func testRebuildCarriesStateFromThePreviousSnapshot() {
        var pp = GameSituation(period: 3, clock: 200)
        pp.applyNHLSituationCode("1541")
        let previous = TestGameFactory.liveScore(nhl: [nhl("e", situation: pp)])
        let rebuilt = TestGameFactory.liveScore(nhl: [nhl("e", situation: GameSituation(period: 3, clock: 190))])
        let carried = LiveMerge.carryingSupplementalState(into: rebuilt, from: previous)
        XCTAssertEqual(carried.nhl?.events.first?.situation?.powerPlaySide, .away)
    }

    func testTallyIsStampedOnLiveBasketballGames() {
        var live = TestGameFactory.make(idEvent: "a", strHomeTeam: "A", strAwayTeam: "B", strStatus: "in")
        live.situation = GameSituation(period: 4, clock: 300)
        let final = TestGameFactory.make(idEvent: "b", strHomeTeam: "C", strAwayTeam: "D", strStatus: "post")
        let tally = BasketballPlayTally(period: 4, homeFouls: 5, awayFouls: 2, homeTimeouts: 2, awayTimeouts: 1,
                                        runSide: .home, runPoints: 9)
        let stamped = ESPNFetchJob.applyingTallies(["a": tally, "b": tally], to: TestGameFactory.liveScore(nba: [live, final]))
        let s = stamped.nba?.events.first?.situation
        XCTAssertEqual(s?.homeFouls, 5)
        XCTAssertEqual(s?.awayTimeouts, 1)
        XCTAssertEqual(s?.runPoints, 9)
        XCTAssertNil(stamped.nba?.events.last?.situation)
    }

    func testBasketballSlugFollowsTheLeague() {
        let wnba = TestGameFactory.make(idEvent: "w", idLeague: "\(Leagues.wnba.rawValue)", strHomeTeam: "A", strAwayTeam: "B")
        let ncaa = TestGameFactory.make(idEvent: "n", idLeague: "\(Leagues.ncaaMBBTournament.rawValue)", strHomeTeam: "A", strAwayTeam: "B")
        let nba = TestGameFactory.make(idEvent: "x", idLeague: "\(Leagues.nba.rawValue)", strHomeTeam: "A", strAwayTeam: "B")
        XCTAssertEqual(ESPNFetchJob.basketballSlug(for: wnba), "wnba")
        XCTAssertEqual(ESPNFetchJob.basketballSlug(for: ncaa), "mens-college-basketball")
        XCTAssertEqual(ESPNFetchJob.basketballSlug(for: nba), "nba")
    }
}
