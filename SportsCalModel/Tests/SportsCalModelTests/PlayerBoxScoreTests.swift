//
//  PlayerBoxScoreTests.swift
//  SportsCalModelTests
//
//  `PlayerBoxScore` and `ScoringSummary` built from trimmed real ESPN summaries
//  (Nov 2026): WSH @ ATL (NBA), ANA @ CGY and a shootout (NHL), JAX @ BAL (NFL),
//  MIL @ TB (MLB).
//

import XCTest
@testable import SportsCalModel

final class PlayerBoxScoreTests: XCTestCase {

    private func summary(_ file: String) throws -> ESPNSummaryResponse {
        try XCTUnwrap(try JSONLoader.load(file: file, type: ESPNSummaryResponse.self) as? ESPNSummaryResponse)
    }

    // MARK: Basketball

    func testBasketballSplitsStartersBenchAndDNPs() throws {
        let box = try XCTUnwrap(PlayerBoxScore(boxscore: try summary("BoxScore-nba").boxscore, sport: .basketball))
        XCTAssertEqual(box.teams.count, 2)
        XCTAssertEqual(box.away?.abbreviation, "WSH")
        XCTAssertEqual(box.home?.abbreviation, "ATL")

        let away = try XCTUnwrap(box.away)
        XCTAssertEqual(away.groups.map(\.id), ["starters", "bench"])
        let starters = try XCTUnwrap(away.group("starters"))
        XCTAssertEqual(starters.labels.first, "MIN")
        XCTAssertEqual(starters.labels.count, 14)
        XCTAssertTrue(starters.rows.allSatisfy(\.isStarter))
        XCTAssertNil(starters.totals, "The team line goes under the bench")

        let first = try XCTUnwrap(starters.rows.first)
        XCTAssertEqual(first.name, "A. Dybantsa")
        XCTAssertEqual(first.jersey, "4")
        XCTAssertEqual(first.position, "F")
        XCTAssertEqual(first.headshot, "https://a.espncdn.com/i/headshots/nba/players/full/5142718.png")
        XCTAssertEqual(first.stats.count, 14)

        let bench = try XCTUnwrap(away.group("bench"))
        XCTAssertEqual(bench.totals?.count, 14)
        let dnp = try XCTUnwrap(bench.rows.first(where: \.isDNP))
        XCTAssertTrue(dnp.stats.isEmpty)
        XCTAssertEqual(dnp.reason, "COACH'S DECISION")
        XCTAssertNil(dnp.starter)
    }

    func testNoBoxScoreForSoccerOrMissingPlayers() throws {
        let nba = try summary("BoxScore-nba")
        XCTAssertNil(PlayerBoxScore(boxscore: nba.boxscore, sport: .soccer))
        XCTAssertNil(PlayerBoxScore(boxscore: nil, sport: .basketball))
        XCTAssertNil(ScoringSummary(summary: nba, sport: .basketball))
    }

    // MARK: Hockey

    func testHockeyCuratesSkaterAndGoalieColumns() throws {
        let box = try XCTUnwrap(PlayerBoxScore(boxscore: try summary("BoxScore-nhl").boxscore, sport: .hockey))
        let away = try XCTUnwrap(box.away)
        // ESPN's empty "skaters" table is dropped.
        XCTAssertEqual(away.groups.map(\.id), ["forwards", "defenses", "goalies"])
        XCTAssertEqual(away.group("forwards")?.labels, ["G", "A", "+/-", "S", "HT", "BS", "PIM", "FO%", "TOI"])
        XCTAssertEqual(away.group("defenses")?.title, "Defense")

        let goalies = try XCTUnwrap(away.group("goalies"))
        XCTAssertEqual(goalies.labels, ["SA", "GA", "SV", "SV%", "TOI"])
        XCTAssertEqual(goalies.descriptions?.first, "Total shots against.")
        let goalie = try XCTUnwrap(goalies.rows.first)
        XCTAssertEqual(goalie.stats.count, 5)
        XCTAssertEqual(goalie.position, "G")
    }

    func testHockeySummaryHasScorersAssistsTagsAndPenalties() throws {
        let scoring = try XCTUnwrap(ScoringSummary(summary: try summary("BoxScore-nhl"), sport: .hockey))
        let goals = scoring.entries.filter { !$0.isPenalty }
        let penalties = scoring.entries.filter(\.isPenalty)
        XCTAssertFalse(penalties.isEmpty)
        XCTAssertFalse(goals.isEmpty)

        XCTAssertEqual(goals.count, 8)
        let first = try XCTUnwrap(goals.first)
        XCTAssertEqual(first.player, "W. Stromgren")
        XCTAssertEqual(first.assists, ["Z. Parekh", "Y. Kuznetsov"])
        XCTAssertNil(first.tags, "Even strength carries no tag")
        XCTAssertEqual(first.text, "Backhand")
        XCTAssertNotNil(first.side)
        XCTAssertNotNil(first.teamAbbreviation)

        let powerPlay = try XCTUnwrap(goals.first { $0.player == "J. Farabee" })
        XCTAssertEqual(powerPlay.tags, ["PP"])
        XCTAssertEqual(powerPlay.assists, ["Z. Parekh", "M. Frost"])
        XCTAssertEqual(powerPlay.text, "Snap Shot")

        let emptyNet = try XCTUnwrap(goals.first { $0.player == "N. Nesterenko" })
        XCTAssertEqual(emptyNet.tags, ["EN"])
        XCTAssertNil(emptyNet.assists)

        let penalty = try XCTUnwrap(penalties.first)
        XCTAssertEqual(penalty.penaltyMinutes, 2)
        XCTAssertFalse(penalty.text.isEmpty)

        // Only goals and penalties; the shots in the fixture are skipped.
        XCTAssertEqual(scoring.entries.count, goals.count + penalties.count)
    }

    func testShootoutGoalsGroupLast() throws {
        let scoring = try XCTUnwrap(ScoringSummary(summary: try summary("Scoring-nhl-shootout"), sport: .hockey))
        let groups = scoring.byPeriod
        XCTAssertEqual(groups.last?.period, -1)
        XCTAssertTrue(groups.last?.entries.allSatisfy(\.isShootout) ?? false)
        XCTAssertEqual(groups.dropLast().map(\.period), groups.dropLast().map(\.period).sorted())
    }

    func testShotKindParsing() {
        XCTAssertEqual(ScoringSummary.shotKind(from: "Jack Quinn Goal (9) Backhand, assists: Owen Power (10)"), "Backhand")
        XCTAssertEqual(ScoringSummary.shotKind(from: "Valeri Nichushkin Goal Backhand"), "Backhand")
        XCTAssertNil(ScoringSummary.shotKind(from: "Faceoff won"))
    }

    // MARK: Football

    func testFootballGroupsAndDerivedShortNames() throws {
        let box = try XCTUnwrap(PlayerBoxScore(boxscore: try summary("BoxScore-nfl").boxscore, sport: .nfl))
        let away = try XCTUnwrap(box.away)
        XCTAssertEqual(away.abbreviation, "JAX")
        XCTAssertEqual(away.groups.map(\.id), ["passing", "rushing", "receiving", "defensive", "interceptions", "kicking", "punting"])
        let passing = try XCTUnwrap(away.group("passing"))
        XCTAssertEqual(passing.labels.first, "C/ATT")
        XCTAssertEqual(passing.rows.first?.name, "T. Lawrence")
        XCTAssertEqual(passing.rows.first?.fullName, "Trevor Lawrence")
        XCTAssertEqual(passing.totals?.first, "16/26")
    }

    func testFootballScoringSummaryUsesScoringPlays() throws {
        let scoring = try XCTUnwrap(ScoringSummary(summary: try summary("BoxScore-nfl"), sport: .nfl))
        let first = try XCTUnwrap(scoring.entries.first)
        XCTAssertEqual(first.text, "Bhayshul Tuten 1 Yd Rush (Cam Little Kick)")
        XCTAssertEqual(first.tags, ["TD"])
        XCTAssertEqual(first.period, 1)
        XCTAssertEqual(first.clock, "11:20")
        XCTAssertEqual(first.side, "away")
        XCTAssertEqual(first.teamAbbreviation, "JAX")
        XCTAssertEqual(first.awayScore, 7)
        XCTAssertEqual(first.homeScore, 0)
    }

    // MARK: Baseball

    func testBaseballBattingPitchingAndDecisions() throws {
        let box = try XCTUnwrap(PlayerBoxScore(boxscore: try summary("BoxScore-mlb").boxscore, sport: .mlb))
        let away = try XCTUnwrap(box.away)
        XCTAssertEqual(away.groups.map(\.id), ["batting", "pitching"])
        XCTAssertEqual(away.group("batting")?.labels, ["AB", "R", "H", "RBI", "HR", "BB", "K", "AVG", "OBP", "SLG"])
        XCTAssertEqual(away.group("batting")?.rows.first?.position, "LF")
        let pitching = try XCTUnwrap(away.group("pitching"))
        XCTAssertEqual(pitching.labels, ["IP", "H", "R", "ER", "BB", "K", "HR", "PC-ST", "ERA"])
        XCTAssertEqual(pitching.rows.first?.note, "W, 2-0")
        XCTAssertEqual(pitching.rows.first?.stats.first, "5.2")
    }

    func testBaseballScoringByInning() throws {
        let scoring = try XCTUnwrap(ScoringSummary(summary: try summary("BoxScore-mlb"), sport: .mlb))
        XCTAssertEqual(scoring.entries.count, 3)
        let first = try XCTUnwrap(scoring.entries.first)
        XCTAssertEqual(first.period, 2)
        XCTAssertEqual(first.half, "Top")
        XCTAssertEqual(first.side, "away")
        XCTAssertEqual(first.teamAbbreviation, "MIL")
        XCTAssertTrue(first.text.hasPrefix("Pratt singled"))
    }

    // MARK: Payload plumbing

    func testExtrasCarryBoxAndSummaryAndRoundTrip() throws {
        let extras = try summary("BoxScore-nhl").extras(league: .nhl, isFinal: false)
        XCTAssertNotNil(extras.players)
        XCTAssertNotNil(extras.scoringSummary)
        XCTAssertFalse(extras.isEmpty)

        let cached = CachedPlays(eventID: "1", lastPlayId: "x", plays: [], isFinal: true, fetchedAt: Date(), extras: extras)
        let decoded = try JSONDecoder().decode(CachedPlays.self, from: JSONEncoder().encode(cached))
        XCTAssertEqual(decoded.players, extras.players)
        XCTAssertEqual(decoded.scoringSummary, extras.scoringSummary)

        let slim = cached.withoutPlayerDetail
        XCTAssertNil(slim.players)
        XCTAssertNil(slim.scoringSummary)
    }

    func testOldPayloadWithoutPlayersStillDecodes() throws {
        let json = #"{"eventID":"1","lastPlayId":"","plays":[],"isFinal":false,"fetchedAt":0}"#
        let decoded = try JSONDecoder().decode(CachedPlays.self, from: Data(json.utf8))
        XCTAssertNil(decoded.players)
        XCTAssertNil(decoded.scoringSummary)
    }
}
