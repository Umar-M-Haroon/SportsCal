import XCTest
import Logging
@testable import App
import SportsCalModel

final class SoccerAlertJobTests: XCTestCase {
    private let logger = Logger(label: "test.soccer-alerts")
    private var kv: RedisCapableKV!
    private var apns: MockAPNSClient!

    override func setUp() {
        kv = RedisCapableKV()
        apns = MockAPNSClient()
    }

    private let game = TestGameFactory.make(
        idEvent: "401879276", idLeague: "4328",
        strHomeTeam: "AFC Bournemouth", strAwayTeam: "Liverpool",
        strStatus: "in", isoDate: Date()
    )

    private func detail(home: Int = 0, away: Int = 0, events: [SoccerMatchEvent] = [], status: String = "STATUS_FIRST_HALF",
                        state: String = "in") -> SoccerMatchDetail {
        let xi = { (team: String) in (1...11).map { SoccerLineupPlayer(name: "\(team) \($0)", starter: true, formationPlace: $0) } }
        return SoccerMatchDetail(
            eventID: "401879276",
            home: SoccerLineup(teamName: "AFC Bournemouth", players: xi("BOU")),
            away: SoccerLineup(teamName: "Liverpool", players: xi("LIV")),
            events: events,
            status: SoccerMatchStatus(state: state, name: status, homeScore: home, awayScore: away)
        )
    }

    private let goal = SoccerMatchEvent(id: "g1", type: .goal, typeText: "Goal", clock: "57'", side: .away,
                                        scoringPlay: true, playerNames: ["Alexander Isak"])

    private func register(_ install: String, token: String, teams: [String],
                          kinds: [SoccerAlertKind] = SoccerAlertKind.allCases, sandbox: Bool = false) async throws {
        let device = SoccerAlertDevice(installID: install, token: token, teams: teams, kinds: kinds)
        let key = SoccerAlertDevice.key(installID: install, sandbox: sandbox)
        try await kv.setJSON(key, value: device, ttl: nil)
        await SoccerAlertDeviceIndex.add(key, sandbox: sandbox, kv: kv)
    }

    func testExpiredRegistrationLeavesTheIndex() async throws {
        try await register("liv-fan", token: "tokA", teams: ["Liverpool"])
        _ = try await kv.delete([SoccerAlertDevice.key(installID: "liv-fan", sandbox: false)])   // TTL ran out
        let devices = await SoccerAlertJob.loadDevices(kv: kv)
        XCTAssertTrue(devices.isEmpty)
        let members = await SoccerAlertDeviceIndex.members(sandbox: false, kv: kv)
        XCTAssertTrue(members.isEmpty)
    }

    private func run(_ match: SoccerMatchDetail) async throws {
        let live = TestGameFactory.liveScore(soccer: [game])
        try await kv.setJSON(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: false).rawValue, value: live, ttl: nil)
        try await SoccerAlertJob.runOnce(kv: kv, apns: apns, now: Date(), isDebug: false, logger: logger) { _ in match }
    }

    func testAlertsFollowersOfEitherSideOnceEach() async throws {
        try await register("liv-fan", token: "tokA", teams: ["Liverpool"])
        try await register("bou-fan", token: "tokB", teams: ["AFC Bournemouth"], sandbox: true)
        try await register("goals-off", token: "tokC", teams: ["Liverpool"], kinds: [.fullTime])
        try await register("other", token: "tokD", teams: ["Arsenal"])

        try await run(detail())                                  // first look: baseline only
        XCTAssertTrue(apns.recorded.isEmpty)

        try await run(detail(away: 1, events: [goal]))
        let sends = apns.recorded
        XCTAssertEqual(Set(sends.map(\.deviceToken)), ["tokA", "tokB"])
        XCTAssertTrue(sends.allSatisfy { $0.kind == .alert && $0.alertTitle == "⚽️ Goal! AFC Bournemouth 0–1 Liverpool" })
        XCTAssertEqual(sends.first { $0.deviceToken == "tokB" }?.environment, .sandbox)

        apns.reset()
        try await run(detail(away: 1, events: [goal]))           // same goal again: quiet
        XCTAssertTrue(apns.recorded.isEmpty)

        try await run(detail(away: 1, events: [goal], status: "STATUS_FULL_TIME", state: "post"))
        XCTAssertEqual(Set(apns.recorded.map(\.deviceToken)), ["tokA", "tokB", "tokC"])
        XCTAssertTrue(apns.recorded.allSatisfy { $0.alertTitle == "Full-time" })
    }

    func testRunningLiveActivityTakesTheGoalButNotFullTime() async throws {
        try await register("liv-fan", token: "tokA", teams: ["Liverpool"])
        try await kv.setString(LiveActivityInstallMarker.key(installID: "liv-fan", eventID: "401879276", sandbox: false),
                               value: "1", ttl: nil)
        try await run(detail())
        try await run(detail(away: 1, events: [goal]))
        XCTAssertTrue(apns.recorded.isEmpty, "the Live Activity announces the goal itself")
        try await run(detail(away: 1, events: [goal], status: "STATUS_FULL_TIME", state: "post"))
        XCTAssertEqual(apns.recorded.map(\.alertTitle), ["Full-time"])
    }

    func testStaleTokenUnregistersTheDevice() async throws {
        try await register("liv-fan", token: "tokA", teams: ["Liverpool"])
        try await run(detail())
        apns.queueError(APNSSendError(reason: .unregistered, underlying: nil), for: "tokA")
        try await run(detail(away: 1, events: [goal]))
        let stillRegistered = try await kv.exists(SoccerAlertDevice.key(installID: "liv-fan", sandbox: false))
        XCTAssertFalse(stillRegistered)
    }

    func testNoDevicesMeansNoMatchFetches() async throws {
        var fetched = false
        try await kv.setJSON(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: false).rawValue,
                             value: TestGameFactory.liveScore(soccer: [game]), ttl: nil)
        try await SoccerAlertJob.runOnce(kv: kv, apns: apns, now: Date(), isDebug: false, logger: logger) { _ in
            fetched = true
            return nil
        }
        XCTAssertFalse(fetched)
    }

    func testWatchWindow() {
        let now = Date()
        let soon = TestGameFactory.make(idEvent: "1", strHomeTeam: "A", strAwayTeam: "B", strStatus: "pre",
                                        isoDate: now.addingTimeInterval(60 * 60))
        let later = TestGameFactory.make(idEvent: "2", strHomeTeam: "A", strAwayTeam: "B", strStatus: "pre",
                                         isoDate: now.addingTimeInterval(3 * 60 * 60))
        let longGone = TestGameFactory.make(idEvent: "3", strHomeTeam: "A", strAwayTeam: "B", strStatus: "post",
                                            isoDate: now.addingTimeInterval(-6 * 60 * 60))
        XCTAssertTrue(SoccerAlertJob.isWatchable(soon, now: now), "lineups land about an hour out")
        XCTAssertFalse(SoccerAlertJob.isWatchable(later, now: now))
        XCTAssertFalse(SoccerAlertJob.isWatchable(longGone, now: now))
    }
}
