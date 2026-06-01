@testable import App
import XCTest
import Logging
import SportsCalModel

/// Regression guard for the B5 scan-path refactor: chunked MGET + bounded
/// concurrency must process every registration without dropping any. Each
/// device follows a distinct event so each is expected to produce one send.
final class APNSBatchingTests: XCTestCase {
    func test_allRegistrationsProcessed_acrossManyDevices() async throws {
        let clock = MutableClock()
        let kv = InMemoryKeyValueStore(clock: clock)
        let apns = MockAPNSClient()
        let logger = Logger(label: "test.apns-batching")

        let count = 450  // > the 500 MGET chunk size boundary region + many concurrency rounds
        var games: [Game] = []
        for i in 0..<count {
            let eventID = "e\(i)"
            let registration = APNSRegistration(eventID: eventID)
            try await kv.setJSON("APNS-token\(i)", value: registration, ttl: nil)
            games.append(TestGameFactory.make(
                idEvent: eventID,
                strHomeTeam: "H\(i)",
                strAwayTeam: "A\(i)",
                intHomeScore: "1",
                intAwayScore: "0",
                strStatus: "in",
                strProgress: "1Q"
            ))
        }
        try await kv.setJSON("Latest Full Live Info", value: TestGameFactory.liveScore(nba: games), ttl: nil)

        try await APNSJob.runOnce(kv: kv, apns: apns, clock: clock, isDebug: false, logger: logger)

        XCTAssertEqual(
            apns.recorded.count, count,
            "Every registration should produce exactly one send — batching/concurrency must not drop any"
        )
    }
}
