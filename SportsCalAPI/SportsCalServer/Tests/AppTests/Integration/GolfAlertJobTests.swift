import XCTest
import Logging
@testable import App
import SportsCalModel

final class GolfAlertJobTests: XCTestCase {
    private let logger = Logger(label: "test.golf-alerts")
    private var kv: RedisCapableKV!
    private var apns: MockAPNSClient!

    override func setUp() {
        kv = RedisCapableKV()
        apns = MockAPNSClient()
    }

    /// The live feed's copy: the top of the board only (a full `golfFieldLimit` of rows).
    private func liveBoard() -> Game {
        let rows = (1...LiveEvent.golfFieldLimit).map {
            LeaderboardEntry(name: "Player \($0)", score: "-\(20 - $0 / 2)", position: $0, rounds: ["66"])
        }
        return Game(idEvent: "401", idLeague: "\(Leagues.pga.rawValue)", strHomeTeam: "The RSM Classic", strAwayTeam: "",
                    strStatus: "in", strProgress: "Round 2 - In Progress", isoDate: nil, leaderboardEntries: rows)
    }

    /// The whole field, with the followed player 45th.
    private func field(thru: String?) -> Game {
        var game = liveBoard()
        game.leaderboardEntries?.append(LeaderboardEntry(name: "Rickie Fowler", score: "-2", position: 45,
                                                         thruHole: thru, rounds: ["70"], today: thru == nil ? nil : "E"))
        return game
    }

    private func register(_ install: String, token: String, players: [String],
                          kinds: [GolfAlertKind] = GolfAlertKind.allCases) async throws {
        let device = GolfAlertDevice(installID: install, token: token, players: players, kinds: kinds)
        let key = GolfAlertDevice.key(installID: install, sandbox: false)
        try await kv.setJSON(key, value: device, ttl: nil)
        await GolfAlertDeviceIndex.add(key, sandbox: false, kv: kv)
    }

    private func run(field whole: Game) async throws {
        try await kv.setJSON(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: false).rawValue,
                             value: TestGameFactory.liveScore(golf: [liveBoard()]), ttl: nil)
        try await GolfAlertJob.runOnce(kv: kv, apns: apns, isDebug: false, logger: logger) { _ in whole }
    }

    func testFollowedPlayerBelowTheLiveBoardGetsTeeOffOnce() async throws {
        try await register("fowler-fan", token: "tokA", players: ["Rickie Fowler"])
        try await register("lead-only", token: "tokB", players: ["Rickie Fowler"], kinds: [.lead])
        try await register("other", token: "tokC", players: ["Tiger Woods"])

        try await run(field: field(thru: nil))          // first look: baseline only
        XCTAssertTrue(apns.recorded.isEmpty)

        try await run(field: field(thru: "1"))
        XCTAssertEqual(apns.recorded.map(\.deviceToken), ["tokA"])
        XCTAssertEqual(apns.recorded.first?.alertTitle, "⛳️ Rickie Fowler tees off")

        apns.reset()
        try await run(field: field(thru: "2"))
        XCTAssertTrue(apns.recorded.isEmpty)
    }

    func testNoDevicesMeansNoFieldFetches() async throws {
        var fetched = false
        try await kv.setJSON(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: false).rawValue,
                             value: TestGameFactory.liveScore(golf: [liveBoard()]), ttl: nil)
        try await GolfAlertJob.runOnce(kv: kv, apns: apns, isDebug: false, logger: logger) { _ in
            fetched = true
            return nil
        }
        XCTAssertFalse(fetched)
    }
}
