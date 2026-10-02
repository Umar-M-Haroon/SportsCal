@testable import App
import XCTest
import Logging
import SportsCalModel

/// Live Activity pushes for the game situation: the strip's state riding along in
/// `ContentState`, clutch-moment alerts, and several devices following one game.
final class APNSJobLiveSituationTests: XCTestCase {

    private var kv: InMemoryKeyValueStore!
    private var apns: MockAPNSClient!
    private var clock: MutableClock!
    private let logger = Logger(label: "test.apns-situation")
    private let liveScoreKey = "Latest Full Live Info"

    override func setUp() async throws {
        clock = MutableClock()
        kv = InMemoryKeyValueStore(clock: clock)
        apns = MockAPNSClient()
    }

    private func register(token: String, eventID: String) async throws {
        try await kv.setJSON("APNS-\(token)", value: APNSRegistration(eventID: eventID), ttl: nil)
    }

    private func seed(_ score: LiveScore) async throws {
        try await kv.setJSON(liveScoreKey, value: score, ttl: nil)
    }

    private func runJob() async throws {
        try await APNSJob.runOnce(kv: kv, apns: apns, clock: clock, isDebug: false, logger: logger)
    }

    // MARK: - Several devices on one game

    func test_everyDeviceFollowingAGameGetsTheUpdate() async throws {
        // More devices than the job's send concurrency (8), so they can't all read the
        // last-pushed state before one of them writes it.
        let tokens = (0..<12).map { String(format: "tok%02d", $0) }
        for token in tokens { try await register(token: token, eventID: "e1") }
        try await seed(TestGameFactory.liveScore(nba: [
            TestGameFactory.make(idEvent: "e1", strHomeTeam: "A", strAwayTeam: "B",
                                 intHomeScore: "10", intAwayScore: "3", strStatus: "in", strProgress: "2Q")
        ]))

        try await runJob()

        let updated = Set(apns.recorded.filter { $0.kind == .update }.map(\.deviceToken))
        XCTAssertEqual(updated, Set(tokens), "every Live Activity on the game must update, not just whichever ran first")
    }

    // MARK: - Situation in the payload

    private func mlbGame(home: Int, away: Int, situation: GameSituation?) -> Game {
        var game = TestGameFactory.make(idEvent: "m1", idLeague: "4424", strHomeTeam: "Guardians", strAwayTeam: "Tigers",
                                        intHomeScore: "\(home)", intAwayScore: "\(away)", strStatus: "in", strProgress: "Bot 9th")
        game.situation = situation
        return game
    }

    /// Bottom 9th, home down 2 with a man on: the tying run is at the plate.
    private let tyingRunUp = GameSituation(period: 9, inningHalf: .bottom, balls: 1, strikes: 2, outs: 1, onFirst: true, homeWinProbability: 0.18)

    func test_updateCarriesTheLiveActivitySituation() async throws {
        try await register(token: "tok", eventID: "m1")
        try await seed(TestGameFactory.liveScore(mlb: [mlbGame(home: 3, away: 5, situation: tyingRunUp)]))

        try await runJob()

        let sent = try XCTUnwrap(apns.recorded.first?.contentState?.situation)
        XCTAssertEqual(sent.outs, 1)
        XCTAssertEqual(sent.bases, 1)
        XCTAssertTrue(sent.onFirst)
        XCTAssertEqual(sent.homeWinPct, 18)
    }

    func test_countAloneDoesNotPush() async throws {
        // The Live Activity shows outs and runners, not the count: a pitch that only
        // moves the count must not cost a push.
        try await register(token: "tok", eventID: "m1")
        try await seed(TestGameFactory.liveScore(mlb: [mlbGame(home: 3, away: 5, situation: tyingRunUp)]))
        try await runJob()
        XCTAssertEqual(apns.recorded.count, 1)

        var nextPitch = tyingRunUp
        nextPitch.balls = 2
        try await seed(TestGameFactory.liveScore(mlb: [mlbGame(home: 3, away: 5, situation: nextPitch)]))
        try await runJob()
        XCTAssertEqual(apns.recorded.count, 1)
    }

    // MARK: - Clutch alerts

    func test_clutchMomentAlertsOnce() async throws {
        try await register(token: "tok", eventID: "m1")
        try await seed(TestGameFactory.liveScore(mlb: [mlbGame(home: 3, away: 5, situation: tyingRunUp)]))
        try await runJob()

        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertEqual(apns.recorded.first?.alertTitle, "Guardians: tying run at the plate")
        XCTAssertEqual(apns.recorded.first?.alertBody, "Bottom 9th, 1 out · Tigers 5, Guardians 3")

        // Same moment, next out: the activity updates, silently.
        var twoOut = tyingRunUp
        twoOut.outs = 2
        try await seed(TestGameFactory.liveScore(mlb: [mlbGame(home: 3, away: 5, situation: twoOut)]))
        try await runJob()

        XCTAssertEqual(apns.recorded.count, 2)
        XCTAssertNil(apns.recorded.last?.alertTitle)
    }

    func test_scoreAlertWinsOverClutch() async throws {
        // Hockey goal in the final two minutes: the goal is the news.
        try await register(token: "tok", eventID: "h1")
        func hockey(_ home: Int, _ away: Int) -> Game {
            var game = TestGameFactory.make(idEvent: "h1", idLeague: "4380", strHomeTeam: "Kings", strAwayTeam: "Ducks",
                                            intHomeScore: "\(home)", intAwayScore: "\(away)", strStatus: "in", strProgress: "P3 1:40")
            game.situation = GameSituation(period: 3, clock: 100)
            return game
        }
        try await seed(TestGameFactory.liveScore(nhl: [hockey(1, 1)]))
        try await runJob()
        try await seed(TestGameFactory.liveScore(nhl: [hockey(2, 1)]))
        try await runJob()

        XCTAssertEqual(apns.recorded.last?.alertTitle, "🏒 Goal!")
    }

    func test_clutchAlertsAreCappedPerGame() async throws {
        let moment = ClutchMoment(kind: .basesLoaded, title: "t", body: "b", key: "k")
        var granted = 0
        for i in 0..<10 {
            let distinct = ClutchMoment(kind: moment.kind, title: "t", body: "b", key: "k\(i)")
            if await APNSJob.claimClutchAlert(distinct, eventID: "e", token: "tok", kv: kv, isDebug: false) { granted += 1 }
        }
        XCTAssertEqual(granted, APNSJob.maxClutchAlertsPerGame)
        // Another device on the same game has its own allowance.
        let otherDevice = await APNSJob.claimClutchAlert(moment, eventID: "e", token: "other", kv: kv, isDebug: false)
        XCTAssertTrue(otherDevice)
    }

    func test_noSituationNoClutch() async throws {
        try await register(token: "tok", eventID: "m1")
        try await seed(TestGameFactory.liveScore(mlb: [mlbGame(home: 3, away: 5, situation: nil)]))
        try await runJob()
        XCTAssertEqual(apns.recorded.count, 1)
        XCTAssertNil(apns.recorded.first?.alertTitle)
        XCTAssertNil(apns.recorded.first?.contentState?.situation)
    }
}
