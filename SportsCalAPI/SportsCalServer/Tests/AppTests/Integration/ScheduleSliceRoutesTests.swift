@testable import App
import XCTVapor
import Redis
import Crypto
import SportsCalModel

/// `/schedules` and `/schedules/sports/:key` ETags follow the calendar version: a live
/// tick rewrites the blob but leaves every ETag alone; a final changes only its sport's.
final class ScheduleSliceRoutesTests: XCTestCase {
    private static let apiKey = "test-key"
    var app: Application!
    var kv: InMemoryKeyValueStore!
    private var authed: HTTPHeaders { ["X-API-Key": Self.apiKey] }

    override func setUp() async throws {
        app = Application(.testing)
        kv = InMemoryKeyValueStore()
        app.kv = kv
        app.redis.configuration = try RedisConfiguration(hostname: "127.0.0.1", port: 1)
        let hash = SHA256.hash(data: Data(Self.apiKey.utf8)).map { String(format: "%02x", $0) }.joined()
        setenv("API_KEY_HASH", hash, 1)
        await LastKnownGoodCache.shared.reset()
        await DerivedPayloadCache.shared.reset()
        SourceVersionMemo.shared.reset()
        try routes(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
        kv = nil
    }

    private func nba(_ status: String, progress: String? = nil, home: String? = nil) -> Game {
        TestGameFactory.make(idEvent: "N1", strHomeTeam: "Lakers", strAwayTeam: "Celtics",
                             intHomeScore: home, strStatus: status, strProgress: progress)
    }

    private let nhl = TestGameFactory.make(idEvent: "H1", strHomeTeam: "Kings", strAwayTeam: "Ducks", strStatus: "pre")

    /// Stores the schedule the way `ScheduleStore.write` does: blob plus calendar versions.
    private func store(nbaGame: Game) async throws {
        var schedule = TestGameFactory.liveScore(nba: [nbaGame])
        schedule.nhl = LiveEvent(events: [nhl])
        try await kv.setJSON(ScheduleStore.scheduleKey(isDebug: false).rawValue, value: schedule, ttl: nil)
        try await kv.setJSON(ScheduleStore.calendarKey(isDebug: false).rawValue,
                             value: ScheduleCalendarVersion.versions(of: schedule), ttl: nil)
        // The 30s in-process snapshot would otherwise hide the rewrite.
        await LastKnownGoodCache.shared.reset()
    }

    private func etag(_ path: String) throws -> String {
        var tag = ""
        try app.test(.GET, path, headers: authed) { res in
            XCTAssertEqual(res.status, .ok, path)
            tag = res.headers.first(name: .eTag) ?? ""
        }
        return tag
    }

    func testSliceBodyAnd304() async throws {
        try await store(nbaGame: nba("pre"))
        var tag = ""
        try app.test(.GET, "v2025/schedules/sports/nba", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            tag = res.headers.first(name: .eTag) ?? ""
            let slice = try JSONDecoder().decode(LiveScore.self, from: Data(res.body.string.utf8))
            XCTAssertEqual(slice.nba?.events.map(\.idEvent), ["N1"])
            XCTAssertNil(slice.nhl, "a slice carries only its sport")
        }
        var headers = authed
        headers.add(name: .ifNoneMatch, value: tag)
        try app.test(.GET, "v2025/schedules/sports/nba", headers: headers) { res in
            XCTAssertEqual(res.status, .notModified)
            XCTAssertEqual(res.body.readableBytes, 0)
        }
        try app.test(.GET, "v2025/schedules/sports/cricket", headers: authed) { res in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    func testLiveTickKeepsETagsAndFinalMovesOnlyItsSport() async throws {
        try await store(nbaGame: nba("in", progress: "Q2 5:00", home: "40"))
        let all1 = try etag("v2025/schedules"), nba1 = try etag("v2025/schedules/sports/nba"), nhl1 = try etag("v2025/schedules/sports/nhl")

        try await store(nbaGame: nba("in", progress: "Q3 1:00", home: "61"))
        XCTAssertEqual(try etag("v2025/schedules"), all1, "a live tick is on the socket")
        XCTAssertEqual(try etag("v2025/schedules/sports/nba"), nba1)

        try await store(nbaGame: nba("post", progress: "Final", home: "110"))
        XCTAssertNotEqual(try etag("v2025/schedules"), all1)
        XCTAssertNotEqual(try etag("v2025/schedules/sports/nba"), nba1, "the final result must reach cached copies")
        XCTAssertEqual(try etag("v2025/schedules/sports/nhl"), nhl1, "another sport's final doesn't touch hockey")
    }
}
