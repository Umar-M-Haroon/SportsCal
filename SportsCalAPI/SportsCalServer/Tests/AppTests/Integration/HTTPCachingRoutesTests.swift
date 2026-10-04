@testable import App
import XCTVapor
import Redis
import Crypto
import SportsCalModel

/// Conditional GET (ETag / If-None-Match → 304), the public `/health` probe, the
/// upstream stale-on-error cache and `JobHeartbeat`, against an in-memory store.
/// Same harness as `RoutesTests`: no `configure(app)`, Redis pointed at a closed port
/// so the rate limiter fails open.
final class HTTPCachingRoutesTests: XCTestCase {

    private static let apiKey = "test-key"

    var app: Application!
    var kv: InMemoryKeyValueStore!

    private var authed: HTTPHeaders { ["X-API-Key": Self.apiKey] }

    override func setUp() async throws {
        app = Application(.testing)
        kv = InMemoryKeyValueStore()
        app.kv = kv
        app.redis.configuration = try RedisConfiguration(hostname: "127.0.0.1", port: 1)
        let hash = SHA256.hash(data: Data(Self.apiKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        setenv("API_KEY_HASH", hash, 1)
        // Process-global caches: start every test from nothing.
        await LastKnownGoodCache.shared.reset()
        await DerivedPayloadCache.shared.reset()
        await HealthReportCache.shared.reset()
        SourceVersionMemo.shared.reset()
        try routes(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
        kv = nil
    }

    // MARK: - Fixtures

    private func game(_ id: String, status: String = "pre") -> Game {
        TestGameFactory.make(idEvent: id, strHomeTeam: "Lakers", strAwayTeam: "Celtics", strStatus: status)
    }

    private func seedSchedule(_ ids: [String]) async throws {
        let key = RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: false).rawValue
        try await kv.setJSON(key, value: TestGameFactory.liveScore(nba: ids.map { game($0) }), ttl: nil)
    }

    private func headers(ifNoneMatch tag: String) -> HTTPHeaders {
        var h = authed
        h.add(name: .ifNoneMatch, value: tag)
        return h
    }

    // MARK: - /schedules

    func testSchedulesReturnsStrongETagThen304OnMatch() async throws {
        try await seedSchedule(["E1"])

        var etag = ""
        try app.test(.GET, "v2025/schedules", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            etag = res.headers.first(name: .eTag) ?? ""
            XCTAssertTrue(etag.hasPrefix("\"") && etag.hasSuffix("\""), "strong, quoted ETag: \(etag)")
            XCTAssertFalse(etag.hasPrefix("W/"))
            XCTAssertEqual(res.headers.first(name: .cacheControl), "no-cache")
            XCTAssertFalse(res.body.string.isEmpty)
        }

        try app.test(.GET, "v2025/schedules", headers: headers(ifNoneMatch: etag)) { res in
            XCTAssertEqual(res.status, .notModified)
            XCTAssertEqual(res.body.readableBytes, 0)
            XCTAssertEqual(res.headers.first(name: .eTag), etag)
            XCTAssertEqual(res.headers.first(name: .cacheControl), "no-cache")
        }

        // Weak form and a compressing proxy's suffix still match; lists are honoured.
        let opaque = String(etag.dropFirst().dropLast())
        for variant in ["W/\(etag)", "\"\(opaque)-gzip\"", "\"other\", \(etag)", "*"] {
            try app.test(.GET, "v2025/schedules", headers: headers(ifNoneMatch: variant)) { res in
                XCTAssertEqual(res.status, .notModified, variant)
            }
        }

        try app.test(.GET, "v2025/schedules", headers: headers(ifNoneMatch: "\"stale\"")) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.headers.first(name: .eTag), etag)
        }

        // Legacy unversioned path: same body, same tag.
        try app.test(.GET, "schedules", headers: headers(ifNoneMatch: etag)) { res in
            XCTAssertEqual(res.status, .notModified)
        }
    }

    func testSchedulesETagDiffersPerCollegeVariant() async throws {
        try await seedSchedule(["E1"])

        var plain = "", college = ""
        try app.test(.GET, "v2025/schedules", headers: authed) { res in
            plain = res.headers.first(name: .eTag) ?? ""
        }
        try app.test(.GET, "v2025/schedules?cfb=1", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            college = res.headers.first(name: .eTag) ?? ""
        }
        XCTAssertFalse(plain.isEmpty)
        XCTAssertNotEqual(plain, college)

        // A tag from one variant must not validate the other.
        try app.test(.GET, "v2025/schedules?cfb=1", headers: headers(ifNoneMatch: plain)) { res in
            XCTAssertEqual(res.status, .ok)
        }
        try app.test(.GET, "v2025/schedules?cfb=1", headers: headers(ifNoneMatch: college)) { res in
            XCTAssertEqual(res.status, .notModified)
        }
    }

    func testSchedulesETagChangesWhenScheduleChanges() async throws {
        try await seedSchedule(["E1"])
        var first = ""
        try app.test(.GET, "v2025/schedules", headers: authed) { res in
            first = res.headers.first(name: .eTag) ?? ""
        }

        // Simulate the 30s snapshot expiring and a new schedule landing.
        await LastKnownGoodCache.shared.reset()
        try await seedSchedule(["E1", "E2"])

        try app.test(.GET, "v2025/schedules", headers: headers(ifNoneMatch: first)) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertNotEqual(res.headers.first(name: .eTag), first)
        }
    }

    func testSchedulesVersionIsReusedForIdenticalBytes() async {
        let v1 = await LastKnownGoodCache.shared.storeSchedules("{\"a\":1}")
        let v2 = await LastKnownGoodCache.shared.storeSchedules(String("{\"a\":1}".reversed().reversed()))
        let v3 = await LastKnownGoodCache.shared.storeSchedules("{\"a\":2}")
        XCTAssertEqual(v1, v2)
        XCTAssertNotEqual(v1, v3)
        XCTAssertEqual(v1, PayloadVersion.of("{\"a\":1}"))
    }

    // MARK: - /sport, /live, /teams

    func testSportETagThen304() async throws {
        try await seedSchedule(["E1"])
        var etag = ""
        try app.test(.GET, "v2025/sport/basketball", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            etag = res.headers.first(name: .eTag) ?? ""
            let event = try JSONDecoder().decode(LiveEvent.self, from: Data(buffer: res.body))
            XCTAssertEqual(event.events.first?.idEvent, "E1")
        }
        XCTAssertFalse(etag.isEmpty)
        try app.test(.GET, "v2025/sport/basketball", headers: headers(ifNoneMatch: etag)) { res in
            XCTAssertEqual(res.status, .notModified)
            XCTAssertEqual(res.body.readableBytes, 0)
        }
        // Different sport over the same schedule → different tag.
        try app.test(.GET, "v2025/sport/basketball?cfb=1", headers: authed) { res in
            XCTAssertNotEqual(res.headers.first(name: .eTag), nil)
        }
        try app.test(.GET, "v2025/sport/nfl", headers: headers(ifNoneMatch: etag)) { res in
            XCTAssertNotEqual(res.status, .notModified)
        }
    }

    func testLiveETagThen304() async throws {
        let key = RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: false).rawValue
        try await kv.setJSON(key, value: TestGameFactory.liveScore(nba: [game("L1", status: "in")]), ttl: nil)

        var etag = ""
        try app.test(.GET, "v2025/live", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            etag = res.headers.first(name: .eTag) ?? ""
            XCTAssertEqual(res.headers.first(name: .cacheControl), "no-cache")
        }
        XCTAssertFalse(etag.isEmpty)
        try app.test(.GET, "v2025/live", headers: headers(ifNoneMatch: etag)) { res in
            XCTAssertEqual(res.status, .notModified)
        }
        try app.test(.GET, "v2025/live?cfb=1", headers: headers(ifNoneMatch: etag)) { res in
            XCTAssertEqual(res.status, .ok)
        }

        // New live data → new tag.
        try await kv.setJSON(key, value: TestGameFactory.liveScore(nba: [game("L1", status: "in"), game("L2", status: "in")]), ttl: nil)
        try app.test(.GET, "v2025/live", headers: headers(ifNoneMatch: etag)) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertNotEqual(res.headers.first(name: .eTag), etag)
        }
    }

    func testTeamsETagThen304() async throws {
        let key = RedisEndpoint.teams.getValue(isDebug: false).rawValue
        try await kv.setJSON(key, value: [Team(idTeam: "100", strTeam: "Lakers")], ttl: nil)
        var etag = ""
        try app.test(.GET, "v2025/teams", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            etag = res.headers.first(name: .eTag) ?? ""
        }
        try app.test(.GET, "v2025/teams", headers: headers(ifNoneMatch: etag)) { res in
            XCTAssertEqual(res.status, .notModified)
        }
    }

    // MARK: - Removed / reshaped routes

    func testRemovedLegacyRoutesAre404() throws {
        for path in ["v2025/test-call", "v2025/teams-by-league", "test-call", "teams-by-league"] {
            try app.test(.GET, path, headers: authed) { res in
                XCTAssertEqual(res.status, .notFound, path)
            }
        }
    }

    func testStandingsHistoryIsEmptyArrayWithoutSnapshots() throws {
        try app.test(.GET, "v2025/standings/4387/history?days=90", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "[]")
        }
    }

    // MARK: - UpstreamCache

    struct UpstreamDown: Error {}

    func testUpstreamCacheServesFreshWithoutFetching() async throws {
        let now = Date()
        try await kv.setString("k", value: UpstreamCache.encode("cached", storedAt: now.addingTimeInterval(-60)), ttl: nil)
        let value = try await UpstreamCache.value(kv: kv, key: "k", freshFor: 600, keepFor: 3600, logger: app.logger, now: now) {
            XCTFail("fresh entry must not hit upstream")
            return "fetched"
        }
        XCTAssertEqual(value, "cached")
    }

    func testUpstreamCacheRefetchesWhenStaleAndServesStaleOnFailure() async throws {
        let now = Date()
        try await kv.setString("k", value: UpstreamCache.encode("old", storedAt: now.addingTimeInterval(-700)), ttl: nil)

        let stale = try await UpstreamCache.value(kv: kv, key: "k", freshFor: 600, keepFor: 3600, logger: app.logger, now: now) {
            throw UpstreamDown()
        }
        XCTAssertEqual(stale, "old")

        let fresh = try await UpstreamCache.value(kv: kv, key: "k", freshFor: 600, keepFor: 3600, logger: app.logger, now: now) {
            "new"
        }
        XCTAssertEqual(fresh, "new")
        let stored = try await kv.getString("k") ?? ""
        XCTAssertEqual(UpstreamCache.decode(stored)?.body, "new")
    }

    func testUpstreamCacheThrowsWhenNothingCachedAndUpstreamFails() async throws {
        do {
            _ = try await UpstreamCache.value(kv: kv, key: "missing", freshFor: 600, keepFor: 3600, logger: app.logger) {
                throw UpstreamDown()
            }
            XCTFail("expected a throw")
        } catch is UpstreamDown {}
    }

    // MARK: - JobHeartbeat

    func testJobHeartbeatRoundTripsWithDebugPrefix() async throws {
        await JobHeartbeat.recordSuccess(.espnFetch, app: app, isDebug: true)
        let debug = await JobHeartbeat.lastSuccess(.espnFetch, app: app, isDebug: true)
        let prod = await JobHeartbeat.lastSuccess(.espnFetch, app: app, isDebug: false)
        XCTAssertNotNil(debug)
        XCTAssertNil(prod)
        XCTAssertEqual(debug!.timeIntervalSinceNow, 0, accuracy: 5)
        XCTAssertNotNil(kv.rawSnapshot["debug-job:last-success:espnFetch"])
        XCTAssertEqual(kv.ttl("debug-job:last-success:espnFetch") ?? 0, TimeInterval(JobHeartbeat.ttlSeconds), accuracy: 5)
    }

    // MARK: - /health

    private func seedHealthyState() async throws {
        try await kv.setString(RedisEndpoint.ESPN.latestLiveInfo.getValue(isDebug: false).rawValue, value: "{}", ttl: nil)
        try await seedSchedule(["E1"])
        try await kv.setJSON(RedisEndpoint.ESPN.scheduleLastUpdate.getValue(isDebug: false).rawValue, value: Date(), ttl: nil)
        for job in JobHeartbeat.Job.allCases {
            await JobHeartbeat.recordSuccess(job, app: app, isDebug: false)
        }
    }

    func testHealthIsPublicAndOKWhenEverythingIsFresh() async throws {
        try await seedHealthyState()
        try app.test(.GET, "health") { res in
            XCTAssertEqual(res.status, .ok)
            let json = try JSONSerialization.jsonObject(with: Data(buffer: res.body)) as? [String: Any]
            XCTAssertEqual(json?["status"] as? String, "ok")
            XCTAssertEqual((json?["failing"] as? [Any])?.count, 0)
            XCTAssertEqual(json?["redis"] as? Bool, true)
        }
    }

    func testHealthIs503AndNamesStaleChecks() async throws {
        try await seedHealthyState()
        // A wedged job: last success well past its budget.
        let old = Date().addingTimeInterval(-JobHeartbeat.Job.espnFetch.maxAge - 60).timeIntervalSince1970
        try await kv.setString(JobHeartbeat.key(.espnFetch, isDebug: false), value: String(old), ttl: nil)
        try await kv.delete([RedisEndpoint.ESPN.scheduleLastUpdate.getValue(isDebug: false).rawValue])

        try app.test(.GET, "health") { res in
            XCTAssertEqual(res.status, .serviceUnavailable)
            let json = try JSONSerialization.jsonObject(with: Data(buffer: res.body)) as? [String: Any]
            XCTAssertEqual(json?["status"] as? String, "degraded")
            let failing = json?["failing"] as? [String] ?? []
            XCTAssertTrue(failing.contains("job:espnFetch"), "\(failing)")
            XCTAssertTrue(failing.contains("data:scheduleLastUpdate"), "\(failing)")
            XCTAssertFalse(failing.contains("job:liveTicker"))
            // APNS isn't configured in tests, so it isn't judged.
            XCTAssertFalse(failing.contains("job:apns"))
        }
    }
}
