import XCTest
@testable import SportsCalModel

/// Live situation (count/runners, down/distance, win probability), clutch moments,
/// the excitement score and team stat comparisons.
///
/// The `Summary-*` fixtures are trimmed real ESPN summaries pulled October 2026
/// (plays reduced to id + period, MLB's box to the curated stats). The live
/// `situation` payloads below are hand-written to ESPN's schema: no MLB or NFL game
/// was in progress when this was built, so swap in recorded ones when convenient.
final class LiveSituationTests: XCTestCase {

    // MARK: - Fixtures

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func summary(_ name: String) throws -> ESPNSummaryResponse {
        let decoded = try JSONLoader.load(file: "Summary-\(name)", type: ESPNSummaryResponse.self)
        return try XCTUnwrap(decoded as? ESPNSummaryResponse)
    }

    private func status(state: String = "in", period: Int, clock: Double? = nil, shortDetail: String? = nil) -> Status {
        // Status has no memberwise init visible here; go through JSON like the feed does.
        var fields = ["\"period\": \(period)",
                      "\"type\": {\"id\": \"2\", \"state\": \"\(state)\", \"completed\": \(state == "post")\(shortDetail.map { ", \"shortDetail\": \"\($0)\"" } ?? "")}"]
        if let clock { fields.append("\"clock\": \(clock)") }
        return try! JSONDecoder().decode(Status.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private let mlbSituationJSON = """
    {
      "balls": 2, "strikes": 1, "outs": 1,
      "onFirst": true, "onSecond": false, "onThird": true,
      "batter": {"playerId": 1, "athlete": {"displayName": "Juan Soto", "shortName": "J. Soto"}, "summary": "1-3, HR"},
      "pitcher": {"playerId": 2, "athlete": {"displayName": "Emmanuel Clase", "shortName": "E. Clase"}, "summary": "0.2 IP, 0 ER"},
      "lastPlay": {"id": "9", "type": {"id": "1", "text": "Single"}, "text": "Lindor singled to left.", "scoreValue": 0, "team": {"id": "21"}}
    }
    """

    private let nflSituationJSON = """
    {
      "down": 3, "distance": 4, "yardLine": 12,
      "downDistanceText": "3rd & 4 at KC 12", "shortDownDistanceText": "3rd & 4",
      "possessionText": "KC 12", "possession": "12", "isRedZone": true,
      "homeTimeouts": 2, "awayTimeouts": 1,
      "lastPlay": {"id": "77", "type": {"id": "5", "text": "Rush"}, "text": "Kelce 6 yd run", "scoreValue": 0,
                   "team": {"id": "12"},
                   "probability": {"homeWinPercentage": 0.6123456, "awayWinPercentage": 0.3876544, "tiePercentage": 0.0}}
    }
    """

    // MARK: - ESPN decoding

    func testSituationDecodesBaseballFields() throws {
        let s = try decode(Situation.self, mlbSituationJSON)
        XCTAssertEqual(s.balls, 2)
        XCTAssertEqual(s.outs, 1)
        XCTAssertEqual(s.onThird, true)
        XCTAssertEqual(s.batter?.athlete?.shortName, "J. Soto")
        XCTAssertEqual(s.pitcher?.summary, "0.2 IP, 0 ER")
        XCTAssertEqual(s.lastPlay?.team?.id, "21")
    }

    func testSituationToleratesUnexpectedTypes() throws {
        // One bad field must cost only that field — never the scoreboard around it.
        let s = try decode(Situation.self, """
        {"outs": "two", "down": 3, "possession": 12, "lastPlay": {"id": 5}}
        """)
        XCTAssertNil(s.outs)
        XCTAssertEqual(s.down, 3)
        XCTAssertEqual(s.possession, "12")
        XCTAssertNil(s.lastPlay)
    }

    func testRecordedNBAScoreboardCarriesWinProbability() throws {
        let decoded = try JSONLoader.load(file: "NBAScoreboardWithCompletedGames", type: Scoreboard.self)
        let board = try XCTUnwrap(decoded as? Scoreboard)
        let probabilities = board.events.compactMap { $0.competitions?.first?.situation?.lastPlay?.probability }
        XCTAssertFalse(probabilities.isEmpty)
        XCTAssertEqual(try XCTUnwrap(probabilities.first?.homeWinPercentage), 0.927, accuracy: 0.0001)
    }

    // MARK: - GameSituation

    func testBaseballSituationResolvesHalfAndMatchup() throws {
        let s = try XCTUnwrap(GameSituation(
            espn: try decode(Situation.self, mlbSituationJSON),
            status: status(period: 9, shortDetail: "Bot 9th"),
            sport: .mlb, homeTeamID: "21", awayTeamID: "5"
        ))
        XCTAssertEqual(s.inningHalf, .bottom)
        XCTAssertEqual(s.inningHalf?.battingSide, .home)
        XCTAssertEqual(s.runnersOn, 2)
        XCTAssertTrue(s.runnerInScoringPosition)
        XCTAssertEqual(s.batter, "J. Soto")
        XCTAssertEqual(s.lastPlaySide, .home)
        XCTAssertNil(s.down, "baseball must not pick up football fields")
        XCTAssertNil(s.clock, "baseball has no countdown clock")
    }

    func testFootballSituationResolvesPossessionToSide() throws {
        let s = try XCTUnwrap(GameSituation(
            espn: try decode(Situation.self, nflSituationJSON),
            status: status(period: 4, clock: 95),
            sport: .nfl, homeTeamID: "7", awayTeamID: "12"
        ))
        XCTAssertEqual(s.possession, .away)
        XCTAssertEqual(s.isRedZone, true)
        XCTAssertEqual(s.shortDownDistanceText, "3rd & 4")
        XCTAssertEqual(s.clock, 95)
        XCTAssertEqual(s.homeWinProbability, 0.612, "rounded to 3 places so float noise doesn't churn deltas")
        XCTAssertNil(s.tieProbability)
        XCTAssertEqual(try XCTUnwrap(s.awayWinProbability), 0.388, accuracy: 0.0001)
        XCTAssertNil(s.balls)
    }

    func testFootballBetweenPlaysHasNoDownOrRedZone() throws {
        // Captured live from ESPN (Rams @ Eagles, 2026-10-04, after a score).
        let espn = try decode(Situation.self, """
        {"down": -1, "distance": 0, "yardLine": 35, "isRedZone": true, "homeTimeouts": 3, "awayTimeouts": 3,
         "lastPlay": {"id": "1", "type": {"id": "1", "text": "x"}, "text": "x", "scoreValue": 0, "team": {"id": "21"},
                      "probability": {"homeWinPercentage": 0.453}}}
        """)
        let s = try XCTUnwrap(GameSituation(espn: espn, status: status(period: 2, clock: 656), sport: .nfl, homeTeamID: "21", awayTeamID: "14"))
        XCTAssertNil(s.down)
        XCTAssertNil(s.isRedZone, "no snap pending, so no red-zone tag")
        XCTAssertFalse(s.hasFootballState)
        XCTAssertEqual(s.homeWinProbability, 0.453, "win probability still shows")
        XCTAssertNil(LiveActivitySituation(s)?.redZone)
    }

    func testNoSituationUnlessInProgress() throws {
        let espn = try decode(Situation.self, nflSituationJSON)
        XCTAssertNil(GameSituation(espn: espn, status: status(state: "post", period: 4), sport: .nfl, homeTeamID: "7", awayTeamID: "12"))
        XCTAssertNil(GameSituation(espn: espn, status: status(state: "pre", period: 0), sport: .nfl, homeTeamID: "7", awayTeamID: "12"))
    }

    func testInningHalfParsing() {
        XCTAssertEqual(GameSituation.inningHalf(from: "Top 3rd"), .top)
        XCTAssertEqual(GameSituation.inningHalf(from: "Bot 9th"), .bottom)
        XCTAssertEqual(GameSituation.inningHalf(from: "Mid 7th"), .middle)
        XCTAssertEqual(GameSituation.inningHalf(from: "End 4th"), .end)
        XCTAssertNil(GameSituation.inningHalf(from: "Final"))
        XCTAssertNil(GameSituation.inningHalf(from: nil))
    }

    func testCompletedGamesInRecordedBoardCarryNoSituation() throws {
        let decoded = try JSONLoader.load(file: "NBAScoreboardWithCompletedGames", type: Scoreboard.self)
        let board = try XCTUnwrap(decoded as? Scoreboard)
        let games = try XCTUnwrap(LiveEvent(events: board, league: .nba)).events
        XCTAssertFalse(games.isEmpty)
        for game in games where game.strStatus != "in" {
            XCTAssertNil(game.situation, "\(game.strHomeTeam): a finished game must not carry a situation")
        }
    }

    func testSituationEncodedOnlyWhileLive() throws {
        let situation = GameSituation(period: 4, clock: 30, homeWinProbability: 0.55)
        let live = Game(strHomeTeam: "A", strAwayTeam: "B", strStatus: "in", isoDate: nil, situation: situation)
        let liveRoundTrip = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(live))
        XCTAssertEqual(liveRoundTrip.situation, situation)

        // The live merge flips status without being able to clear the field — the
        // encoder is the backstop that keeps a stale situation off the wire.
        let final = live.updated(strStatus: "post")
        let json = String(decoding: try JSONEncoder().encode(final), as: UTF8.self)
        XCTAssertFalse(json.contains("situation"))
    }

    func testOldPayloadWithoutNewFieldsStillDecodes() throws {
        let game = try decode(Game.self, #"{"strHomeTeam":"A","strAwayTeam":"B","strStatus":"in"}"#)
        XCTAssertNil(game.situation)
        XCTAssertNil(game.excitement)
    }

    // MARK: - Clutch moments

    private func detect(_ sport: SportType, _ s: GameSituation, previous: GameSituation? = nil, home: Int, away: Int) -> ClutchMoment? {
        ClutchMoment.detect(sport: sport, situation: s, previous: previous,
                            homeScore: home, awayScore: away, homeName: "Home", awayName: "Away")
    }

    func testTyingRunAtThePlate() {
        // Bottom 9th, down 2, one on: the batter is the tying run.
        let s = GameSituation(period: 9, inningHalf: .bottom, outs: 2, onFirst: true)
        let moment = detect(.mlb, s, home: 3, away: 5)
        XCTAssertEqual(moment?.kind, .tyingRunAtPlate)
        XCTAssertEqual(moment?.title, "Home: tying run at the plate")
        XCTAssertEqual(moment?.key, "tying-9bottom")
    }

    func testWinningRunAtThePlate() {
        // Bottom 9th, down 1, two on: the batter would win it.
        let s = GameSituation(period: 9, inningHalf: .bottom, outs: 1, onFirst: true, onSecond: true)
        XCTAssertEqual(detect(.mlb, s, home: 4, away: 5)?.title, "Home: winning run at the plate")
        // Same spot for the visitors in the top half is a go-ahead run, not a winning one.
        let top = GameSituation(period: 9, inningHalf: .top, outs: 1, onFirst: true, onSecond: true)
        XCTAssertEqual(detect(.mlb, top, home: 5, away: 4)?.title, "Away: go-ahead run at the plate")
    }

    func testNoTyingRunWhenTooFarBack() {
        // Down 4 with one on: the tying run isn't up yet.
        let s = GameSituation(period: 9, inningHalf: .bottom, outs: 0, onFirst: true)
        XCTAssertNil(detect(.mlb, s, home: 1, away: 5))
    }

    func testGoAheadRunInScoringPositionWhenTied() {
        let s = GameSituation(period: 10, inningHalf: .top, outs: 1, onSecond: true)
        let moment = detect(.mlb, s, home: 2, away: 2)
        XCTAssertEqual(moment?.kind, .goAheadRunInScoringPosition)
        XCTAssertEqual(moment?.title, "Away: go-ahead run in scoring position")
    }

    func testBasesLoadedLateAndClose() {
        let s = GameSituation(period: 7, inningHalf: .top, outs: 1, onFirst: true, onSecond: true, onThird: true)
        XCTAssertEqual(detect(.mlb, s, home: 4, away: 2)?.kind, .basesLoaded)
        // Early, or a blowout, isn't a moment.
        let early = GameSituation(period: 3, inningHalf: .top, outs: 1, onFirst: true, onSecond: true, onThird: true)
        XCTAssertNil(detect(.mlb, early, home: 4, away: 2))
        XCTAssertNil(detect(.mlb, s, home: 9, away: 2))
    }

    func testMiddleOfInningIsNeverAMoment() {
        let s = GameSituation(period: 9, inningHalf: .middle, outs: 3, onFirst: true, onSecond: true, onThird: true)
        XCTAssertNil(detect(.mlb, s, home: 2, away: 2))
    }

    func testRedZoneInOneScoreFourthQuarter() {
        let s = GameSituation(period: 4, clock: 300, shortDownDistanceText: "2nd & 6", possession: .away, isRedZone: true)
        let moment = detect(.nfl, s, home: 20, away: 14)
        XCTAssertEqual(moment?.kind, .redZone)
        XCTAssertEqual(moment?.title, "Away in the red zone")
        XCTAssertEqual(moment?.body, "Q4 · 2nd & 6 · Away 14, Home 20")
        // Same drive on the next tick → same key, so it alerts once.
        let nextTick = GameSituation(period: 4, clock: 280, shortDownDistanceText: "3rd & 2", possession: .away, isRedZone: true)
        XCTAssertEqual(detect(.nfl, nextTick, home: 20, away: 14)?.key, moment?.key)
        // Two-score game: not a moment.
        XCTAssertNil(detect(.nfl, s, home: 30, away: 14))
    }

    func testBasketballCrunchTime() {
        let s = GameSituation(period: 4, clock: 95)
        XCTAssertEqual(detect(.basketball, s, home: 101, away: 99)?.kind, .crunchTime)
        XCTAssertEqual(detect(.basketball, s, home: 101, away: 101)?.title, "Tied in the final 2 minutes")
        XCTAssertNil(detect(.basketball, GameSituation(period: 4, clock: 400), home: 101, away: 99))
        XCTAssertNil(detect(.basketball, s, home: 110, away: 99))
        XCTAssertEqual(detect(.basketball, GameSituation(period: 5, clock: 60), home: 1, away: 0)?.key, "crunch-5")
    }

    func testHockeyFinalMinutesOneGoal() {
        XCTAssertEqual(detect(.hockey, GameSituation(period: 3, clock: 100), home: 2, away: 3)?.kind, .finalMinutesOneGoal)
        XCTAssertNil(detect(.hockey, GameSituation(period: 3, clock: 100), home: 2, away: 2))
        XCTAssertNil(detect(.hockey, GameSituation(period: 2, clock: 100), home: 2, away: 3))
    }

    func testLateFavoriteFlip() {
        let before = GameSituation(period: 4, clock: 400, homeWinProbability: 0.62)
        let after = GameSituation(period: 4, clock: 380, homeWinProbability: 0.41)
        let moment = detect(.nfl, after, previous: before, home: 17, away: 21)
        XCTAssertEqual(moment?.kind, .favoriteFlipped)
        XCTAssertEqual(moment?.title, "Away now favored")
        XCTAssertEqual(moment?.body, "59% to win · Away 21, Home 17")
        // A wobble across 50% isn't a flip worth an alert.
        let wobble = GameSituation(period: 4, clock: 380, homeWinProbability: 0.49)
        XCTAssertNil(detect(.nfl, wobble, previous: GameSituation(period: 4, homeWinProbability: 0.52), home: 17, away: 17))
        // Nor is a first-half flip.
        XCTAssertNil(detect(.nfl, GameSituation(period: 2, homeWinProbability: 0.41),
                            previous: GameSituation(period: 2, homeWinProbability: 0.62), home: 7, away: 10))
    }

    func testNCAATournamentPlaysHalves() {
        let s = GameSituation(period: 2, clock: 60)
        let moment = ClutchMoment.detect(sport: .basketball, league: .ncaaMBBTournament, situation: s, previous: nil,
                                         homeScore: 70, awayScore: 70, homeName: "Home", awayName: "Away")
        XCTAssertEqual(moment?.kind, .crunchTime, "the 2nd half is the final period")
        XCTAssertEqual(moment?.body, "H2 · Away 70, Home 70")
        XCTAssertNil(detect(.basketball, s, home: 70, away: 70), "an NBA 2nd quarter is not crunch time")
    }

    func testPeriodNames() {
        XCTAssertEqual(Leagues.nba.periodName(4), "Q4")
        XCTAssertEqual(Leagues.nba.periodName(6), "2OT")
        XCTAssertEqual(Leagues.ncaaMBBTournament.periodName(2), "H2")
        XCTAssertEqual(Leagues.ncaaMBBTournament.periodName(3), "OT")
        XCTAssertEqual(Leagues.nhl.periodName(5), "2OT")
        XCTAssertEqual(Leagues.mlb.periodName(11), "11th")
    }

    func testBoundariesUseRecordedPeriodsNotPosition() {
        // Q2 had no win-probability entries: the first boundary is the start of Q3.
        let series = WinProbabilitySeries(home: [0.5, 0.6, 0.7], periodStarts: [1, 2], startPeriods: [3, 4])
        XCTAssertEqual(series.boundaries(league: .nba).map(\.label), ["Q3", "Q4"])
        // Series cached before periods were recorded fall back to position.
        XCTAssertEqual(WinProbabilitySeries(home: [0.5, 0.6], periodStarts: [1]).boundaries(league: .nba).map(\.label), ["Q2"])
    }

    func testOverlayingKeepsWhatTheFresherSourceLacks() {
        let espn = GameSituation(period: 7, inningHalf: .top, outs: 0, batter: "J. Soto", batterLine: "1-3, HR",
                                 pitcher: "E. Clase", pitcherLine: "1.0 IP", homeWinProbability: 0.4)
        // statsapi: same pitcher, a new batter, two outs, no lines or win probability.
        let statsapi = GameSituation(period: 7, inningHalf: .top, outs: 2, onFirst: true, batter: "P. Alonso", pitcher: "E. Clase")
        let merged = espn.overlaying(statsapi)
        XCTAssertEqual(merged.outs, 2)
        XCTAssertEqual(merged.onFirst, true)
        XCTAssertEqual(merged.batter, "P. Alonso")
        XCTAssertNil(merged.batterLine, "Soto's line must not follow Alonso")
        XCTAssertEqual(merged.pitcherLine, "1.0 IP", "same pitcher keeps his line")
        XCTAssertEqual(merged.homeWinProbability, 0.4)
    }

    func testSoccerHasNoClutchMoments() {
        // Goals already alert through the score-change path.
        XCTAssertNil(detect(.soccer, GameSituation(period: 2), home: 1, away: 1))
    }

    // MARK: - Win probability & excitement

    func testSeriesPeriodsFromRealNFLSummary() throws {
        let s = try summary("nfl")
        XCTAssertTrue(s.plays?.isEmpty ?? true, "football sends its plays under drives")
        let series = try XCTUnwrap(s.extras(league: .nfl, isFinal: true).winProbability)
        XCTAssertEqual(series.home.count, 196)
        XCTAssertEqual(series.periodStarts.count, 3, "four quarters → three boundaries")
        XCTAssertEqual(series.periodStarts, series.periodStarts.sorted())
        XCTAssertEqual(series.boundaries(league: .nfl).map(\.label), ["Q2", "Q3", "Q4"])
        XCTAssertEqual(try XCTUnwrap(series.home.last), 1.0, accuracy: 0.0001, "home (CLE) won")
    }

    func testFootballPlaysComeFromDrives() throws {
        // ESPN's NFL summary has no top-level plays; they're grouped by drive.
        let nfl = try summary("nfl")
        XCTAssertTrue(nfl.playsFromDrives)
        XCTAssertEqual(nfl.allPlays.count, 195)
        XCTAssertEqual(nfl.allPlays.first?.period?.number, 1)
        XCTAssertEqual(nfl.allPlays.map { $0.period?.number ?? 0 }, nfl.allPlays.map { $0.period?.number ?? 0 }.sorted(),
                       "drives flatten oldest first")

        let nba = try summary("nba")
        XCTAssertFalse(nba.playsFromDrives)
        XCTAssertEqual(nba.allPlays.count, nba.plays?.count)
    }

    func testExcitementAnchorsMapToPercentiles() throws {
        let nfl = try XCTUnwrap(ExcitementIndex.anchors(for: .nfl))
        XCTAssertEqual(ExcitementIndex.score(raw: nfl.p10, anchors: nfl), 10)
        XCTAssertEqual(ExcitementIndex.score(raw: nfl.p50, anchors: nfl), 50)
        XCTAssertEqual(ExcitementIndex.score(raw: nfl.p90, anchors: nfl), 90)
        XCTAssertEqual(ExcitementIndex.score(raw: 0, anchors: nfl), 0)
        XCTAssertEqual(ExcitementIndex.score(raw: 1000, anchors: nfl), 100)
    }

    func testLateSwingsCountDouble() {
        // The same single 0.4 swing, early versus in the final quarter of the series.
        let early = [0.5, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9]
        let late = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.9]
        XCTAssertEqual(ExcitementIndex.raw(early), 0.4, accuracy: 1e-9)
        XCTAssertEqual(ExcitementIndex.raw(late), 0.8, accuracy: 1e-9)
    }

    func testRealGamesScoreSensibly() throws {
        // CLE 27–24 PIT (three-point game) and IND 137–134 NY (three-point game, 553 plays):
        // both close finishes, so both should land in the top half.
        let nfl = try summary("nfl").extras(league: .nfl, isFinal: true)
        let nba = try summary("nba").extras(league: .nba, isFinal: true)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(nfl.excitement), 50)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(nba.excitement), 50)
        // LAA 6–1 at PIT: a five-run game sits in the lower half.
        let mlb = try summary("mlb").extras(league: .mlb, isFinal: true)
        XCTAssertLessThan(try XCTUnwrap(mlb.excitement), 50)
    }

    func testNoExcitementUntilFinalOrWithoutWinProbability() throws {
        XCTAssertNil(try summary("nfl").extras(league: .nfl, isFinal: false).excitement)
        // ESPN publishes no win probability for soccer.
        let soccer = try summary("soccer").extras(league: .English_Premier_League, isFinal: true)
        XCTAssertNil(soccer.winProbability)
        XCTAssertNil(soccer.excitement)
    }

    func testTiers() {
        XCTAssertEqual(ExcitementTier(score: 95), .classic)
        XCTAssertEqual(ExcitementTier(score: 80), .thriller)
        XCTAssertEqual(ExcitementTier(score: 60), .close)
        XCTAssertEqual(ExcitementTier(score: 10), .ordinary)
        XCTAssertTrue(ExcitementTier.thriller.isWorthWatching)
        XCTAssertFalse(ExcitementTier.close.isWorthWatching)
    }

    // MARK: - Team stat comparison

    func testFootballBoxScore() throws {
        let stats = try XCTUnwrap(try summary("nfl").extras(league: .nfl, isFinal: true).teamStats)
        XCTAssertEqual(stats.rows.first?.label, "Total Yards")
        let turnovers = try XCTUnwrap(stats.rows.first { $0.name == "turnovers" })
        XCTAssertEqual(turnovers.lowerIsBetter, true)
        let possession = try XCTUnwrap(stats.rows.first { $0.name == "possessionTime" })
        XCTAssertEqual(possession.away, "31:11", "PIT is the away side in this fixture")
        XCTAssertEqual(possession.awayValue, 31 * 60 + 11)
    }

    func testBasketballBoxScoreParsesMadeAttempted() throws {
        let stats = try XCTUnwrap(try summary("nba").extras(league: .nba, isFinal: true).teamStats)
        let fieldGoals = try XCTUnwrap(stats.rows.first { $0.label == "Field Goals" })
        XCTAssertEqual(fieldGoals.away, "50-97")
        XCTAssertEqual(fieldGoals.awayValue, 50)
        XCTAssertEqual(stats.rows.first { $0.label == "FG %" }?.away, "52%")
    }

    func testBaseballBoxScoreReadsNestedCategories() throws {
        let stats = try XCTUnwrap(try summary("mlb").extras(league: .mlb, isFinal: true).teamStats)
        XCTAssertEqual(stats.rows.first { $0.name == "batting.hits" }?.away, "12")
        XCTAssertEqual(stats.rows.first { $0.name == "batting.runnersLeftOnBase" }?.away, "15")
        XCTAssertEqual(stats.rows.first { $0.name == "fielding.errors" }?.lowerIsBetter, true)
    }

    func testSoccerBoxScore() throws {
        let stats = try XCTUnwrap(try summary("soccer").extras(league: .English_Premier_League, isFinal: true).teamStats)
        XCTAssertEqual(stats.rows.first?.label, "Possession")
        let possession = try XCTUnwrap(stats.rows.first)
        XCTAssertTrue(possession.home.hasSuffix("%"))
        // ESPN sends both sides' passPct as "0.9"; the counts say 396/451 and 529/590.
        let passing = try XCTUnwrap(stats.rows.first { $0.name == "passPct" })
        XCTAssertEqual(passing.home, "88%")
        XCTAssertEqual(passing.away, "90%")
    }

    func testNumericParsing() {
        typealias Row = TeamStatComparison.Row
        XCTAssertEqual(Row.numeric("22/40"), 22)
        XCTAssertEqual(Row.numeric("8-50"), 8)
        XCTAssertEqual(Row.numeric("42.7%"), 42.7)
        XCTAssertEqual(Row.numeric("1,271"), 1271)
        XCTAssertEqual(Row.numeric("31:11"), 1871)
        XCTAssertEqual(Row.numeric("-3"), -3, "a leading minus is a sign, not a separator")
        XCTAssertNil(Row.numeric("--"))
    }

    // MARK: - CachedPlays compatibility

    func testLegacyCachedPlaysDecodeWithoutExtras() throws {
        let legacy = #"{"eventID":"1","lastPlayId":"2","plays":[],"isFinal":true,"fetchedAt":0}"#
        let cached = try decode(CachedPlays.self, legacy)
        XCTAssertNil(cached.winProbability)
        XCTAssertNil(cached.teamStats)
        XCTAssertTrue(cached.extras.isEmpty)
    }
}
