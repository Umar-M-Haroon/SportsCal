//
//  CustomAlertRulesTests.swift
//  SportsCalTests
//
//  The pure side of custom live alerts: building rules from the alert builder,
//  stable IDs across edits, game-situation rules, and the free/Pro cap.
//

import XCTest
import SportsCalModel
@testable import Scoreline

@MainActor
final class CustomAlertRulesTests: XCTestCase {

    private let curry = PlayerRef(athleteID: "3975", name: "Stephen Curry", sport: .basketball, teamID: "134865")
    private let judge = PlayerRef(athleteID: "33192", name: "Aaron Judge", sport: .mlb, teamID: "135260")

    private func ids(_ prefix: String = "id") -> () -> String {
        var n = 0
        return { n += 1; return "\(prefix)\(n)" }
    }

    // MARK: Draft → rules

    func testDraftBuildsOnePlayRuleAndOneRulePerMilestone() {
        var draft = PlayerAlertDraft(player: curry, rules: [])
        draft.playTypes = [.dunk, .threePointer]
        draft.addMilestone(AlertMilestone(stat: "points", threshold: 30))
        draft.addMilestone(AlertMilestone(stat: "points", threshold: 30)) // duplicate ignored
        draft.addMilestone(AlertMilestone(stat: AlertMilestone.tripleDouble, threshold: 1))
        draft.finalPeriodOnly = true

        let rules = draft.rules(existing: [], makeID: ids())
        XCTAssertEqual(rules.count, 3)
        XCTAssertEqual(rules[0].kind, .playerPlay)
        // Display order, whatever order they were picked in.
        XCTAssertEqual(rules[0].playTypes, [.threePointer, .dunk])
        XCTAssertEqual(rules.filter { $0.kind == .playerMilestone }.count, 2)
        XCTAssertTrue(rules.allSatisfy { $0.isValid && $0.finalPeriodOnly && !$0.closeGameOnly })
        XCTAssertTrue(rules.allSatisfy { $0.teamID == "134865" && $0.athleteName == "Stephen Curry" })
    }

    func testEditingKeepsRuleIDs() {
        var draft = PlayerAlertDraft(player: curry, rules: [])
        draft.playTypes = [.threePointer]
        draft.addMilestone(AlertMilestone(stat: "points", threshold: 30))
        let first = draft.rules(existing: [], makeID: ids("a"))

        var edit = PlayerAlertDraft(player: curry, rules: first)
        XCTAssertEqual(edit.playTypes, [.threePointer])
        XCTAssertEqual(edit.milestones, [AlertMilestone(stat: "points", threshold: 30)])
        edit.playTypes.insert(.dunk)
        edit.addMilestone(AlertMilestone(stat: "rebounds", threshold: 10))
        let second = edit.rules(existing: first, makeID: ids("b"))

        XCTAssertEqual(second.first { $0.kind == .playerPlay }?.id, first.first { $0.kind == .playerPlay }?.id)
        XCTAssertEqual(second.first { $0.milestone?.stat == "points" }?.id, first.first { $0.milestone?.stat == "points" }?.id)
        XCTAssertEqual(second.first { $0.milestone?.stat == "rebounds" }?.id, "b1")
    }

    func testEmptyDraftMakesNoRules() {
        XCTAssertTrue(PlayerAlertDraft(player: curry, rules: []).rules(existing: []).isEmpty)
    }

    func testSoccerOffersPlaysButNoMilestones() {
        let saka = PlayerRef(athleteID: "1", name: "Bukayo Saka", sport: .soccer, teamID: "133604")
        var draft = PlayerAlertDraft(player: saka, rules: [])
        XCTAssertTrue(draft.offersPlays)
        XCTAssertFalse(draft.offersMilestones)
        draft.playTypes = [.goal]
        draft.milestones = [AlertMilestone(stat: "goals", threshold: 2)]
        let rules = draft.rules(existing: [], makeID: ids())
        XCTAssertEqual(rules.map(\.kind), [.playerPlay])
    }

    func testSummaryUsesMilestoneWording() {
        var draft = PlayerAlertDraft(player: judge, rules: [])
        draft.playTypes = [.homeRun]
        draft.addMilestone(AlertMilestone(stat: "batting.hits", threshold: 3))
        let summary = CustomAlertCatalog.summary(of: draft.rules(existing: [], makeID: ids()), sport: .mlb)
        XCTAssertEqual(summary, "hits a home run or reaches 3 hits")
        for banned in ["over", "under", "line", "prop", "total"] {
            XCTAssertFalse(summary.lowercased().split(separator: " ").contains(Substring(banned)))
        }
    }

    // MARK: Cap

    func testFreeTierAllowsOnePlayerWithOneRule() {
        var draft = PlayerAlertDraft(player: curry, rules: [])
        draft.playTypes = [.threePointer, .dunk] // still one rule
        let one = draft.rules(existing: [], makeID: ids("c"))
        XCTAssertFalse(CustomAlertPolicy.exceedsCap(new: one, athleteID: curry.athleteID, playerRules: [], limits: .free))

        draft.addMilestone(AlertMilestone(stat: "points", threshold: 30))
        let two = draft.rules(existing: [], makeID: ids("d"))
        XCTAssertTrue(CustomAlertPolicy.exceedsCap(new: two, athleteID: curry.athleteID, playerRules: [], limits: .free))
        XCTAssertFalse(CustomAlertPolicy.exceedsCap(new: two, athleteID: curry.athleteID, playerRules: [], limits: .pro))
    }

    func testFreeTierBlocksASecondPlayerButAllowsEditingTheFirst() {
        var curryDraft = PlayerAlertDraft(player: curry, rules: [])
        curryDraft.playTypes = [.threePointer]
        let existing = curryDraft.rules(existing: [], makeID: ids("e"))

        var judgeDraft = PlayerAlertDraft(player: judge, rules: [])
        judgeDraft.playTypes = [.homeRun]
        let judgeRules = judgeDraft.rules(existing: existing, makeID: ids("f"))
        XCTAssertTrue(CustomAlertPolicy.exceedsCap(new: judgeRules, athleteID: judge.athleteID, playerRules: existing, limits: .free))

        var edit = PlayerAlertDraft(player: curry, rules: existing)
        edit.playTypes = [.dunk]
        let edited = edit.rules(existing: existing, makeID: ids("g"))
        XCTAssertFalse(CustomAlertPolicy.exceedsCap(new: edited, athleteID: curry.athleteID, playerRules: existing, limits: .free))
    }

    func testReplacingKeepsThePlayersPlace() {
        let a = AlertRule(id: "a", kind: .playerPlay, sport: .mlb, athleteID: "1", teamID: "t", playTypes: [.hit])
        let b = AlertRule(id: "b", kind: .playerPlay, sport: .mlb, athleteID: "2", teamID: "t", playTypes: [.hit])
        let c = AlertRule(id: "c", kind: .playerPlay, sport: .mlb, athleteID: "3", teamID: "t", playTypes: [.hit])
        let b2 = AlertRule(id: "b2", kind: .playerPlay, sport: .mlb, athleteID: "2", teamID: "t", playTypes: [.homeRun])
        XCTAssertEqual(CustomAlertPolicy.replacing(athleteID: "2", with: [b2], in: [a, b, c]).map(\.id), ["a", "b2", "c"])
        XCTAssertEqual(CustomAlertPolicy.replacing(athleteID: "2", with: [], in: [a, b, c]).map(\.id), ["a", "c"])
        XCTAssertEqual(CustomAlertPolicy.replacing(athleteID: "9", with: [b2], in: [a]).map(\.id), ["a", "b2"])
    }

    func testLocalProWinsOverAStaleServerAnswer() {
        XCTAssertEqual(CustomAlertPolicy.limits(localIsPro: true, server: .free), .pro)
        XCTAssertEqual(CustomAlertPolicy.limits(localIsPro: false, server: nil), .free)
        XCTAssertEqual(CustomAlertPolicy.limits(localIsPro: false, server: .pro), .pro)
    }

    // MARK: Situations

    func testSituationRulesForFavoriteTeamsOrTheWholeLeague() {
        var prefs = SituationAlertPrefs()
        prefs.set(.crunchTime, sport: .basketball, on: true)
        prefs.set(.goaliePulled, sport: .hockey, on: true)
        prefs.setCoversAllGames(.hockey, true)

        let rules = SituationAlertRules.rules(prefs: prefs, favoriteTeamIDs: [.basketball: ["134865", "134862"]])
        XCTAssertEqual(Set(rules.map(\.id)), [
            "sit-basketball-crunchTime-134865",
            "sit-basketball-crunchTime-134862",
            "sit-hockey-goaliePulled-all",
        ])
        XCTAssertTrue(rules.allSatisfy { $0.isValid && $0.kind == .gameSituation })
        XCTAssertNil(rules.first { $0.sport == .hockey }?.teamID)
        // Free can't have situations at all.
        XCTAssertEqual(CustomAlertLimits.free.apply(to: rules).accepted.count, 0)
    }

    func testSituationRuleIDRoundTrips() {
        let id = SituationAlertRules.ruleID(sport: .mlb, kind: .tyingRunAtPlate, teamID: "135260")
        let parsed = SituationAlertRules.parse(id)
        XCTAssertEqual(parsed?.sport, .mlb)
        XCTAssertEqual(parsed?.kind, .tyingRunAtPlate)
        XCTAssertNil(SituationAlertRules.parse("8F2C-UUID-LIKE-ID"))
    }

    func testFavoriteTeamsComeFromMainLeagueGames() {
        let nba = Game(idLeague: "\(Leagues.nba.rawValue)", idHomeTeam: "134865", idAwayTeam: "134862",
                       strHomeTeam: "Warriors", strAwayTeam: "Knicks", isoDate: nil)
        let nhl = Game(idLeague: "\(Leagues.nhl.rawValue)", idHomeTeam: "134852", idAwayTeam: "999",
                       strHomeTeam: "Kings", strAwayTeam: "Other", isoDate: nil)
        let teams = SituationAlertRules.favoriteTeamIDs(games: [nba, nhl], favorites: ["134865", "134852"])
        XCTAssertEqual(teams[.basketball], ["134865"])
        XCTAssertEqual(teams[.hockey], ["134852"])
    }

    func testEverySituationSportHasSituations() {
        for sport in CustomAlertCatalog.situationSports {
            XCTAssertFalse(CustomAlertCatalog.situations(for: sport).isEmpty, "\(sport)")
        }
        XCTAssertEqual(Set(CustomAlertCatalog.situationSports), AlertRule.situationSports)
    }

    func testPlayerRefRoundTrips() throws {
        let data = try JSONEncoder().encode([curry])
        XCTAssertEqual(try JSONDecoder().decode([PlayerRef].self, from: data), [curry])
    }
}
