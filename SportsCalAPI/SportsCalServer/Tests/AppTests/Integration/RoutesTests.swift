@testable import App
import XCTVapor
import Redis
import Crypto
import SportsCalModel

/// Routes-layer tests against an in-memory KeyValueStore — no Redis, no
/// `configure(app)` (which would boot Redis config, the PBP archive, and APNS).
/// RateLimitMiddleware fails open on Redis errors by design, so pointing the
/// Redis config at a closed port keeps the middleware chain intact without a
/// server. The WebSocket `/ws` route is deliberately untested here: it's an
/// infinite poll loop against live Redis; its client-side reconnect behavior
/// is covered in the iOS test suite.
final class RoutesTests: XCTestCase {

    private static let apiKey = "test-key"

    var app: Application!
    var kv: InMemoryKeyValueStore!

    /// Prod key names: `.testing` env means `isDebug == false` in the routes.
    private var scheduleKey: String {
        RedisEndpoint.ESPN.latestSchedule.getValue(isDebug: false).rawValue
    }

    override func setUp() async throws {
        app = Application(.testing)
        kv = InMemoryKeyValueStore()
        app.kv = kv
        // Closed port: every rate-limit INCR errors instantly → fail-open.
        app.redis.configuration = try RedisConfiguration(hostname: "127.0.0.1", port: 1)
        let hash = SHA256.hash(data: Data(Self.apiKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        setenv("API_KEY_HASH", hash, 1)
        try routes(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
        kv = nil
    }

    private var authed: HTTPHeaders {
        ["X-API-Key": Self.apiKey]
    }

    /// The API returns JSON in a plaintext body (`encodeResult` → String), so
    /// XCTVapor's content-type-driven decoder can't be used.
    private static func decodeBody<T: Decodable>(_ type: T.Type, from res: XCTHTTPResponse) throws -> T {
        try JSONDecoder().decode(type, from: Data(buffer: res.body))
    }

    private func seedSchedule(_ score: LiveScore) async throws {
        try await kv.setJSON(scheduleKey, value: score, ttl: nil)
    }

    private func nbaGame(idEvent: String = "TSDB1") -> Game {
        TestGameFactory.make(
            idEvent: idEvent, strHomeTeam: "Lakers", strAwayTeam: "Celtics",
            strTimestamp: "2024-06-01T18:00:00",
            isoDate: ISO8601DateFormatter().date(from: "2024-06-01T18:00:00Z")!
        )
    }

    // MARK: - ping

    func testPingIsUnauthenticated() throws {
        try app.test(.GET, "ping") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "pong")
        }
        try app.test(.HEAD, "ping") { res in
            XCTAssertEqual(res.status, .ok)
        }
    }

    // MARK: - schedules

    func testSchedulesRequiresAPIKey() throws {
        try app.test(.GET, "v2025/schedules") { res in
            XCTAssertEqual(res.status, .forbidden)
        }
        try app.test(.GET, "v2025/schedules", headers: ["X-API-Key": "wrong-key"]) { res in
            XCTAssertEqual(res.status, .forbidden)
        }
    }

    func testSchedulesWithNoSeededDataFails() throws {
        try app.test(.GET, "v2025/schedules", headers: authed) { res in
            XCTAssertEqual(res.status, .internalServerError)
        }
    }

    func testSchedulesReturnsSeededSchedule() async throws {
        try await seedSchedule(TestGameFactory.liveScore(nba: [nbaGame()]))

        try app.test(.GET, "v2025/schedules", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            let score = try Self.decodeBody(LiveScore.self, from: res)
            XCTAssertEqual(score.nba?.events.count, 1)
            XCTAssertEqual(score.nba?.events.first?.idEvent, "TSDB1")
        }
    }

    func testLegacyUnversionedPathServesSameRoute() async throws {
        try await seedSchedule(TestGameFactory.liveScore(nba: [nbaGame()]))

        try app.test(.GET, "schedules", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            let score = try Self.decodeBody(LiveScore.self, from: res)
            XCTAssertEqual(score.nba?.events.first?.idEvent, "TSDB1")
        }
    }

    // MARK: - sport/:sport

    func testSportReturnsRequestedBucket() async throws {
        try await seedSchedule(TestGameFactory.liveScore(nba: [nbaGame()]))

        try app.test(.GET, "v2025/sport/basketball", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            let event = try Self.decodeBody(LiveEvent.self, from: res)
            XCTAssertEqual(event.events.first?.idEvent, "TSDB1")
        }
    }

    func testSportMissingBucketAndUnknownSportAreBadRequests() async throws {
        try await seedSchedule(TestGameFactory.liveScore(nba: [nbaGame()]))

        try app.test(.GET, "v2025/sport/golf", headers: authed) { res in
            XCTAssertEqual(res.status, .badRequest)
        }
        try app.test(.GET, "v2025/sport/quidditch", headers: authed) { res in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    // MARK: - teams

    func testTeamsReturnsEmptyArrayWhenUnseeded() throws {
        try app.test(.GET, "v2025/teams", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            let teams = try Self.decodeBody([Team].self, from: res)
            XCTAssertTrue(teams.isEmpty)
        }
    }

    func testTeamsReturnsSeededTeams() async throws {
        let key = RedisEndpoint.teams.getValue(isDebug: false).rawValue
        try await kv.setJSON(key, value: [Team(idTeam: "100", strTeam: "Lakers")], ttl: nil)

        try app.test(.GET, "v2025/teams", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            let teams = try Self.decodeBody([Team].self, from: res)
            XCTAssertEqual(teams.first?.strTeam, "Lakers")
        }
    }

    // MARK: - plays/:eventID

    func testPlaysTier1CacheHit() async throws {
        let key = RedisEndpoint.ESPN.playByPlay("evt1").getValue(isDebug: false).rawValue
        let cached = CachedPlays(eventID: "evt1", lastPlayId: "p9", plays: [], isFinal: false, fetchedAt: Date())
        try await kv.setJSON(key, value: cached, ttl: nil)

        try app.test(.GET, "v2025/plays/evt1", headers: authed) { res in
            XCTAssertEqual(res.status, .ok)
            let plays = try Self.decodeBody(CachedPlays.self, from: res)
            XCTAssertEqual(plays.eventID, "evt1")
            XCTAssertEqual(plays.lastPlayId, "p9")
        }
    }

    func testPlaysMissWithNoMappingAndNoParamsIs404() throws {
        try app.test(.GET, "v2025/plays/unknown-event", headers: authed) { res in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    // MARK: - pushToStart/register

    func testPushToStartRegisterStoresInstallAndTokenIndex() async throws {
        try app.test(.POST, "v2025/pushToStart/register", headers: registrationHeaders(installID: "install-1"), beforeRequest: { req in
            try req.content.encode(PushToStartRegistration(token: "tok-A", favorites: ["Lakers"], eventIDs: ["evt1"]))
        }) { res in
            XCTAssertEqual(res.status, .ok)
        }

        let installKey = RedisEndpoint.pushToStartByInstall("install-1").getValue(isDebug: false).rawValue
        let install = try await kv.getJSON(installKey, as: PushToStartInstall.self)
        XCTAssertEqual(install?.token, "tok-A")
        XCTAssertEqual(install?.favorites, ["Lakers"])
        XCTAssertEqual(install?.eventIDs, ["evt1"])

        let indexKey = RedisEndpoint.pushToStartTokenIndex("tok-A").getValue(isDebug: false).rawValue
        let indexed = try await kv.getString(indexKey)
        XCTAssertEqual(indexed, "install-1")
    }

    func testPushToStartTokenRotationDropsStaleIndex() async throws {
        // The historical duplicate-Live-Activity bug: a rotated token's old
        // reverse index must be deleted, or stale-token cleanup later nukes
        // the live install record.
        for token in ["tok-old", "tok-new"] {
            try app.test(.POST, "v2025/pushToStart/register", headers: registrationHeaders(installID: "install-1"), beforeRequest: { req in
                try req.content.encode(PushToStartRegistration(token: token, favorites: ["Lakers"]))
            }) { res in
                XCTAssertEqual(res.status, .ok)
            }
        }

        let staleIndex = RedisEndpoint.pushToStartTokenIndex("tok-old").getValue(isDebug: false).rawValue
        let newIndex = RedisEndpoint.pushToStartTokenIndex("tok-new").getValue(isDebug: false).rawValue
        let installKey = RedisEndpoint.pushToStartByInstall("install-1").getValue(isDebug: false).rawValue

        let staleValue = try await kv.getString(staleIndex)
        XCTAssertNil(staleValue)
        let newValue = try await kv.getString(newIndex)
        XCTAssertEqual(newValue, "install-1")
        let install = try await kv.getJSON(installKey, as: PushToStartInstall.self)
        XCTAssertEqual(install?.token, "tok-new")
    }

    func testPushToStartDeregisterRemovesAllState() async throws {
        try app.test(.POST, "v2025/pushToStart/register", headers: registrationHeaders(installID: "install-1"), beforeRequest: { req in
            try req.content.encode(PushToStartRegistration(token: "tok-A", favorites: ["Lakers"]))
        }) { res in
            XCTAssertEqual(res.status, .ok)
        }
        // Simulate per-event sent markers written by ESPNFetchJob
        try await kv.setString("SentPushToStart-tok-A-evt1", value: "1", ttl: nil)
        try await kv.setString("SentPushToStart-tok-A-evt2", value: "1", ttl: nil)

        try app.test(.DELETE, "v2025/pushToStart/register", headers: registrationHeaders(installID: "install-1"), beforeRequest: { req in
            try req.content.encode(DeregisterRequest(token: "tok-A"))
        }) { res in
            XCTAssertEqual(res.status, .ok)
        }

        let snapshot = kv.rawSnapshot
        XCTAssertFalse(snapshot.keys.contains(where: { $0.contains("PushToStart") }),
                       "expected all push-to-start keys removed, found: \(snapshot.keys)")
    }

    private func registrationHeaders(installID: String, apnsEnv: String = "production") -> HTTPHeaders {
        var headers = authed
        headers.add(name: "X-Install-ID", value: installID)
        headers.add(name: "X-APNS-Env", value: apnsEnv)
        return headers
    }

    // MARK: - liveActivity

    func testLiveActivitySandboxHeaderStoresUnderDebugKey() async throws {
        var headers = authed
        headers.add(name: "X-APNS-Env", value: "sandbox")
        try app.test(.POST, "v2025/liveActivity", headers: headers, beforeRequest: { req in
            try req.content.encode(LiveActivityRegistration(token: "tok-S", eventID: "evt1", homeTeam: "Lakers", awayTeam: "Celtics"))
        }) { res in
            XCTAssertEqual(res.status, .ok)
        }

        let registration = try await kv.getJSON("debug-APNS-tok-S", as: APNSRegistration.self)
        XCTAssertEqual(registration?.eventID, "evt1")
        XCTAssertEqual(registration?.environment, .sandbox)
        // 12h TTL matching the Live Activity max lifetime
        XCTAssertEqual(kv.ttl("debug-APNS-tok-S") ?? 0, 60 * 60 * 12, accuracy: 5)
    }

    func testLiveActivityWithoutHeaderFallsBackToServerEnvironment() async throws {
        // `.testing` is not development → production fallback → prod key prefix.
        try app.test(.POST, "v2025/liveActivity", headers: authed, beforeRequest: { req in
            try req.content.encode(LiveActivityRegistration(token: "tok-P", eventID: "evt2"))
        }) { res in
            XCTAssertEqual(res.status, .ok)
        }

        let registration = try await kv.getJSON("APNS-tok-P", as: APNSRegistration.self)
        XCTAssertEqual(registration?.eventID, "evt2")
        XCTAssertEqual(registration?.environment, .production)
    }

    func testLiveActivityDeleteRemovesRegistration() async throws {
        try await kv.setJSON("APNS-tok-D", value: APNSRegistration(eventID: "evt3"), ttl: nil)

        try app.test(.DELETE, "v2025/liveActivity", headers: authed, beforeRequest: { req in
            try req.content.encode(DeregisterRequest(token: "tok-D"))
        }) { res in
            XCTAssertEqual(res.status, .ok)
        }

        let registration = try await kv.getJSON("APNS-tok-D", as: APNSRegistration.self)
        XCTAssertNil(registration)
    }
}
