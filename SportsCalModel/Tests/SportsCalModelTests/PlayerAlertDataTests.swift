//
//  PlayerAlertDataTests.swift
//  SportsCalModelTests
//
//  The data custom player alerts need, from trimmed real ESPN summaries (Nov 2026):
//  who made each play (`Play.participants`) and each player's live numbers
//  (`PlayerLiveStatLine`). Fixtures: BoxScore-nba (WSH @ ATL), BoxScore-nfl (JAX @ BAL),
//  PlayParticipants-nhl (PHI @ EDM), PlayParticipants-mlb (MIL @ TB),
//  MLBPitchSummary.
//

import XCTest
@testable import SportsCalModel

final class PlayerAlertDataTests: XCTestCase {

    private func summary(_ file: String) throws -> ESPNSummaryResponse {
        try XCTUnwrap(try JSONLoader.load(file: file, type: ESPNSummaryResponse.self) as? ESPNSummaryResponse)
    }

    private func line(_ lines: [PlayerLiveStatLine], _ athleteID: String,
                      file: StaticString = #filePath, line: UInt = #line) throws -> PlayerLiveStatLine {
        try XCTUnwrap(lines.first { $0.athleteID == athleteID }, "No stat line for \(athleteID)", file: file, line: line)
    }

    // MARK: - Play participants

    func testBasketballParticipantsDecodeInOrderWithoutRoles() throws {
        let plays = try XCTUnwrap(try summary("BoxScore-nba").plays)
        let three = try XCTUnwrap(plays.first { $0.id == "4019092879" })
        XCTAssertEqual(three.participants?.map(\.athleteID), ["4278039", "4869342"], "Shooter, then the assister")
        XCTAssertEqual(three.participants?.compactMap(\.role), [], "ESPN sends no basketball roles")
        XCTAssertTrue(plays.allSatisfy { $0.participants?.isEmpty == false })
    }

    func testBasketballParticipantNamesComeFromTheBoxScore() throws {
        let summary = try summary("BoxScore-nba")
        XCTAssertNil(summary.plays?.first?.participants?.first?.name, "ESPN doesn't name basketball participants")
        let named = summary.allPlaysWithNamedParticipants
        let three = try XCTUnwrap(named.first { $0.id == "4019092879" })
        // A player the trimmed box doesn't list keeps his ID and no name.
        XCTAssertEqual(three.participants?.map(\.name), ["N. Alexander-Walker", nil])
        XCTAssertEqual(three.participants?.last?.athleteID, "4869342")
    }

    func testHockeyParticipantsCarryRolesAndNames() throws {
        let plays = try XCTUnwrap(try summary("PlayParticipants-nhl").plays)
        let goal = try XCTUnwrap(plays.first { $0.type?.text == "Goal" })
        XCTAssertEqual(goal.participants, [
            PlayParticipant(athleteID: "3114727", name: "L. Draisaitl", role: "scorer"),
            PlayParticipant(athleteID: "3895074", name: "C. McDavid", role: "assister"),
            PlayParticipant(athleteID: "4352722", name: "E. Bouchard", role: "assister"),
        ])
        let faceoff = try XCTUnwrap(plays.first)
        XCTAssertEqual(faceoff.participants?.first?.role, "face-off-winner")
        XCTAssertNil(faceoff.participants?.last?.role, "The losing side of a face-off has no type")
    }

    func testBaseballParticipantsCarryBatterPitcherAndRunners() throws {
        let summary = try summary("PlayParticipants-mlb")
        let plays = summary.allPlaysWithNamedParticipants
        let scoring = try XCTUnwrap(plays.first { $0.scoringPlay == true })
        XCTAssertEqual(scoring.participants?.map(\.role), ["pitcher", "batter", "onThird"])
        XCTAssertEqual(scoring.participants?.first { $0.role == "batter" }?.athleteID, "5149101")
        XCTAssertEqual(scoring.participants?.first { $0.role == "batter" }?.name, "C. Pratt")

        let pitches = try XCTUnwrap(try self.summary("MLBPitchSummary").plays)
        let first = try XCTUnwrap(pitches.first { $0.participants != nil })
        XCTAssertEqual(first.participants?.map(\.role), ["pitcher", "batter"])
    }

    func testFootballDrivePlaysHaveNoParticipants() throws {
        // ESPN's site summary sends football drive plays with only `teamParticipants`
        // ($ref links to the core API), so football player plays need another source.
        let plays = try summary("NFLDrivesSummary").allPlays
        XCTAssertFalse(plays.isEmpty)
        XCTAssertTrue(plays.allSatisfy { $0.participants == nil })
    }

    func testOddParticipantIsDroppedNotThePlay() throws {
        let json = """
        {"id": "1", "text": "Goal", "participants": [
            {"athlete": {"displayName": "No ID"}, "type": "scorer"},
            {"athlete": {"id": 12345}, "type": "assister"},
            "garbage",
            {"athlete": {"id": "678", "shortName": "A. Player"}}
        ]}
        """
        let play = try JSONDecoder().decode(Play.self, from: Data(json.utf8))
        XCTAssertEqual(play.text, "Goal")
        XCTAssertEqual(play.participants, [
            PlayParticipant(athleteID: "12345", role: "assister"),
            PlayParticipant(athleteID: "678", name: "A. Player"),
        ])

        let notAList = try JSONDecoder().decode(Play.self, from: Data(#"{"id": "2", "participants": {"a": 1}}"#.utf8))
        XCTAssertNil(notAList.participants)
        let empty = try JSONDecoder().decode(Play.self, from: Data(#"{"id": "3", "participants": []}"#.utf8))
        XCTAssertNil(empty.participants)
    }

    func testExistingFieldsStillDecodeStrictly() {
        // Same as the synthesized decoder this replaced: a play without an ID fails.
        XCTAssertThrowsError(try JSONDecoder().decode(Play.self, from: Data(#"{"text": "x"}"#.utf8)))
    }

    // MARK: Compatibility

    /// `Play` as shipped before participants (3.3 and earlier), with its synthesized decoder.
    private struct OldPlay: Codable, Equatable {
        let id: String
        let text: String?
        let scoringPlay: Bool?
        let awayScore: Int?
        let homeScore: Int?
        let clock: Play.PlayClock?
        let period: Play.PlayPeriod?
        let type: Play.PlayType?
        let summaryType: String?
        let atBatId: String?
    }

    func testOldClientsDecodePlaysWithParticipants() throws {
        let play = Play(
            id: "9", text: "Draisaitl scores", scoringPlay: true, awayScore: 1, homeScore: 2,
            clock: .init(displayValue: "4:12"), period: .init(number: 2), type: .init(id: "505", text: "Goal"),
            participants: [PlayParticipant(athleteID: "3114727", name: "L. Draisaitl", role: "scorer")]
        )
        let data = try JSONEncoder().encode(play)
        let old = try JSONDecoder().decode(OldPlay.self, from: data)
        XCTAssertEqual(old.id, "9")
        XCTAssertEqual(old.type?.text, "Goal")
        XCTAssertEqual(old.homeScore, 2)
    }

    func testNewClientsDecodePlaysWithoutParticipants() throws {
        let old = OldPlay(id: "9", text: "Ball", scoringPlay: false, awayScore: 0, homeScore: 0, clock: nil,
                          period: .init(number: 1, type: "Top"), type: .init(id: "1", text: "Ball"),
                          summaryType: "P", atBatId: "77")
        let play = try JSONDecoder().decode(Play.self, from: try JSONEncoder().encode(old))
        XCTAssertNil(play.participants)
        XCTAssertEqual(play.atBatId, "77")
        XCTAssertEqual(play.period?.type, "Top")
    }

    func testParticipantsRoundTripInOwnShape() throws {
        let play = Play(id: "1", participants: [
            PlayParticipant(athleteID: "42", name: "S. Curry", role: nil),
            PlayParticipant(athleteID: "43", role: "assister"),
        ])
        let data = try JSONEncoder().encode(play)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""athleteID":"42""#))
        XCTAssertFalse(text.contains("athlete\":{"), "Encodes its own shape, not ESPN's")
        XCTAssertEqual(try JSONDecoder().decode(Play.self, from: data), play)
    }

    // MARK: Payload

    func testCachedPlaysNeverCarriesParticipants() throws {
        let summary = try summary("PlayParticipants-nhl")
        XCTAssertTrue(summary.allPlays.contains { $0.participants != nil })
        let cached = CachedPlays(eventID: "1", lastPlayId: "x", plays: summary.allPlays, isFinal: false, fetchedAt: Date())
        XCTAssertTrue(cached.plays.allSatisfy { $0.participants == nil })
        let encoded = String(decoding: try JSONEncoder().encode(cached), as: UTF8.self)
        XCTAssertFalse(encoded.contains("participants"))
        XCTAssertEqual(cached.plays.map(\.id), summary.allPlays.map(\.id))
        XCTAssertEqual(cached.plays.map(\.text), summary.allPlays.map(\.text))
    }

    // MARK: - Live stat lines

    func testBasketballStatLines() throws {
        let lines = try summary("BoxScore-nba").playerStatLines(sport: .basketball)
        let dybantsa = try line(lines, "5142718")
        XCTAssertEqual(dybantsa.name, "AJ Dybantsa")
        XCTAssertEqual(dybantsa.teamID, "27")
        XCTAssertEqual(dybantsa.stats["points"], 11)
        XCTAssertEqual(dybantsa.stats["rebounds"], 9)
        XCTAssertEqual(dybantsa.stats["assists"], 3)
        XCTAssertEqual(dybantsa.stats["minutes"], 36)
        XCTAssertEqual(dybantsa.stats["fieldGoalsMade"], 3)
        XCTAssertEqual(dybantsa.stats["fieldGoalsAttempted"], 13)
        XCTAssertEqual(dybantsa.stats["threePointFieldGoalsMade"], 1)
        XCTAssertEqual(dybantsa.stats["freeThrowsAttempted"], 4)
        XCTAssertEqual(dybantsa.stats["plusMinus"], -5)
        XCTAssertNil(dybantsa.stats["fieldGoalsMade-fieldGoalsAttempted"], "Paired columns are split")
        XCTAssertEqual(Set(lines.map(\.teamID)).count, 2)

        // Players who sat have no line.
        let box = try XCTUnwrap(PlayerBoxScore(boxscore: try summary("BoxScore-nba").boxscore, sport: .basketball))
        let dnpIDs = box.teams.flatMap(\.groups).flatMap(\.rows).filter(\.isDNP).map(\.id)
        XCTAssertFalse(dnpIDs.isEmpty)
        XCTAssertTrue(dnpIDs.allSatisfy { id in !lines.contains { $0.athleteID == id } })
    }

    func testFootballStatLinesArePrefixedByTable() throws {
        let lines = try summary("BoxScore-nfl").playerStatLines(sport: .nfl)
        let lawrence = try line(lines, "4360310")
        XCTAssertEqual(lawrence.stats["passing.passingYards"], 242)
        XCTAssertEqual(lawrence.stats["passing.completions"], 16)
        XCTAssertEqual(lawrence.stats["passing.passingAttempts"], 26)
        XCTAssertEqual(lawrence.stats["passing.passingTouchdowns"], 1)
        XCTAssertEqual(lawrence.stats["passing.sacks"], 0)
        XCTAssertNil(lawrence.stats["passingYards"])

        let abdullah = try line(lines, "2576336")
        XCTAssertEqual(abdullah.stats["rushing.rushingYards"], 30)
        XCTAssertEqual(abdullah.stats["kickReturns.kickReturnYards"], 24, "A player's tables merge into one line")
        XCTAssertEqual(lines.filter { $0.athleteID == "2576336" }.count, 1)

        XCTAssertEqual(try line(lines, "3916433").stats["receiving.receivingYards"], 65)
        XCTAssertEqual(try line(lines, "3916433").stats["receiving.receptions"], 4)
        XCTAssertEqual(try line(lines, "3050073").stats["defensive.sacks"], 1)
        XCTAssertEqual(try line(lines, "4242149").stats["interceptions.interceptions"], 1)
        XCTAssertEqual(try line(lines, "4686361").stats["kicking.fieldGoalsMade"], 4)
        XCTAssertEqual(try line(lines, "4686361").stats["kicking.fieldGoalAttempts"], 4)
    }

    func testBaseballStatLinesSplitBattingAndPitching() throws {
        let lines = try summary("PlayParticipants-mlb").playerStatLines(sport: .mlb)
        let pratt = try line(lines, "5149101")
        XCTAssertEqual(pratt.stats["batting.hits"], 2)
        XCTAssertEqual(pratt.stats["batting.atBats"], 3)
        XCTAssertEqual(pratt.stats["batting.RBIs"], 2)
        XCTAssertEqual(pratt.stats["batting.homeRuns"], 0)
        XCTAssertEqual(try XCTUnwrap(pratt.stats["batting.avg"]), 0.354, accuracy: 0.0001)

        let misiorowski = try line(lines, "5080761")
        XCTAssertEqual(misiorowski.stats["pitching.strikeouts"], 2)
        XCTAssertEqual(misiorowski.stats["pitching.outs"], 17, "5.2 innings is 17 outs")
        XCTAssertEqual(try XCTUnwrap(misiorowski.stats["pitching.inningsPitched"]), 5 + 2.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(misiorowski.stats["pitching.pitches"], 86)
        XCTAssertEqual(misiorowski.stats["pitching.strikes"], 58)
        XCTAssertEqual(misiorowski.stats["pitching.hits"], 2)
        XCTAssertNil(misiorowski.stats["batting.hits"], "A pitcher's hits allowed aren't his own")

        XCTAssertEqual(try line(lines, "42584").teamID, "30")
    }

    func testHockeyStatLines() throws {
        let lines = try summary("PlayParticipants-nhl").playerStatLines(sport: .hockey)
        let draisaitl = try line(lines, "3114727")
        XCTAssertEqual(draisaitl.teamID, "6")
        XCTAssertEqual(draisaitl.stats["goals"], 2)
        XCTAssertEqual(draisaitl.stats["assists"], 1)
        XCTAssertEqual(draisaitl.stats["shotsTotal"], 3)
        XCTAssertEqual(draisaitl.stats["plusMinus"], 3)
        XCTAssertEqual(draisaitl.stats["faceoffPercent"], 66.7)
        XCTAssertEqual(draisaitl.stats["timeOnIce"], 18 * 60 + 31, "Times are seconds")
        XCTAssertNil(draisaitl.stats["ytdGoals"], "Season totals aren't live stats")

        let jarry = try line(lines, "3042020")
        XCTAssertEqual(jarry.stats["saves"], 34)
        XCTAssertEqual(jarry.stats["goalsAgainst"], 2)
        XCTAssertEqual(try XCTUnwrap(jarry.stats["savePct"]), 0.944, accuracy: 0.0001)
        XCTAssertEqual(try line(lines, "3096237").stats["plusMinus"], -1)
    }

    func testNoStatLinesForSportsWithoutPlayerTables() throws {
        let nba = try summary("BoxScore-nba")
        XCTAssertTrue(nba.playerStatLines(sport: .soccer).isEmpty)
        XCTAssertTrue(nba.playerStatLines(sport: .golf).isEmpty)
        XCTAssertTrue(PlayerLiveStatLine.lines(boxscore: nil, sport: .basketball).isEmpty)
    }

    func testStatValueParsing() {
        XCTAssertEqual(PlayerLiveStatLine.number("12"), 12)
        XCTAssertEqual(PlayerLiveStatLine.number("-3"), -3)
        XCTAssertEqual(PlayerLiveStatLine.number("+5"), 5)
        XCTAssertEqual(PlayerLiveStatLine.number(".923"), 0.923)
        XCTAssertEqual(PlayerLiveStatLine.number("55.6%"), 55.6)
        XCTAssertEqual(PlayerLiveStatLine.number("60:00"), 3600)
        XCTAssertNil(PlayerLiveStatLine.number("--"))
        XCTAssertNil(PlayerLiveStatLine.number(""))
        XCTAssertNil(PlayerLiveStatLine.number("INF"), "ESPN's ERA for a pitcher with no outs")
        XCTAssertNil(PlayerLiveStatLine.number("inf"))
        XCTAssertNil(PlayerLiveStatLine.number("nan"))
        XCTAssertNil(PlayerLiveStatLine.number("1:75"))

        XCTAssertTrue(PlayerLiveStatLine.parse(key: "fieldGoalsMade-fieldGoalsAttempted", value: "5").isEmpty,
                      "A paired column with one value is dropped, not guessed")
        XCTAssertTrue(PlayerLiveStatLine.parse(key: "fullInnings.partInnings", value: "4.5").isEmpty)
        XCTAssertEqual(PlayerLiveStatLine.parse(key: "fullInnings.partInnings", value: "0.1").map(\.1), [1.0 / 3, 1])
    }

    func testStatLinesRoundTrip() throws {
        let lines = try summary("PlayParticipants-nhl").playerStatLines(sport: .hockey)
        XCTAssertFalse(lines.isEmpty)
        let decoded = try JSONDecoder().decode([PlayerLiveStatLine].self, from: try JSONEncoder().encode(lines))
        XCTAssertEqual(decoded, lines)
    }
}
