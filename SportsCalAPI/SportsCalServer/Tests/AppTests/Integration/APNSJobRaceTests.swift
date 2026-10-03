@testable import App
import XCTest
import Logging
import SportsCalModel

/// F1 Live Activities: races have no integer scores, so the job used to drop every one.
final class APNSJobRaceTests: XCTestCase {
    private var kv: InMemoryKeyValueStore!
    private var apns: MockAPNSClient!
    private var clock: MutableClock!
    private let logger = Logger(label: "test.apns-race")

    override func setUp() async throws {
        clock = MutableClock()
        kv = InMemoryKeyValueStore(clock: clock)
        apns = MockAPNSClient()
    }

    private func race(leaders: [(String, Int, String?)], status: String = "in") -> Game {
        let entries = leaders.map { LeaderboardEntry(name: $0.0, score: "", position: $0.1, constructor: "McLaren", gap: $0.2) }
        return Game(
            idEvent: "f1", idLeague: "4370", strHomeTeam: "Singapore Grand Prix", strAwayTeam: leaders.first?.0 ?? "",
            intAwayScore: "P1", strStatus: status, strProgress: "Lap 23/62",
            lastPlay: String(repeating: "Driver|P1|+0.000|Team\n", count: 20),
            isoDate: nil,
            sessions: [EventSession(sessionType: "Race", sessionName: "Race", status: status, leaderboard: entries)]
        )
    }

    private func seed(_ game: Game) async throws {
        try await kv.setJSON("Latest Full Live Info", value: TestGameFactory.liveScore(racing: [game]), ttl: nil)
        try await kv.setJSON("F1 Standings", value: F1Standings(teamColors: ["McLaren": "F47600"], driverCodes: ["oscar piastri": "PIA"]), ttl: nil)
    }

    private func runJob() async throws {
        try await APNSJob.runOnce(kv: kv, apns: apns, clock: clock, isDebug: false, logger: logger)
    }

    func test_raceUpdateCarriesTopThreeAndNoLeaderboardLastPlay() async throws {
        try await kv.setJSON("APNS-tok1", value: APNSRegistration(eventID: "f1"), ttl: nil)
        try await seed(race(leaders: [("Oscar Piastri", 1, "1:02:11.004"), ("Lando Norris", 2, "+1.204"), ("George Russell", 3, "+3.900")]))

        try await runJob()

        let update = try XCTUnwrap(apns.recorded.first { $0.kind == .update })
        let state = try XCTUnwrap(update.contentState)
        XCTAssertNil(state.lastPlay, "the full F1 leaderboard must not ride in the APNS payload")
        XCTAssertEqual(state.progress, "Lap 23/62")
        XCTAssertEqual(state.race?.leaders.map(\.code), ["PIA", "NOR", "RUS"])
        XCTAssertEqual(state.race?.leaders.first?.teamColor, "F47600")
    }

    func test_orderChangePushesAgain_unchangedOrderDoesNot() async throws {
        try await kv.setJSON("APNS-tok1", value: APNSRegistration(eventID: "f1"), ttl: nil)
        try await seed(race(leaders: [("Oscar Piastri", 1, nil), ("Lando Norris", 2, "+1.2")]))
        try await runJob()
        try await runJob()
        XCTAssertEqual(apns.recorded.filter { $0.kind == .update }.count, 1)

        try await seed(race(leaders: [("Lando Norris", 1, nil), ("Oscar Piastri", 2, "+0.4")]))
        try await runJob()
        XCTAssertEqual(apns.recorded.filter { $0.kind == .update }.count, 2)
    }
}
