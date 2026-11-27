//
//  CustomAlertJobTests.swift
//  AppTests
//
//  Pro custom alerts end to end against in-memory Redis and a recording APNS client:
//  registration (free cap, RevenueCat verification and its failure modes), play
//  matching on a feed built from a recorded-shape ESPN summary, milestones crossing
//  once, situations without a Live Activity, dedupe, mutes and the per-game cap.
//

import XCTest
import Logging
@testable import App
import SportsCalModel

/// Stands in for RevenueCat.
private struct StubEntitlements: ProEntitlementChecking {
    var proUsers: Set<String> = []
    func check(appUserID: String?) async -> ProEntitlementCheck {
        guard let appUserID else { return .unverified }
        return ProEntitlementCheck(isPro: proUsers.contains(appUserID), verified: true)
    }
}

final class CustomAlertJobTests: XCTestCase {
    private let logger = Logger(label: "test.custom-alerts")
    private var kv: RedisCapableKV!
    private var apns: MockAPNSClient!

    private let eventID = "401810001"
    private let warriors = "134865"
    private let lakers = "134867"
    private let curry = "3975"
    private let green = "6589"

    override func setUp() {
        kv = RedisCapableKV()
        apns = MockAPNSClient()
    }

    // MARK: - Fixtures

    private func game(home: Int = 80, away: Int = 78, period: Int = 4, clock: Double = 300,
                      league: Leagues = .nba, winProbability: Double? = nil) -> Game {
        var game = TestGameFactory.make(
            idEvent: eventID, idLeague: "\(league.rawValue)", idHomeTeam: lakers, idAwayTeam: warriors,
            strHomeTeam: "Lakers", strAwayTeam: "Warriors",
            intHomeScore: "\(home)", intAwayScore: "\(away)", strStatus: "in", strProgress: "Q\(period) 5:00"
        )
        game.situation = GameSituation(period: period, clock: clock, homeWinProbability: winProbability)
        return game
    }

    /// An ESPN-shaped NBA summary: plays `1...count` (play 2 and every later even play a
    /// Curry three assisted by Green) and the box score with Curry at `points`.
    private func summary(plays count: Int, points: Int, threes: Int = 1) throws -> ESPNSummaryResponse {
        var plays: [String] = []
        for id in 1...count {
            if id.isMultiple(of: 2) {
                plays.append("""
                {"id": "\(id)", "text": "Stephen Curry makes 27-foot three point jumper (Draymond Green assists)",
                 "scoringPlay": true, "type": {"id": "92", "text": "Jump Shot"}, "period": {"number": 4},
                 "participants": [{"athlete": {"id": "\(curry)"}}, {"athlete": {"id": "\(green)"}}]}
                """)
            } else {
                plays.append("""
                {"id": "\(id)", "text": "Draymond Green defensive rebound", "type": {"text": "Defensive Rebound"},
                 "period": {"number": 4}, "participants": [{"athlete": {"id": "\(green)"}}]}
                """)
            }
        }
        let json = """
        {"plays": [\(plays.joined(separator: ","))],
         "boxscore": {"players": [{"team": {"id": "9"}, "statistics": [{
           "keys": ["points", "threePointFieldGoalsMade-threePointFieldGoalsAttempted", "rebounds", "assists"],
           "athletes": [
             {"athlete": {"id": "\(curry)", "displayName": "Stephen Curry", "shortName": "S. Curry"}, "stats": ["\(points)", "\(threes)-9", "4", "5"]},
             {"athlete": {"id": "\(green)", "displayName": "Draymond Green", "shortName": "D. Green"}, "stats": ["6", "0-1", "9", "8"]}
           ]}]}]}}
        """
        return try JSONDecoder().decode(ESPNSummaryResponse.self, from: Data(json.utf8))
    }

    private func writeFeed(plays: Int, points: Int) async throws {
        let feed = try XCTUnwrap(LivePlayerFeed(
            summary: try summary(plays: plays, points: points), sportType: .basketball, espnEventID: eventID,
            tsdbEventID: nil, sport: "basketball", league: "nba", isFinal: false, fetchedAt: Date()
        ))
        try await kv.setJSON(RedisEndpoint.ESPN.livePlayers(eventID).getValue(isDebug: false).rawValue, value: feed, ttl: nil)
    }

    private func threesRule(_ id: String = "curry-3s", finalPeriodOnly: Bool = false) -> AlertRule {
        AlertRule(id: id, kind: .playerPlay, sport: .basketball, athleteID: curry, athleteName: "Stephen Curry",
                  teamID: warriors, playTypes: [.threePointer], finalPeriodOnly: finalPeriodOnly)
    }

    private func pointsRule(_ threshold: Double = 30) -> AlertRule {
        AlertRule(id: "curry-30", kind: .playerMilestone, sport: .basketball, athleteID: curry, athleteName: "Stephen Curry",
                  teamID: warriors, milestone: AlertMilestone(stat: "points", threshold: threshold))
    }

    @discardableResult
    private func register(_ install: String, token: String, rules: [AlertRule], appUser: String? = nil,
                          pro: Set<String> = [], sandbox: Bool = false) async throws -> CustomAlertRegistrationResponse {
        try await CustomAlertRegistry.register(
            CustomAlertRegistration(token: token, revenueCatAppUserID: appUser, rules: rules),
            installID: install, sandbox: sandbox, kv: kv, entitlements: StubEntitlements(proUsers: pro), now: Date()
        )
    }

    private func run(_ game: Game, now: Date = Date(), entitlements: ProEntitlementChecking = StubEntitlements(),
                     soccer: SoccerMatchDetail? = nil) async throws {
        let live = game.sportType == .soccer ? TestGameFactory.liveScore(soccer: [game]) : TestGameFactory.liveScore(nba: [game])
        try await kv.setJSON(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: false).rawValue, value: live, ttl: nil)
        try await CustomAlertJob.runOnce(kv: kv, apns: apns, entitlements: entitlements, now: now, isDebug: false,
                                         logger: logger) { _ in soccer }
    }

    // MARK: - Registration

    func testFreeInstallKeepsOnePlayerRule() async throws {
        let response = try await register("free", token: "tokF", rules: [
            AlertRule(id: "sit", kind: .gameSituation, sport: .basketball),
            threesRule(), pointsRule(),
        ], appUser: "user-free")
        XCTAssertFalse(response.isPro)
        XCTAssertEqual(response.rules.map(\.id), ["curry-3s"])
        XCTAssertEqual(response.droppedRuleIDs, ["sit", "curry-30"])
        XCTAssertEqual(response.limits, .free)
        let stored = try await kv.getJSON(CustomAlertDevice.key(installID: "free", sandbox: false), as: CustomAlertDevice.self)
        XCTAssertEqual(stored?.rules.map(\.id), ["curry-3s"])
        XCTAssertEqual(kv.inner.ttl(CustomAlertDevice.key(installID: "free", sandbox: false)) ?? 0, CustomAlertDevice.ttl, accuracy: 5)
        let scopes = await CustomAlertIndex.scopesInUse(sandbox: false, kv: kv)
        XCTAssertEqual(scopes, ["team:basketball:\(warriors)"])
    }

    func testProInstallKeepsEverythingAndReindexesOnReplace() async throws {
        let response = try await register("pro", token: "tokP", rules: [
            AlertRule(id: "sit", kind: .gameSituation, sport: .basketball), threesRule(), pointsRule(),
        ], appUser: "user-pro", pro: ["user-pro"])
        XCTAssertTrue(response.isPro)
        XCTAssertEqual(response.rules.count, 3)
        let key = CustomAlertDevice.key(installID: "pro", sandbox: false)
        var sport = await CustomAlertIndex.devices(in: "sport:basketball", sandbox: false, kv: kv)
        XCTAssertEqual(sport, [key])

        // Replacing the rules moves the device out of scopes it no longer uses.
        try await register("pro", token: "tokP", rules: [threesRule()], appUser: "user-pro", pro: ["user-pro"])
        sport = await CustomAlertIndex.devices(in: "sport:basketball", sandbox: false, kv: kv)
        XCTAssertTrue(sport.isEmpty)
        let team = await CustomAlertIndex.devices(in: "team:basketball:\(warriors)", sandbox: false, kv: kv)
        XCTAssertEqual(team, [key])

        await CustomAlertRegistry.unregister(installID: "pro", sandbox: false, kv: kv)
        let gone = await CustomAlertIndex.devices(in: "team:basketball:\(warriors)", sandbox: false, kv: kv)
        XCTAssertTrue(gone.isEmpty)
        let device = try await kv.getJSON(key, as: CustomAlertDevice.self)
        XCTAssertNil(device)
    }

    func testRevenueCatFailureMeansFree() async throws {
        let failing = RevenueCatEntitlementChecker(secretKey: "sk_test", kv: kv, logger: logger) { _, _ in
            throw URLError(.timedOut)
        }
        let rules = [threesRule(), pointsRule()]
        let response = try await CustomAlertRegistry.register(
            CustomAlertRegistration(token: "t", revenueCatAppUserID: "user-pro", rules: rules),
            installID: "i", sandbox: false, kv: kv, entitlements: failing, now: Date()
        )
        XCTAssertFalse(response.isPro)
        XCTAssertEqual(response.rules.count, 1)
        // Not cached, so the next registration asks again.
        let cached = try await kv.getString(RevenueCatEntitlementChecker.cacheKey(appUserID: "user-pro"))
        XCTAssertNil(cached)

        let serverError = RevenueCatEntitlementChecker(secretKey: "sk_test", kv: kv, logger: logger) { _, _ in (500, Data()) }
        let serverErrorCheck = await serverError.check(appUserID: "user-pro")
        XCTAssertEqual(serverErrorCheck, .unverified)
        let noKey = RevenueCatEntitlementChecker(secretKey: nil, kv: kv, logger: logger) { _, _ in
            XCTFail("No key, no request")
            return (200, Data())
        }
        let noKeyCheck = await noKey.check(appUserID: "user-pro")
        XCTAssertEqual(noKeyCheck, .unverified)
        let noUserCheck = await serverError.check(appUserID: nil)
        XCTAssertEqual(noUserCheck, .unverified)
    }

    func testRevenueCatActiveEntitlementIsCached() async throws {
        let body = Data("""
        {"subscriber": {"entitlements": {
          "Pro": {"expires_date": "2099-01-01T00:00:00Z", "product_identifier": "pro_annual"}
        }}}
        """.utf8)
        let calls = Counter()
        let checker = RevenueCatEntitlementChecker(secretKey: "sk_test", kv: kv, logger: logger) { url, key in
            XCTAssertEqual(url, "https://api.revenuecat.com/v1/subscribers/%24RCAnonymousID%3Aabc")
            XCTAssertEqual(key, "sk_test")
            calls.increment()
            return (200, body)
        }
        let first = await checker.check(appUserID: "$RCAnonymousID:abc")
        let second = await checker.check(appUserID: "$RCAnonymousID:abc")
        XCTAssertEqual(first, ProEntitlementCheck(isPro: true, verified: true))
        XCTAssertEqual(second, first)
        XCTAssertEqual(calls.value, 1, "Cached for 6h")
        XCTAssertEqual(kv.inner.ttl(RevenueCatEntitlementChecker.cacheKey(appUserID: "$RCAnonymousID:abc")) ?? 0,
                       RevenueCatEntitlementChecker.cacheTTL, accuracy: 5)
    }

    func testRevenueCatEntitlementShapes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15
        func active(_ json: String) -> Bool? {
            RevenueCatEntitlementChecker.hasActiveEntitlement(body: Data(json.utf8), now: now)
        }
        XCTAssertEqual(active(#"{"subscriber":{"entitlements":{"Pro":{"expires_date":null}}}}"#), true, "Lifetime")
        XCTAssertEqual(active(#"{"subscriber":{"entitlements":{"Pro":{"expires_date":"2026-01-01T00:00:00Z"}}}}"#), false)
        XCTAssertEqual(active(#"{"subscriber":{"entitlements":{"Pro":{"expires_date":"2026-01-01T00:00:00Z","grace_period_expires_date":"2027-02-01T00:00:00.000Z"}}}}"#), true)
        XCTAssertEqual(active(#"{"subscriber":{"entitlements":{"pro":{"expires_date":null}}}}"#), false, "Identifier is case-sensitive: Pro")
        XCTAssertEqual(active(#"{"subscriber":{"entitlements":{}}}"#), false)
        XCTAssertNil(active("<html>"))
    }

    // MARK: - Player plays

    func testNewThreesAlertOnceAndFirstLookIsQuiet() async throws {
        try await register("fan", token: "tokA", rules: [threesRule()], appUser: "u")
        try await register("other", token: "tokB", rules: [
            AlertRule(id: "lebron", kind: .playerPlay, sport: .basketball, athleteID: "1966", teamID: lakers, playTypes: [.dunk]),
        ], appUser: "u2")

        try await writeFeed(plays: 2, points: 3)
        try await run(game())
        XCTAssertTrue(apns.recorded.isEmpty, "First look only records")

        try await writeFeed(plays: 4, points: 6)                    // play 4: a new Curry three
        try await run(game())
        XCTAssertEqual(apns.recorded.count, 1)
        let send = try XCTUnwrap(apns.recorded.first)
        XCTAssertEqual(send.deviceToken, "tokA")
        XCTAssertEqual(send.alertTitle, "Stephen Curry hits a 3-pointer")
        XCTAssertEqual(send.alertBody, "Warriors 78, Lakers 80 · Q4 5:00")
        XCTAssertEqual(send.alertType, CustomAlertNotification.playType)
        XCTAssertEqual(send.alertOptions?.category, CustomAlertNotification.category)
        XCTAssertEqual(send.alertOptions?.ruleID, "curry-3s")
        XCTAssertEqual(send.alertOptions?.athleteID, curry)
        XCTAssertEqual(send.alertOptions?.collapseID?.count, 32)

        apns.reset()
        try await run(game())                                       // nothing new
        XCTAssertTrue(apns.recorded.isEmpty)

        // The state is lost (TTL, flush): the same plays are first-look again, and the
        // per-device claim would catch a replay anyway.
        _ = try await kv.delete([CustomAlertGameState.key(eventID: eventID, isDebug: false)])
        try await run(game())
        try await writeFeed(plays: 4, points: 6)
        try await run(game())
        XCTAssertTrue(apns.recorded.isEmpty)
    }

    func testSentClaimDedupesAReplayedPlay() async throws {
        try await register("fan", token: "tokA", rules: [threesRule()])
        try await writeFeed(plays: 2, points: 3)
        try await run(game())
        try await writeFeed(plays: 4, points: 6)
        try await run(game())
        XCTAssertEqual(apns.recorded.count, 1)

        // Rewind the state as a second job instance might have: the claim holds.
        let saved = try await kv.getJSON(CustomAlertGameState.key(eventID: eventID, isDebug: false), as: CustomAlertGameState.self)
        var state = try XCTUnwrap(saved)
        state.lastPlayID = "2"
        try await kv.setJSON(CustomAlertGameState.key(eventID: eventID, isDebug: false), value: state, ttl: nil)
        apns.reset()
        try await run(game())
        XCTAssertTrue(apns.recorded.isEmpty)
        let claimed = try await kv.exists(CustomAlertJob.sentKey(installID: "fan", ruleID: "curry-3s", eventID: eventID, key: "4", sandbox: false))
        XCTAssertTrue(claimed)
    }

    func testFinalPeriodFilterAndSandboxDevice() async throws {
        try await register("fan", token: "tokS", rules: [threesRule(finalPeriodOnly: true)], sandbox: true)
        try await writeFeed(plays: 2, points: 3)
        try await run(game())
        try await writeFeed(plays: 4, points: 6)
        try await run(game())
        XCTAssertEqual(apns.recorded.map(\.environment), [.sandbox], "Q4 play passes; sandbox token goes to sandbox")
        let claim = try await kv.getString("debug-CustomAlertSent-fan-curry-3s-\(eventID)-4")
        XCTAssertNotNil(claim)
    }

    func testPerGameCap() async throws {
        try await register("fan", token: "tokA", rules: [threesRule()])
        try await writeFeed(plays: 2, points: 3)
        try await run(game())
        try await writeFeed(plays: 2 + 2 * 20, points: 60)          // 20 new threes in one minute
        try await run(game())
        XCTAssertEqual(apns.recorded.count, CustomAlertNotification.maxPerDevicePerGame)
    }

    func testMutedPlayerIsQuietForThatGame() async throws {
        try await register("fan", token: "tokA", rules: [threesRule()])
        try await CustomAlertRegistry.mute(
            CustomAlertMuteRequest(token: "tokA", eventID: eventID, athleteID: curry), installID: "fan", sandbox: false, kv: kv
        )
        try await writeFeed(plays: 2, points: 3)
        try await run(game())
        try await writeFeed(plays: 4, points: 6)
        try await run(game())
        XCTAssertTrue(apns.recorded.isEmpty)
    }

    func testOneRuleOtherTeamsGameIsUntouched() async throws {
        try await register("fan", token: "tokA", rules: [threesRule()])
        let other = TestGameFactory.make(idEvent: "999", idLeague: "4387", idHomeTeam: "1", idAwayTeam: "2",
                                     strHomeTeam: "A", strAwayTeam: "B", strStatus: "in")
        try await run(other)
        let state = try await kv.getJSON(CustomAlertGameState.key(eventID: "999", isDebug: false), as: CustomAlertGameState.self)
        XCTAssertNil(state, "A game nobody follows isn't looked at")
    }

    // MARK: - Milestones

    func testMilestoneFiresOnceOnTheWayUp() async throws {
        try await register("pro", token: "tokP", rules: [pointsRule()], appUser: "p", pro: ["p"])
        try await writeFeed(plays: 2, points: 26)
        try await run(game())
        try await writeFeed(plays: 3, points: 29)
        try await run(game())
        XCTAssertTrue(apns.recorded.isEmpty)

        try await writeFeed(plays: 5, points: 32)
        try await run(game())
        XCTAssertEqual(apns.recorded.map(\.alertTitle), ["Stephen Curry reaches 30 points"])
        XCTAssertEqual(apns.recorded.first?.alertType, CustomAlertNotification.milestoneType)

        apns.reset()
        try await writeFeed(plays: 7, points: 35)
        try await run(game())
        XCTAssertTrue(apns.recorded.isEmpty, "Once per rule per game")
    }

    // MARK: - Fantasy points

    /// An NFL summary with one running back at `yards` rushing yards and `touchdowns` TDs.
    private func nflFeed(yards: Int, touchdowns: Int) throws -> LivePlayerFeed {
        let json = """
        {"boxscore": {"players": [{"team": {"id": "8", "abbreviation": "DET"}, "statistics": [{
           "name": "rushing", "keys": ["rushingAttempts", "rushingYards", "rushingTouchdowns"],
           "athletes": [{"athlete": {"id": "4429795", "displayName": "Jahmyr Gibbs"}, "stats": ["12", "\(yards)", "\(touchdowns)"]}]
         }]}]}}
        """
        let summary = try JSONDecoder().decode(ESPNSummaryResponse.self, from: Data(json.utf8))
        return try XCTUnwrap(LivePlayerFeed(summary: summary, sportType: .nfl, espnEventID: eventID, tsdbEventID: nil,
                                            sport: "football", league: "nfl", isFinal: false, fetchedAt: Date()))
    }

    func testFantasyPointsMilestoneForAnNFLPlayer() async throws {
        let rule = AlertRule(id: "gibbs-20", kind: .playerMilestone, sport: .nfl, athleteID: "4429795",
                             athleteName: "Jahmyr Gibbs", teamID: lakers,
                             milestone: AlertMilestone(stat: AlertMilestone.fantasyPoints, threshold: 20),
                             fantasyScoringID: FantasyScoring.nflHalfPPR.id)
        let response = try await register("pro", token: "tokP", rules: [rule], appUser: "p", pro: ["p"])
        XCTAssertEqual(response.rules.map(\.id), ["gibbs-20"])

        let nfl = game(league: .nfl)
        func runNFL() async throws {
            let live = TestGameFactory.liveScore(nfl: [nfl])
            try await kv.setJSON(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: false).rawValue, value: live, ttl: nil)
            try await CustomAlertJob.runOnce(kv: kv, apns: apns, entitlements: StubEntitlements(), now: Date(), isDebug: false,
                                             logger: logger) { _ in nil }
        }
        let key = RedisEndpoint.ESPN.livePlayers(eventID).getValue(isDebug: false).rawValue
        try await kv.setJSON(key, value: try nflFeed(yards: 60, touchdowns: 1), ttl: nil)   // 12 pts
        try await runNFL()
        try await kv.setJSON(key, value: try nflFeed(yards: 85, touchdowns: 2), ttl: nil)   // 20.5 pts
        try await runNFL()
        XCTAssertEqual(apns.recorded.map(\.alertTitle), ["Jahmyr Gibbs reaches 20 fantasy points"])
    }

    func testMilestoneAlreadyPassedAtFirstLookStaysQuiet() async throws {
        try await register("pro", token: "tokP", rules: [pointsRule()], appUser: "p", pro: ["p"])
        try await writeFeed(plays: 2, points: 34)
        try await run(game())
        try await writeFeed(plays: 3, points: 36)
        try await run(game())
        XCTAssertTrue(apns.recorded.isEmpty)
    }

    func testLapsedProIsCappedAtSendTime() async throws {
        try await register("pro", token: "tokP", rules: [pointsRule(), threesRule()], appUser: "p", pro: ["p"])
        try await writeFeed(plays: 2, points: 28)
        let later = Date().addingTimeInterval(CustomAlertDevice.proRecheckInterval + 60)
        try await run(game(), now: later)
        try await writeFeed(plays: 4, points: 31)
        try await run(game(), now: later)                           // Pro gone: only the first rule
        XCTAssertEqual(apns.recorded.map(\.alertOptions?.ruleID), ["curry-30"])
    }

    // MARK: - Situations

    func testSituationFiresWithoutALiveActivity() async throws {
        try await register("pro", token: "tokP", rules: [
            AlertRule(id: "crunch", kind: .gameSituation, sport: .basketball, situation: .crunchTime),
        ], appUser: "p", pro: ["p"])
        try await run(game(home: 100, away: 99, clock: 200))
        try await run(game(home: 100, away: 99, clock: 100))
        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.alertType, CustomAlertNotification.situationType)
        XCTAssertNil(apns.recorded.first?.alertOptions?.athleteID)
        apns.reset()
        try await run(game(home: 102, away: 101, clock: 60))
        XCTAssertTrue(apns.recorded.isEmpty, "One crunch-time alert per period")

        // A WNBA game isn't the league-wide rule's.
        let wnba = TestGameFactory.make(idEvent: "777", idLeague: "\(Leagues.wnba.rawValue)", strHomeTeam: "A", strAwayTeam: "B", strStatus: "in")
        XCTAssertFalse(CustomAlertJob.rule(AlertRule(id: "x", kind: .gameSituation, sport: .basketball), matches: wnba))
    }

    // MARK: - Soccer

    func testSoccerGoalByFollowedPlayer() async throws {
        let haaland = "253989"
        try await register("city", token: "tokC", rules: [
            AlertRule(id: "haaland", kind: .playerPlay, sport: .soccer, athleteID: haaland, athleteName: "Erling Haaland",
                      teamID: "133613", playTypes: [.goal]),
        ])
        let soccerGame = TestGameFactory.make(
            idEvent: "740001", idLeague: "4328", idHomeTeam: "133613", idAwayTeam: "133604",
            strHomeTeam: "Manchester City", strAwayTeam: "Arsenal", intHomeScore: "1", intAwayScore: "0", strStatus: "in"
        )
        func detail(_ events: [SoccerMatchEvent]) -> SoccerMatchDetail {
            SoccerMatchDetail(eventID: "740001", home: SoccerLineup(teamName: "Manchester City", players: []),
                              away: SoccerLineup(teamName: "Arsenal", players: []), events: events)
        }
        let goal = SoccerMatchEvent(id: "g1", type: .goal, typeText: "Goal", clock: "23'", period: 1, side: .home,
                                    scoringPlay: true, playerNames: ["Erling Haaland"], athleteIDs: [haaland])
        try await run(soccerGame, soccer: detail([]))
        try await run(soccerGame, soccer: detail([goal]))
        XCTAssertEqual(apns.recorded.map(\.alertTitle), ["Erling Haaland scores a goal"])
    }

    // MARK: - Payload

    func testAlertPayloadKeys() throws {
        let payload = AlertPayload(eventID: "1", type: CustomAlertNotification.playType, ruleID: "r", athleteID: "a")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: String])
        XCTAssertEqual(json, [CustomAlertNotification.eventIDKey: "1", CustomAlertNotification.typeKey: "custom_play",
                              CustomAlertNotification.ruleIDKey: "r", CustomAlertNotification.athleteIDKey: "a"])
        let plain = try JSONEncoder().encode(AlertPayload(eventID: "1", type: "soccer_goal"))
        let plainKeys = try XCTUnwrap(try JSONSerialization.jsonObject(with: plain) as? [String: String])
        XCTAssertEqual(plainKeys, ["eventID": "1", "type": "soccer_goal"], "Soccer/golf payloads unchanged")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
