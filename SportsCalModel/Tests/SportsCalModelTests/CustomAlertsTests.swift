//
//  CustomAlertsTests.swift
//  SportsCalModelTests
//
//  Custom alert rules: which plays count as which play type (recorded ESPN summaries
//  from PlayerAlertDataTests' fixtures), milestone crossing, the free cap, and lenient
//  decoding of the registration the app posts.
//

import XCTest
@testable import SportsCalModel

final class CustomAlertsTests: XCTestCase {

    private func summary(_ file: String) throws -> ESPNSummaryResponse {
        try XCTUnwrap(try JSONLoader.load(file: file, type: ESPNSummaryResponse.self) as? ESPNSummaryResponse)
    }

    private func play(_ text: String, type: String = "Play", scoring: Bool = false, period: Int = 4,
                      participants: [PlayParticipant]) -> Play {
        Play(id: UUID().uuidString, text: text, scoringPlay: scoring, awayScore: nil, homeScore: nil, clock: nil,
             period: .init(number: period), type: .init(id: nil, text: type), summaryType: nil, atBatId: nil,
             participants: participants)
    }

    // MARK: - Play classification (recorded)

    func testBasketballThreeAssistAndStealFromRecordedPlays() throws {
        let plays = try summary("BoxScore-nba").allPlaysWithNamedParticipants
        let three = try XCTUnwrap(plays.first { $0.id == "4019092879" })
        let highlights = PlayHighlight.highlights(in: three, sport: .basketball)
        XCTAssertEqual(Set(highlights.filter { $0.athleteID == "4278039" }.map(\.type)), [.basket, .threePointer])
        XCTAssertEqual(highlights.filter { $0.athleteID == "4869342" }.map(\.type), [.assist])
        XCTAssertFalse(highlights.contains { $0.type == .dunk })

        let turnover = try XCTUnwrap(plays.first { $0.id == "40190928711" })
        XCTAssertEqual(PlayHighlight.highlights(in: turnover, sport: .basketball),
                       [PlayHighlight(athleteID: "4397020", type: .steal, period: turnover.period?.number)])

        let miss = try XCTUnwrap(plays.first { $0.id == "4019092877" })
        XCTAssertTrue(PlayHighlight.highlights(in: miss, sport: .basketball).isEmpty, "A miss is nobody's basket")
    }

    func testHockeyGoalCreditsScorerAndAssisters() throws {
        let plays = try summary("PlayParticipants-nhl").allPlaysWithNamedParticipants
        let goal = try XCTUnwrap(plays.first { $0.type?.text == "Goal" })
        let highlights = PlayHighlight.highlights(in: goal, sport: .hockey)
        XCTAssertEqual(Set(highlights.filter { $0.athleteID == "3114727" }.map(\.type)), [.goal, .point])
        XCTAssertEqual(Set(highlights.filter { $0.athleteID == "3895074" }.map(\.type)), [.assist, .point])
        let faceoff = try XCTUnwrap(plays.first)
        XCTAssertTrue(PlayHighlight.highlights(in: faceoff, sport: .hockey).isEmpty)
    }

    func testBaseballSingleIsAHitNotAHomeRun() throws {
        let plays = try summary("PlayParticipants-mlb").allPlaysWithNamedParticipants
        let single = try XCTUnwrap(plays.first { $0.scoringPlay == true })
        XCTAssertEqual(PlayHighlight.highlights(in: single, sport: .mlb).map(\.type), [.hit])
        XCTAssertEqual(PlayHighlight.highlights(in: single, sport: .mlb).first?.athleteID, "5149101", "The batter")
    }

    func testBaseballHomeRunAndPitcherStrikeout() {
        let hr = play("Judge homered to left (412 feet).", scoring: true, period: 3, participants: [
            PlayParticipant(athleteID: "p1", role: "pitcher"), PlayParticipant(athleteID: "judge", role: "batter"),
        ])
        XCTAssertEqual(Set(PlayHighlight.highlights(in: hr, sport: .mlb).map(\.type)), [.homeRun, .hit])
        XCTAssertTrue(PlayHighlight.highlights(in: hr, sport: .mlb).allSatisfy { $0.athleteID == "judge" && $0.period == 3 })

        let k = play("Soto struck out swinging.", participants: [
            PlayParticipant(athleteID: "skubal", role: "pitcher"), PlayParticipant(athleteID: "soto", role: "batter"),
        ])
        XCTAssertEqual(PlayHighlight.highlights(in: k, sport: .mlb), [PlayHighlight(athleteID: "skubal", type: .strikeout, period: 4)])
    }

    func testBasketballBlockGoesToTheNamedBlocker() {
        let block = play("Rudy Gobert blocks Stephen Curry 's 3-foot layup", type: "Block", participants: [
            PlayParticipant(athleteID: "curry"), PlayParticipant(athleteID: "gobert"),
        ])
        let names = ["curry": "Stephen Curry", "gobert": "Rudy Gobert"]
        XCTAssertEqual(PlayHighlight.highlights(in: block, sport: .basketball, fullNames: names).map(\.athleteID), ["gobert"])
        let dunk = play("Giannis Antetokounmpo makes driving dunk", type: "Driving Dunk Shot", scoring: true,
                        participants: [PlayParticipant(athleteID: "giannis")])
        XCTAssertEqual(Set(PlayHighlight.highlights(in: dunk, sport: .basketball).map(\.type)), [.basket, .dunk])
        let freeThrow = play("Giannis Antetokounmpo makes free throw 1 of 2", type: "Free Throw - 1 of 2", scoring: true,
                             participants: [PlayParticipant(athleteID: "giannis")])
        XCTAssertTrue(PlayHighlight.highlights(in: freeThrow, sport: .basketball).isEmpty)
    }

    func testSoccerGoalAndCardHighlights() {
        let goal = SoccerMatchEvent(id: "g", type: .goal, typeText: "Goal", period: 2, scoringPlay: true,
                                    playerNames: ["Erling Haaland", "Kevin De Bruyne"], athleteIDs: ["haaland", "kdb"])
        XCTAssertEqual(PlayHighlight.highlights(in: goal), [
            PlayHighlight(athleteID: "haaland", type: .goal, period: 2),
            PlayHighlight(athleteID: "kdb", type: .assist, period: 2),
        ])
        let card = SoccerMatchEvent(id: "c", type: .redCard, typeText: "Red Card", playerNames: ["X"], athleteIDs: ["x"])
        XCTAssertEqual(PlayHighlight.highlights(in: card).map(\.type), [.redCard])
        let own = SoccerMatchEvent(id: "o", type: .ownGoal, typeText: "Own Goal", athleteIDs: ["x"])
        XCTAssertTrue(PlayHighlight.highlights(in: own).isEmpty)
        let older = SoccerMatchEvent(id: "n", type: .goal, typeText: "Goal", playerNames: ["X"])
        XCTAssertTrue(PlayHighlight.highlights(in: older).isEmpty, "No IDs from an older server")
    }

    // MARK: - Milestones

    func testMilestoneCrossesOnlyOnTheWayUp() {
        let thirty = AlertMilestone(stat: "points", threshold: 30)
        XCTAssertTrue(thirty.isCrossed(from: 28, to: 31))
        XCTAssertTrue(thirty.isCrossed(from: 29, to: 30))
        XCTAssertFalse(thirty.isCrossed(from: 30, to: 32), "Already past it")
        XCTAssertFalse(thirty.isCrossed(from: nil, to: 32), "First look only records")
        XCTAssertFalse(thirty.isCrossed(from: 20, to: 25))
    }

    func testTripleDoubleIsDerived() {
        let line: [String: Double] = ["points": 24, "rebounds": 11, "assists": 9]
        XCTAssertEqual(AlertMilestone.value(of: AlertMilestone.tripleDouble, in: line), 0)
        XCTAssertEqual(AlertMilestone.value(of: AlertMilestone.doubleDouble, in: line), 1)
        var later = line
        later["assists"] = 10
        XCTAssertEqual(AlertMilestone.value(of: AlertMilestone.tripleDouble, in: later), 1)
        XCTAssertNil(AlertMilestone.value(of: AlertMilestone.tripleDouble, in: [:]))
    }

    func testMilestoneCopyIsMilestoneLanguage() {
        XCTAssertEqual(AlertMilestone(stat: "points", threshold: 30).description(sport: .basketball), "30 points")
        XCTAssertEqual(AlertMilestone(stat: "pitching.strikeouts", threshold: 10).description(sport: .mlb), "10 strikeouts")
        XCTAssertEqual(AlertMilestone(stat: AlertMilestone.tripleDouble, threshold: 1).description(sport: .basketball), "a triple-double")
        XCTAssertEqual(AlertMilestone(stat: "batting.stolenBases", threshold: 2).description(sport: .mlb), "2 stolen bases")
        let banned = ["over", "under", "line", "prop", "total"]
        for sport in SportType.allCases {
            for type in AlertPlayType.types(for: sport) {
                let words = Set((type.phrase(sport: sport) + " " + type.title).lowercased().split(separator: " ").map(String.init))
                XCTAssertTrue(words.isDisjoint(with: banned), "\(type) wording")
            }
        }
    }

    // MARK: - Rules and limits

    private func playerRule(_ id: String, athlete: String, sport: SportType = .basketball,
                            types: [AlertPlayType] = [.threePointer]) -> AlertRule {
        AlertRule(id: id, kind: .playerPlay, sport: sport, athleteID: athlete, athleteName: athlete, teamID: "134880",
                  playTypes: types)
    }

    func testValidation() {
        XCTAssertTrue(playerRule("a", athlete: "3975").isValid)
        XCTAssertFalse(playerRule("a", athlete: "3975", types: [.homeRun]).isValid, "Wrong sport for the play type")
        XCTAssertFalse(playerRule("a", athlete: "3975", sport: .nfl, types: []).isValid, "NFL player alerts are off in v1")
        XCTAssertFalse(AlertRule(id: "a", kind: .playerPlay, sport: .basketball, athleteID: "1", playTypes: [.dunk]).isValid,
                       "A player rule needs the team that finds the game")
        XCTAssertFalse(AlertRule(id: "m", kind: .playerMilestone, sport: .soccer, athleteID: "1", teamID: "2",
                                 milestone: .init(stat: "goals", threshold: 2)).isValid, "No soccer milestones")
        XCTAssertTrue(AlertRule(id: "m", kind: .playerMilestone, sport: .hockey, athleteID: "1", teamID: "2",
                                milestone: .init(stat: "goals", threshold: 3)).isValid)
        XCTAssertTrue(AlertRule(id: "s", kind: .gameSituation, sport: .nfl, situation: .redZone).isValid)
        XCTAssertFalse(AlertRule(id: "s", kind: .gameSituation, sport: .soccer).isValid)
    }

    func testFreeTierKeepsOnePlayerWithOneRule() {
        let rules = [
            AlertRule(id: "sit", kind: .gameSituation, sport: .basketball, situation: .crunchTime),
            playerRule("curry-3s", athlete: "3975"),
            playerRule("curry-dunks", athlete: "3975", types: [.dunk]),
            playerRule("lebron", athlete: "1966"),
        ]
        let free = CustomAlertLimits.free.apply(to: rules)
        XCTAssertEqual(free.accepted.map(\.id), ["curry-3s"])
        XCTAssertEqual(free.droppedIDs, ["sit", "curry-dunks", "lebron"])

        let pro = CustomAlertLimits.pro.apply(to: rules + [playerRule("curry-3s", athlete: "3975")])
        XCTAssertEqual(pro.accepted.map(\.id), ["sit", "curry-3s", "curry-dunks", "lebron"])
        XCTAssertEqual(pro.droppedIDs, ["curry-3s"], "Duplicate IDs are dropped")
    }

    func testFiltersFinalPeriodAndCloseGame() {
        var rule = playerRule("a", athlete: "1")
        rule.finalPeriodOnly = true
        XCTAssertFalse(rule.passesFilters(period: 3, margin: 0, league: .nba))
        XCTAssertTrue(rule.passesFilters(period: 4, margin: 20, league: .nba))
        XCTAssertTrue(rule.passesFilters(period: 5, margin: 0, league: .nba), "Overtime counts")
        rule.closeGameOnly = true
        XCTAssertFalse(rule.passesFilters(period: 4, margin: 12, league: .nba))
        XCTAssertTrue(rule.passesFilters(period: 4, margin: 8, league: .nba))
        XCTAssertEqual(AlertRule.finalPeriod(sport: .mlb, league: .mlb), 9)
        XCTAssertEqual(AlertRule.finalPeriod(sport: .soccer, league: .English_Premier_League), 2)
    }

    // MARK: - Codable

    func testRegistrationDecodesLeniently() throws {
        let json = """
        {"token":"abc","revenueCatAppUserID":"$RCAnonymousID:1","rules":[
          {"id":"r1","kind":"playerPlay","sport":"basketball","athleteID":"3975","teamID":"134865",
           "playTypes":["threePointer","halfCourtHeave"],"finalPeriodOnly":true},
          {"id":"r2","kind":"futureKind","sport":"basketball"},
          {"id":"r3","kind":"gameSituation","sport":"curling"},
          {"id":"r4","kind":"gameSituation","sport":"hockey","situation":"newSituation","closeGameOnly":"yes"}
        ]}
        """
        let registration = try JSONDecoder().decode(CustomAlertRegistration.self, from: Data(json.utf8))
        XCTAssertEqual(registration.rules.map(\.id), ["r1", "r4"])
        XCTAssertEqual(registration.rules[0].playTypes, [.threePointer], "Unknown play types are dropped")
        XCTAssertTrue(registration.rules[0].finalPeriodOnly)
        XCTAssertNil(registration.rules[1].situation, "Unknown situation reads as any")
        XCTAssertFalse(registration.rules[1].closeGameOnly)
        XCTAssertNil(registration.sandbox)
    }

    func testRuleRoundTrips() throws {
        let rule = AlertRule(id: "m", kind: .playerMilestone, sport: .mlb, athleteID: "skubal", athleteName: "Tarik Skubal",
                             teamID: "135268", milestone: .init(stat: "pitching.strikeouts", threshold: 10), closeGameOnly: true)
        let data = try JSONEncoder().encode(rule)
        XCTAssertEqual(try JSONDecoder().decode(AlertRule.self, from: data), rule)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"sport\":\"mlb\""))
    }
}
