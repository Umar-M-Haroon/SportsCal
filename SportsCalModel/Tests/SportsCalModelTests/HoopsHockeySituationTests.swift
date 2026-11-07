import XCTest
@testable import SportsCalModel

final class BasketballPlayTallyTests: XCTestCase {
    /// POR @ LAL, 2026-11-06 (ESPN 401909294), trimmed to type/team/period/score.
    private func realGame() throws -> ESPNSummaryResponse {
        let url = URL(fileURLWithPath: #file).deletingLastPathComponent()
            .appendingPathComponent("MockJSON/Summary-nba-401909294-plays.json")
        return try JSONDecoder().decode(ESPNSummaryResponse.self, from: Data(contentsOf: url))
    }

    /// ESPN's core situation endpoint said home 10, away 9 team fouls in the 4th.
    func testFoulsMatchESPNsOwnCount() throws {
        let summary = try realGame()
        let teamIDs = try XCTUnwrap(summary.playTeamIDs)
        XCTAssertEqual(teamIDs.count, summary.allPlays.count)
        let tally = try XCTUnwrap(BasketballPlayTally(
            plays: summary.allPlays, teamIDs: teamIDs, homeTeamID: "13", awayTeamID: "22", league: .nba
        ))
        XCTAssertEqual(tally.period, 4)
        XCTAssertEqual(tally.homeFouls, 10)
        XCTAssertEqual(tally.awayFouls, 9)
        // Lakers called 3 of their 4th-quarter allowance of 4 and lost a challenge, which
        // costs the 4th; the Blazers called all 7 of the game's.
        XCTAssertEqual(tally.homeTimeouts, 0)
        XCTAssertEqual(tally.awayTimeouts, 0)
    }

    func testTimeoutsOnlyForTheNBA() throws {
        let summary = try realGame()
        let tally = try XCTUnwrap(BasketballPlayTally(
            plays: summary.allPlays, teamIDs: summary.playTeamIDs ?? [], homeTeamID: "13", awayTeamID: "22", league: .wnba
        ))
        XCTAssertNil(tally.homeTimeouts)
    }

    private func scoring(_ scores: [(Int, Int)]) -> [Play] {
        scores.enumerated().map { index, score in
            Play(id: "\(index)", awayScore: score.1, homeScore: score.0, period: .init(number: 4))
        }
    }

    func testRunIsUnansweredPointsSinceTheOtherSideScored() {
        let plays = scoring([(0, 0), (50, 52), (50, 54), (52, 54), (55, 54), (57, 54), (57, 54), (60, 54), (62, 54)])
        let run = BasketballPlayTally.currentRun(plays)
        XCTAssertEqual(run?.side, .home)
        XCTAssertEqual(run?.points, 12, "50-54 → 62-54")
        let tally = BasketballPlayTally(plays: plays, teamIDs: [], homeTeamID: nil, awayTeamID: nil, league: .nba)
        XCTAssertEqual(tally?.runSide, .home)
        XCTAssertEqual(tally?.runPoints, 12)
    }

    func testShortRunsDontCount() {
        let plays = scoring([(0, 0), (2, 0), (2, 3), (4, 3)])
        XCTAssertEqual(BasketballPlayTally.currentRun(plays)?.points, 2)
        XCTAssertNil(BasketballPlayTally(plays: plays, teamIDs: [], homeTeamID: nil, awayTeamID: nil, league: .nba)?.runSide)
    }

    func testFoulTypes() {
        XCTAssertTrue(BasketballPlayTally.isTeamFoul("shooting foul"))
        XCTAssertTrue(BasketballPlayTally.isTeamFoul("offensive foul"))
        XCTAssertTrue(BasketballPlayTally.isTeamFoul("offensive charge"))
        XCTAssertFalse(BasketballPlayTally.isTeamFoul("offensive foul turnover"))
        XCTAssertFalse(BasketballPlayTally.isTeamFoul("technical foul"))
        XCTAssertFalse(BasketballPlayTally.isTeamFoul("defensive 3-seconds technical"))
    }

    func testBallSideFromTheLastPlay() {
        XCTAssertEqual(GameSituation.basketballBallSide(afterPlay: "Defensive Rebound", scoreValue: 0, by: .home), .home)
        XCTAssertEqual(GameSituation.basketballBallSide(afterPlay: "Jump Shot", scoreValue: 2, by: .home), .away)
        XCTAssertEqual(GameSituation.basketballBallSide(afterPlay: "Bad Pass\nTurnover", scoreValue: 0, by: .away), .home)
        XCTAssertEqual(GameSituation.basketballBallSide(afterPlay: "Free Throw - 2 of 2", scoreValue: 1, by: .home), .away)
        XCTAssertNil(GameSituation.basketballBallSide(afterPlay: "Free Throw - 1 of 2", scoreValue: 1, by: .home))
        XCTAssertNil(GameSituation.basketballBallSide(afterPlay: "Jump Shot", scoreValue: 0, by: .home), "a miss doesn't say")
        XCTAssertNil(GameSituation.basketballBallSide(afterPlay: "Personal Foul", scoreValue: 0, by: .home))
    }

    func testBonus() {
        var s = GameSituation(period: 4)
        s.homeFouls = 5
        s.awayFouls = 4
        XCTAssertEqual(s.isInBonus(.away, league: .nba), true, "home's 5th foul puts away in the bonus")
        XCTAssertEqual(s.isInBonus(.home, league: .nba), false)
        s.period = 5
        XCTAssertEqual(s.isInBonus(.home, league: .nba), true, "overtime's limit is 4")
        s.period = 2
        s.homeFouls = 10
        XCTAssertTrue(s.isInDoubleBonus(.away, league: .ncaaMBBTournament))
        XCTAssertNil(s.isInBonus(.home, league: nil))
    }

    func testTallyAppliesFoulsOnlyInItsPeriod() {
        let tally = BasketballPlayTally(period: 3, homeFouls: 4, awayFouls: 2, runSide: .away, runPoints: 9)
        var next = GameSituation(period: 4)
        tally.apply(to: &next)
        XCTAssertNil(next.homeFouls)
        XCTAssertEqual(next.runPoints, 9)
        var same = GameSituation(period: 3)
        tally.apply(to: &same)
        XCTAssertEqual(same.homeFouls, 4)
    }
}

final class HockeySituationTests: XCTestCase {
    func testSituationCode() {
        var s = GameSituation()
        XCTAssertTrue(s.applyNHLSituationCode("1451"))
        XCTAssertEqual(s.powerPlaySide, .home)
        XCTAssertEqual(s.strengthText, "5-on-4")
        XCTAssertNil(s.emptyNetSide)

        XCTAssertTrue(s.applyNHLSituationCode("0651"))
        XCTAssertEqual(s.emptyNetSide, .away)
        XCTAssertNil(s.powerPlaySide, "the extra attacker isn't a power play")

        XCTAssertTrue(s.applyNHLSituationCode("1331"))
        XCTAssertNil(s.powerPlaySide, "3-on-3 overtime is even")

        XCTAssertFalse(s.applyNHLSituationCode("15x1"))
        XCTAssertFalse(s.applyNHLSituationCode("155"))
    }

    func testPowerPlayClockText() {
        var s = GameSituation()
        s.applyNHLSituationCode("1541")
        s.powerPlayClock = 102
        XCTAssertEqual(s.powerPlaySide, .away)
        XCTAssertEqual(s.powerPlayClockText, "1:42")
        s.setEvenStrength()
        XCTAssertNil(s.powerPlayClockText)
    }

    /// A partial source's even strength must clear the power play, not leave it.
    func testOverlayTakesStrengthWhole() {
        var old = GameSituation(period: 2)
        old.applyNHLSituationCode("1451")
        old.powerPlayClock = 80
        var fresh = GameSituation(period: 2, clock: 600)
        fresh.setEvenStrength()
        let merged = old.overlaying(fresh)
        XCTAssertNil(merged.powerPlaySide)
        XCTAssertNil(merged.powerPlayClock)

        let unrelated = old.overlaying(GameSituation(period: 2, clock: 590))
        XCTAssertEqual(unrelated.powerPlaySide, .home, "a fresh copy without strength keeps the old")
    }

    func testESPNReplacementCarriesStrengthUntilTheScoreMoves() {
        var old = GameSituation(period: 2)
        old.applyNHLSituationCode("1451")
        let espn = GameSituation(period: 2, clock: 500)
        let kept = espn.carryingSupplementalState(from: old, sport: .hockey, oldScore: (1, 1), newScore: (1, 1))
        XCTAssertEqual(kept.powerPlaySide, .home)
        let afterGoal = espn.carryingSupplementalState(from: old, sport: .hockey, oldScore: (1, 1), newScore: (2, 1))
        XCTAssertNil(afterGoal.powerPlaySide)
        let nextPeriod = GameSituation(period: 3).carryingSupplementalState(from: old, sport: .hockey, oldScore: (1, 1), newScore: (1, 1))
        XCTAssertNil(nextPeriod.powerPlaySide)
    }

    func testESPNReplacementCarriesBasketballRunsAndFouls() {
        var old = GameSituation(period: 4)
        old.homeFouls = 3
        old.awayFouls = 5
        old.runSide = .away
        old.runPoints = 10
        let espn = GameSituation(period: 4, clock: 300)
        let extended = espn.carryingSupplementalState(from: old, sport: .basketball, oldScore: (80, 70), newScore: (80, 73))
        XCTAssertEqual(extended.runPoints, 13)
        XCTAssertEqual(extended.awayFouls, 5)
        let broken = espn.carryingSupplementalState(from: old, sport: .basketball, oldScore: (80, 70), newScore: (82, 70))
        XCTAssertNil(broken.runSide)
        let football = espn.carryingSupplementalState(from: old, sport: .nfl, oldScore: (0, 0), newScore: (0, 0))
        XCTAssertNil(football.homeFouls)
    }

    func testLiveActivityCarriesPowerPlayAndEmptyNet() throws {
        var s = GameSituation(period: 3)
        s.applyNHLSituationCode("1560")
        let la = try XCTUnwrap(LiveActivitySituation(s))
        XCTAssertEqual(la.emptyNet, .home)
        XCTAssertNil(la.powerPlay)
        var even = GameSituation(period: 1)
        even.setEvenStrength()
        XCTAssertNil(LiveActivitySituation(even), "nothing to show at even strength")
    }

    func testNewFieldsStayOffTheWireWhenUnset() throws {
        let data = try JSONEncoder().encode(GameSituation(period: 2))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("Skaters"))
        XCTAssertFalse(json.contains("Fouls"))
    }
}
