//
//  FantasyTests.swift
//  SportsCalModelTests
//
//  Fixture: CHI 39 @ DET 35, Thanksgiving 2026 (ESPN 401873081), trimmed to the box
//  score and scoring plays.
//

import XCTest
@testable import SportsCalModel

final class FantasyTests: XCTestCase {
    typealias K = FantasyStatKey.NFL

    private func lines() throws -> [FantasyPlayerLine] {
        let summary = try XCTUnwrap(JSONLoader.load(file: "NFLFantasySummary", type: ESPNSummaryResponse.self) as? ESPNSummaryResponse)
        return FantasyStatLines.lines(summary: summary, sport: .nfl, eventID: "401873081")
    }

    private func line(_ name: String, in lines: [FantasyPlayerLine]) throws -> FantasyPlayerLine {
        try XCTUnwrap(lines.first { $0.name == name }, "no line for \(name)")
    }

    func testSkillPlayersScoreUnderEachPreset() throws {
        let all = try lines()
        let gibbs = try line("Jahmyr Gibbs", in: all)
        // 205 rush yds, 3 rush TD, 5 rec, 47 rec yds.
        XCTAssertEqual(FantasyScoring.nflStandard.points(gibbs.stats), 43.2)
        XCTAssertEqual(FantasyScoring.nflHalfPPR.points(gibbs.stats), 45.7)
        XCTAssertEqual(FantasyScoring.nflPPR.points(gibbs.stats), 48.2)

        let goff = try line("Jared Goff", in: all)
        // 313 pass yds, 1 TD, 1 INT, 10 rush yds, 3 rec yds; a recovered fumble isn't lost.
        XCTAssertEqual(FantasyScoring.nflHalfPPR.points(goff.stats), 15.82)

        let odunze = try line("Rome Odunze", in: all)
        XCTAssertEqual(FantasyScoring.nflHalfPPR.points(odunze.stats), 23.7)
    }

    func testTwoPointConversionComesFromScoringPlays() throws {
        let caleb = try line("Caleb Williams", in: try lines())
        XCTAssertEqual(caleb.stats[K.twoPointConversions], 1)
        // 345 pass yds, 2 TD, 15 rush yds, 2-pt run.
        XCTAssertEqual(FantasyScoring.nflHalfPPR.points(caleb.stats), 25.3)
    }

    func testKickersScoreByDistance() throws {
        let all = try lines()
        let bates = try line("Jake Bates", in: all)
        XCTAssertEqual(bates.stats[K.fieldGoals0to39], 1) // 24 yards
        XCTAssertEqual(bates.stats[K.fieldGoals40to49], 1) // 40 yards
        // 3 + 4, 3 of 4 extra points.
        XCTAssertEqual(FantasyScoring.nflHalfPPR.points(bates.stats), 9)

        let santos = try line("Cairo Santos", in: all)
        XCTAssertEqual(FantasyScoring.nflHalfPPR.points(santos.stats), 8)
    }

    func testDefenseLines() throws {
        let all = try lines()
        let det = try XCTUnwrap(all.first { $0.athleteID == "dst-8" })
        XCTAssertEqual(det.position, "DST")
        XCTAssertEqual(det.stats[K.dstPointsAllowed], 39)
        XCTAssertEqual(det.stats[K.dstSacks], 4)
        XCTAssertEqual(det.stats[K.dstSafeties], 1)
        XCTAssertEqual(det.stats[K.dstInterceptions], 0)

        let chi = try XCTUnwrap(all.first { $0.athleteID == "dst-3" })
        XCTAssertEqual(chi.stats[K.dstPointsAllowed], 35)
        XCTAssertEqual(chi.stats[K.dstInterceptions], 1)
        XCTAssertEqual(chi.stats[K.dstSacks], 1)
        XCTAssertEqual(chi.opponentAbbreviation, "DET")
        // 1 sack + 1 INT×2, 35 allowed → −3.
        XCTAssertEqual(FantasyScoring.nflHalfPPR.points(chi.stats), 1 + 2 - 3 + 2 * (chi.stats[K.dstFumblesRecovered] ?? 0) + 6 * (chi.stats[K.dstTouchdowns] ?? 0))
    }

    func testLinesCarryTeamContext() throws {
        let gibbs = try line("Jahmyr Gibbs", in: try lines())
        XCTAssertEqual(gibbs.teamAbbreviation, "DET")
        XCTAssertEqual(gibbs.opponentAbbreviation, "CHI")
        XCTAssertEqual(gibbs.isHome, true)
        XCTAssertNotNil(gibbs.headshot)
        XCTAssertEqual(gibbs.statSummary, "21 CAR, 205 YD, 3 TD · 5/5 REC, 47 YD")
    }

    // MARK: Text parsing

    func testFieldGoalText() {
        XCTAssertEqual(FantasyStatLines.fieldGoal(in: "Jake Bates 44 Yd Field Goal")?.yards, 44)
        XCTAssertEqual(FantasyStatLines.fieldGoal(in: "Ka'imi Fairbairn 52 Yd Field Goal ")?.kicker, "Ka'imi Fairbairn")
        XCTAssertNil(FantasyStatLines.fieldGoal(in: "Jahmyr Gibbs 1 Yd Rush (Jake Bates Kick)"))
    }

    func testTwoPointText() {
        XCTAssertEqual(FantasyStatLines.twoPointScorers(in: "Rome Odunze 41 Yd pass from Caleb Williams (Caleb Williams Run for Two-Point Conversion)"), ["Caleb Williams"])
        XCTAssertEqual(FantasyStatLines.twoPointScorers(in: "X 5 Yd pass from Jared Goff (Jared Goff Pass to Amon-Ra St. Brown for Two-Point Conversion)"), ["Jared Goff", "Amon-Ra St. Brown"])
        XCTAssertEqual(FantasyStatLines.twoPointScorers(in: "X 1 Yd Rush (Two-Point Pass Conversion Failed)"), [])
        XCTAssertEqual(FantasyStatLines.twoPointScorers(in: "X 1 Yd Rush (Jake Bates Kick)"), [])
    }

    func testNameNormalization() {
        XCTAssertEqual(FantasyStatLines.normalized("Amon-Ra St. Brown"), FantasyStatLines.normalized("amon ra st brown"))
        XCTAssertEqual(FantasyStatLines.normalized("Marvin Harrison Jr."), FantasyStatLines.normalized("Marvin Harrison"))
    }

    // MARK: Verdicts

    private func evaluation(points stats: [String: Double], average: [String: Double]?, progress: Double, state: String = "in") -> FantasyEvaluation {
        let line = FantasyPlayerLine(athleteID: "1", name: "P", position: "WR", teamID: "1", eventID: "1",
                                     stats: stats, gameState: state, gameProgress: progress,
                                     seasonAverage: average, seasonGames: average == nil ? nil : 8)
        return FantasyEvaluation(line: line, scoring: .nflPPR)
    }

    func testStinkerIsPaceAdjusted() {
        // Averages 18 PPR (8 rec, 100 yds); has 3 at the half → expected 9 → stinker.
        let average = [K.receptions: 8.0, K.receivingYards: 100]
        let half = evaluation(points: [K.receptions: 1, K.receivingYards: 20], average: average, progress: 0.5)
        XCTAssertEqual(half.points, 3)
        XCTAssertEqual(half.expectedSoFar, 9)
        XCTAssertEqual(half.verdict, .stinker)

        // Same line after one quarter isn't judged yet.
        XCTAssertEqual(evaluation(points: [K.receptions: 1, K.receivingYards: 20], average: average, progress: 0.25).verdict, .steady)
        // A big final day is a stud.
        XCTAssertEqual(evaluation(points: [K.receptions: 10, K.receivingYards: 160, K.receivingTouchdowns: 2], average: average, progress: 1, state: "post").verdict, .stud)
    }

    func testLowVolumePlayersArentJudged() {
        // Averages 4 points: a zero isn't a stinker.
        let quiet = evaluation(points: [:], average: [K.receptions: 2, K.receivingYards: 20], progress: 1, state: "post")
        XCTAssertEqual(quiet.verdict, .steady)
        XCTAssertNil(evaluation(points: [K.receptions: 1], average: nil, progress: 1).delta)
    }

    // MARK: Imports

    func testSleeperScoringMapsWeightsTiersAndBonuses() {
        let settings: [String: Double] = [
            "pass_yd": 0.04, "pass_td": 4, "pass_int": -1, "rec": 0.5, "rec_yd": 0.1, "rush_yd": 0.1,
            "fgm_0_19": 3, "fgm_30_39": 3, "fgm_40_49": 4, "fgm_50p": 5, "xpm": 1,
            "pts_allow_0": 10, "pts_allow_35p": -4, "bonus_rec_yd_100": 2, "bonus_rec_te": 0.5,
        ]
        let (scoring, unsupported) = SleeperScoring.scoring(settings: settings, id: "sleeper.1", name: "L")
        XCTAssertEqual(scoring.weights[K.interceptionsThrown], -1)
        XCTAssertEqual(scoring.weights[K.receptions], 0.5)
        XCTAssertEqual(unsupported, ["bonus_rec_te 0.5"])
        XCTAssertEqual(scoring.points([K.receivingYards: 104, K.receptions: 6]), 10.4 + 3 + 2)
        XCTAssertEqual(scoring.points([K.dstPointsAllowed: 0]), 10)
        XCTAssertEqual(scoring.points([K.dstPointsAllowed: 40]), -4)
    }

    func testESPNScoringAndDefenseIDs() {
        let items: [ESPNFantasy.LeagueResponse.ScoringItem] = [
            .init(statId: 3, points: 0.04), .init(statId: 53, points: 1), .init(statId: 42, points: 0.1),
            .init(statId: 89, points: 5), .init(statId: 124, points: -3), .init(statId: 8, points: 1),
            .init(statId: 999, points: 2),
        ]
        let (scoring, unsupported) = ESPNFantasy.scoring(items: items, id: "espn.1", name: "L")
        XCTAssertEqual(scoring.weights[K.passingYards]!, 0.08, accuracy: 0.0001) // 0.04 + 1 per 25
        XCTAssertEqual(scoring.points([K.dstPointsAllowed: 39]), -3)
        XCTAssertEqual(unsupported, ["ESPN stat 999 2"])
        XCTAssertEqual(ESPNFantasy.athleteID(playerID: -16008), "dst-8")
        XCTAssertEqual(ESPNFantasy.athleteID(playerID: 4429795), "4429795")
    }

    func testScoringRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(FantasyScoring.nflHalfPPR)
        XCTAssertEqual(try JSONDecoder().decode(FantasyScoring.self, from: data), .nflHalfPPR)
    }

    func testFormat() {
        XCTAssertEqual(FantasyScoring.format(18), "18")
        XCTAssertEqual(FantasyScoring.format(18.4), "18.4")
        XCTAssertEqual(FantasyScoring.format(15.82), "15.82")
        XCTAssertEqual(FantasyScoring.format(-1), "-1")
    }
}
