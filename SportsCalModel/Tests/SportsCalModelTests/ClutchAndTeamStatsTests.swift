import XCTest
@testable import SportsCalModel

/// Edges of `ClutchMoment.detect` and `TeamStatComparison` that `LiveSituationTests`
/// doesn't pin down.
final class ClutchMomentEdgeTests: XCTestCase {

    private func detect(_ sport: SportType, _ s: GameSituation, previous: GameSituation? = nil,
                        home: Int, away: Int, league: Leagues? = nil) -> ClutchMoment? {
        ClutchMoment.detect(sport: sport, league: league, situation: s, previous: previous,
                            homeScore: home, awayScore: away, homeName: "HOM", awayName: "AWY")
    }

    func testThreeOutsIsNeverABaseballMoment() {
        let s = GameSituation(period: 9, inningHalf: .bottom, outs: 3, onFirst: true, onSecond: true, onThird: true)
        XCTAssertNil(detect(.mlb, s, home: 3, away: 4))
    }

    func testBaseballNeedsAKnownHalf() {
        XCTAssertNil(detect(.mlb, GameSituation(period: 9, outs: 1, onFirst: true), home: 3, away: 4))
    }

    func testBaseballMomentBodyAndKey() {
        let s = GameSituation(period: 8, inningHalf: .top, outs: 1, onFirst: true, onSecond: true, onThird: true)
        let moment = detect(.mlb, s, home: 5, away: 3)
        XCTAssertEqual(moment?.kind, .basesLoaded)
        XCTAssertEqual(moment?.title, "Bases loaded for AWY")
        XCTAssertEqual(moment?.body, "Top 8th, 1 out · AWY 3, HOM 5")
        XCTAssertEqual(moment?.key, "loaded-8top")
    }

    func testTyingRunOutranksBasesLoaded() {
        // 9th, down 3, bases loaded: the batter is the go-ahead run → tying-run rule wins.
        let s = GameSituation(period: 9, inningHalf: .top, outs: 2, onFirst: true, onSecond: true, onThird: true)
        XCTAssertEqual(detect(.mlb, s, home: 6, away: 3)?.kind, .tyingRunAtPlate)
    }

    func testRedZoneNeedsPossessionAndEightPointGame() {
        let noSide = GameSituation(period: 4, isRedZone: true)
        XCTAssertNil(detect(.nfl, noSide, home: 10, away: 7))
        let s = GameSituation(period: 4, possession: .home, isRedZone: true)
        XCTAssertEqual(detect(.nfl, s, home: 10, away: 18)?.kind, .redZone, "8 is still one score")
        XCTAssertNil(detect(.nfl, s, home: 10, away: 19))
        XCTAssertNil(detect(.nfl, GameSituation(period: 3, possession: .home, isRedZone: true), home: 10, away: 7))
    }

    func testRedZoneKeyChangesWhenTheScoreDoes() {
        let s = GameSituation(period: 4, possession: .home, isRedZone: true)
        XCTAssertNotEqual(detect(.nfl, s, home: 10, away: 7)?.key, detect(.nfl, s, home: 10, away: 14)?.key)
    }

    func testOvertimeCountsAsFinalPeriod() {
        let ot = GameSituation(period: 5, possession: .away, isRedZone: true)
        XCTAssertEqual(detect(.nfl, ot, home: 20, away: 20)?.body, "OT · AWY 20, HOM 20")
        XCTAssertEqual(detect(.hockey, GameSituation(period: 4, clock: 60), home: 2, away: 1)?.kind, .finalMinutesOneGoal)
    }

    func testCrunchTimeBoundaries() {
        XCTAssertNotNil(detect(.basketball, GameSituation(period: 4, clock: 120), home: 100, away: 97))
        XCTAssertNil(detect(.basketball, GameSituation(period: 4, clock: 120.5), home: 100, away: 97))
        XCTAssertNil(detect(.basketball, GameSituation(period: 4, clock: 60), home: 100, away: 96))
        XCTAssertNil(detect(.basketball, GameSituation(period: 4), home: 100, away: 100), "no clock, no crunch time")
    }

    func testFlipRequiresFifteenPointMoveAndAPreviousReading() {
        let now = GameSituation(period: 4, homeWinProbability: 0.40)
        XCTAssertNil(detect(.basketball, now, home: 90, away: 95), "no previous reading")
        XCTAssertNil(detect(.basketball, now, previous: GameSituation(period: 4, homeWinProbability: 0.54),
                            home: 90, away: 95), "14-point move")
        let flip = detect(.basketball, now, previous: GameSituation(period: 4, homeWinProbability: 0.56),
                          home: 90, away: 95)
        XCTAssertEqual(flip?.kind, .favoriteFlipped)
        XCTAssertEqual(flip?.key, "flip-4-away")
        XCTAssertEqual(flip?.body, "60% to win · AWY 95, HOM 90")
    }

    func testBaseballFlipFromTheSeventh() {
        let before = GameSituation(period: 7, inningHalf: .top, outs: 0, homeWinProbability: 0.30)
        let after = GameSituation(period: 7, inningHalf: .bottom, outs: 0, homeWinProbability: 0.70)
        XCTAssertEqual(detect(.mlb, after, previous: before, home: 4, away: 3)?.title, "HOM now favored")
        let sixth = GameSituation(period: 6, inningHalf: .bottom, outs: 0, homeWinProbability: 0.70)
        XCTAssertNil(detect(.mlb, sixth, previous: before, home: 4, away: 3))
    }

    func testIndividualSportsHaveNoMoments() {
        let s = GameSituation(period: 4, clock: 10, homeWinProbability: 0.9)
        for sport in [SportType.golf, .tennis, .racing, .soccer] {
            XCTAssertNil(detect(sport, s, previous: GameSituation(period: 4, homeWinProbability: 0.1), home: 1, away: 0))
        }
    }

    func testOrdinals() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 101, 111].map(ClutchMoment.ordinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "101st", "111th"])
    }

    func testDefaultLeagues() {
        XCTAssertEqual(ClutchMoment.defaultLeague(for: .basketball), .nba)
        XCTAssertEqual(ClutchMoment.defaultLeague(for: .hockey), .nhl)
        XCTAssertNil(ClutchMoment.defaultLeague(for: .soccer))
        XCTAssertNil(Leagues.English_Premier_League.regulationPeriods)
        XCTAssertEqual(Leagues.English_Premier_League.periodName(2), "2")
    }
}

final class TeamStatComparisonEdgeTests: XCTestCase {

    private func box(_ json: String) throws -> ESPNSummaryBoxscore {
        try JSONDecoder().decode(ESPNSummaryBoxscore.self, from: Data(json.utf8))
    }

    private func side(_ homeAway: String, _ stats: [(String, String)]) -> String {
        let list = stats.map { #"{"name":"\#($0.0)","displayValue":"\#($0.1)"}"# }.joined(separator: ",")
        return #"{"homeAway":"\#(homeAway)","statistics":[\#(list)]}"#
    }

    func testNilWithoutBothSides() throws {
        XCTAssertNil(TeamStatComparison(boxscore: nil, sport: .basketball))
        let homeOnly = try box(#"{"teams":[\#(side("home", [("assists", "20")]))]}"#)
        XCTAssertNil(TeamStatComparison(boxscore: homeOnly, sport: .basketball))
    }

    func testNilWhenNothingCuratedIsPresent() throws {
        let b = try box(#"{"teams":[\#(side("home", [("mystery", "1")])),\#(side("away", [("mystery", "2")]))]}"#)
        XCTAssertNil(TeamStatComparison(boxscore: b, sport: .basketball))
    }

    func testRowsFollowSpecOrderAndSkipOneSidedStats() throws {
        let b = try box("""
        {"teams":[\(side("away", [("turnovers", "12"), ("assists", "25"), ("totalRebounds", "40")])),\
        \(side("home", [("assists", "22"), ("totalRebounds", "44")]))]}
        """)
        let stats = try XCTUnwrap(TeamStatComparison(boxscore: b, sport: .basketball))
        XCTAssertEqual(stats.rows.map(\.name), ["totalRebounds", "assists"], "spec order; turnovers only on one side")
        XCTAssertEqual(stats.rows.first?.home, "44")
        XCTAssertEqual(stats.rows.first?.away, "40")
        XCTAssertNil(stats.rows.first?.lowerIsBetter, "only lower-is-better rows carry the flag")
    }

    func testPercentFormattingAndRatio() throws {
        let b = try box("""
        {"teams":[\(side("home", [("possessionPct", "61.4"), ("accuratePasses", "300"), ("totalPasses", "400")])),\
        \(side("away", [("possessionPct", "38.6%"), ("accuratePasses", "150"), ("totalPasses", "0")]))]}
        """)
        let stats = try XCTUnwrap(TeamStatComparison(boxscore: b, sport: .soccer))
        let possession = try XCTUnwrap(stats.rows.first { $0.name == "possessionPct" })
        XCTAssertEqual(possession.home, "61.4%")
        XCTAssertEqual(possession.away, "38.6%", "no doubled sign")
        XCTAssertNil(stats.rows.first { $0.name == "passPct" }, "a zero denominator yields no row")
    }

    func testIndividualSportsHaveNoSpecs() {
        XCTAssertTrue(TeamStatComparison.specs(for: .golf).isEmpty)
        XCTAssertTrue(TeamStatComparison.specs(for: .tennis).isEmpty)
        XCTAssertTrue(TeamStatComparison.specs(for: .racing).isEmpty)
    }

    func testBoxscoreToleratesMalformedFields() throws {
        let b = try box(#"{"teams":[{"homeAway":1,"statistics":"x"},\#(side("away", [("assists", "1")]))]}"#)
        XCTAssertEqual(b.teams?.count, 2)
        XCTAssertNil(b.teams?.first?.homeAway)
        XCTAssertNil(TeamStatComparison(boxscore: b, sport: .basketball))
    }

    func testCodableRoundTrip() throws {
        let stats = TeamStatComparison(rows: [
            .init(name: "turnovers", label: "Turnovers", home: "12", away: "9", lowerIsBetter: true),
            .init(name: "assists", label: "Assists", home: "25", away: "22"),
        ])
        let data = try JSONEncoder().encode(stats)
        XCTAssertEqual(try JSONDecoder().decode(TeamStatComparison.self, from: data), stats)
        XCTAssertEqual(stats.rows.map(\.id), ["turnovers", "assists"])
        XCTAssertEqual(stats.rows[0].homeValue, 12)
    }
}
