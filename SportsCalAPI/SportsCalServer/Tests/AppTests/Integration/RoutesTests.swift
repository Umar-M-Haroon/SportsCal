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
        // The schedule snapshot is process-global; don't inherit another test's.
        await LastKnownGoodCache.shared.reset()
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

    // MARK: - Client Telemetry

    private var telemetryDay: Int { Int(Date().timeIntervalSince1970) / 86_400 }

    func testTelemetryAllowedEventIncrementsCounter() async throws {
        try app.test(.POST, "v2025/telemetry", headers: authed, beforeRequest: { req in
            try req.content.encode(ClientTelemetryEvent(event: "paywall_shown", fields: ["trigger": "postOnboarding"]))
        }) { res in
            XCTAssertEqual(res.status, .ok)
        }
        let snapshot = kv.rawSnapshot
        XCTAssertEqual(snapshot["telemetry:client.paywall_shown:unknown:\(telemetryDay)"], "1",
                       "pre-channel clients feed the namespaced per-day counter under `unknown`")
    }

    func testTelemetryChannelTaggedEventWritesChannelDimensionAndUniqueKeys() async throws {
        var headers = authed
        headers.add(name: "X-Install-ID", value: "install-1")
        try app.test(.POST, "v2025/telemetry", headers: headers, beforeRequest: { req in
            try req.content.encode(ClientTelemetryEvent(event: "paywall_shown", fields: [
                "trigger": "nth_session", "channel": "appstore", "platform": "ios", "build": "412",
            ]))
        }) { res in
            XCTAssertEqual(res.status, .ok)
        }
        let day = telemetryDay
        let snapshot = kv.rawSnapshot
        XCTAssertEqual(snapshot["telemetry:client.paywall_shown:appstore:\(day)"], "1")
        XCTAssertEqual(snapshot["telemetry:client.paywall_shown:appstore:trigger=nth_session:\(day)"], "1")
        let uniques = try await kv.hllCount(["telemetry:uniq:client.paywall_shown:appstore:\(day)"])
        XCTAssertEqual(uniques, 1)
        XCTAssertFalse(snapshot.keys.contains { $0.contains("412") }, "build is log-only, never a key segment")
    }

    func testTelemetryUnknownChannelIsNormalized() async throws {
        try app.test(.POST, "v2025/telemetry", headers: authed, beforeRequest: { req in
            try req.content.encode(ClientTelemetryEvent(event: "gate_hit", fields: ["channel": "evil*chan"]))
        }) { res in
            XCTAssertEqual(res.status, .ok)
        }
        let snapshot = kv.rawSnapshot
        XCTAssertEqual(snapshot["telemetry:client.gate_hit:unknown:\(telemetryDay)"], "1")
        XCTAssertFalse(snapshot.keys.contains { $0.contains("evil") }, "free-form channels must not mint keys")
    }

    func testTelemetryAppActiveFeedsDAU() async throws {
        for (install, platform) in [("i1", "ios"), ("i1", "ios"), ("m1", "macos")] {
            var headers = authed
            headers.add(name: "X-Install-ID", value: install)
            try app.test(.POST, "v2025/telemetry", headers: headers, beforeRequest: { req in
                try req.content.encode(ClientTelemetryEvent(event: "app_active", fields: [
                    "channel": "appstore", "platform": platform,
                ]))
            }) { res in
                XCTAssertEqual(res.status, .ok)
            }
        }
        let day = telemetryDay
        let ios = try await kv.hllCount(["telemetry:dau:appstore:ios:\(day)"])
        let all = try await kv.hllCount(["telemetry:dau:appstore:ios:\(day)", "telemetry:dau:appstore:macos:\(day)"])
        XCTAssertEqual(ios, 1)
        XCTAssertEqual(all, 2)
        XCTAssertEqual(kv.rawSnapshot["telemetry:client.app_active:appstore:\(day)"], "3",
                       "the plain counter still counts every ping")
    }

    func testAdminTelemetryReportsChannelsActiveUsersAndConversion() async throws {
        let adminKey = "admin-test-key"
        let adminHash = SHA256.hash(data: Data(adminKey.utf8)).map { String(format: "%02x", $0) }.joined()
        setenv("ADMIN_API_KEY_HASH", adminHash, 1)
        defer { unsetenv("ADMIN_API_KEY_HASH") }

        let day = telemetryDay
        // Legacy (pre-channel) shape still readable.
        _ = try await kv.increment("telemetry:client.paywall_shown:\(day)", ttl: 3600)
        _ = try await kv.increment("telemetry:apns.tick:\(day)", ttl: 3600)
        let clock = SystemClock()
        let counters = ClientTelemetryCounters(kv: kv, clock: clock)
        let telemetry = RedisTelemetry(kv: kv, clock: clock)
        for id in ["A", "B", "C", "D"] {
            await counters.record(event: "app_active", channel: "appstore", platform: "ios", installID: id, fields: [:])
        }
        await counters.record(event: "app_active", channel: "debug", platform: "macos", installID: "DEV", fields: [:])
        for id in ["A", "A", "B"] {
            await telemetry.info("client.paywall_shown", ["channel": "appstore"])
            await counters.record(event: "paywall_shown", channel: "appstore", platform: "ios",
                                  installID: id, fields: ["trigger": "post_onboarding"])
        }
        await counters.record(event: "trial_started", channel: "appstore", platform: "ios", installID: "A", fields: [:])
        await counters.record(event: "purchase_completed", channel: "appstore", platform: "ios", installID: "A", fields: [:])

        try app.test(.GET, "api/admin/telemetry?days=7", headers: ["X-Admin-API-Key": adminKey]) { res in
            XCTAssertEqual(res.status, .ok)
            let body = try res.content.decode(AdminController.TelemetryResponse.self)
            XCTAssertEqual(body.windowDays, 7)
            XCTAssertEqual(body.counters["client.paywall_shown"]?[String(day)], 1, "legacy key shape still parsed")
            XCTAssertEqual(body.counters["apns.tick"]?[String(day)], 1)
            XCTAssertEqual(body.channels["appstore"]?["client.paywall_shown"]?[String(day)], 3)
            XCTAssertEqual(body.dimensions["appstore"]?["client.paywall_shown"]?["trigger=post_onboarding"]?[String(day)], 3)
            XCTAssertEqual(body.activeUsers["appstore"]?.total.dau, 4)
            XCTAssertEqual(body.activeUsers["appstore"]?.total.mau, 4)
            XCTAssertEqual(body.activeUsers["appstore"]?.byPlatform["ios"]?.wau, 4)
            XCTAssertEqual(body.activeUsers["debug"]?.total.dau, 1, "debug is segregated, not dropped")
            XCTAssertEqual(body.activeUsers["all"]?.total.dau, 5)
            XCTAssertEqual(body.uniqueInstalls["appstore"]?["client.paywall_shown"], 2)
            XCTAssertEqual(body.uniqueInstalls["appstore"]?["client.purchase_or_trial"], 1,
                           "trial + purchase by the same install is one converter")
        }
    }

    func testTelemetryUnknownEventIsDroppedButStillOK() async throws {
        try app.test(.POST, "v2025/telemetry", headers: authed, beforeRequest: { req in
            try req.content.encode(ClientTelemetryEvent(event: "not_on_the_allow_list", fields: nil))
        }) { res in
            XCTAssertEqual(res.status, .ok, "fail-open: unknown events never error the client")
        }
        let snapshot = kv.rawSnapshot
        XCTAssertNil(snapshot["telemetry:client.not_on_the_allow_list:\(telemetryDay)"],
                     "disallowed events must not mint arbitrary counter keys")
    }

    func testTelemetryRequiresAPIKey() throws {
        try app.test(.POST, "v2025/telemetry", beforeRequest: { req in
            try req.content.encode(ClientTelemetryEvent(event: "paywall_shown"))
        }) { res in
            XCTAssertEqual(res.status, .forbidden, "APIKeyMiddleware rejects missing keys with 403")
        }
    }

    // MARK: - Universal Links

    func testAppSiteAssociationIsPublicJSON() throws {
        // Apple's CDN fetches this unauthenticated; it must be 200 JSON, no key.
        try app.test(.GET, ".well-known/apple-app-site-association") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.headers.contentType, .json)
            XCTAssertTrue(res.body.string.contains("com.KomodoLLC.SportsCal"),
                          "AASA must declare the app ID for applinks validation")
            XCTAssertTrue(res.body.string.contains("/g/*"))
        }
    }

    func testGameWebFallbackServesAppStoreBanner() throws {
        try app.test(.GET, "g/TSDB1") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.headers.contentType, .html)
            XCTAssertTrue(res.body.string.contains("app-id=1580232928"),
                          "web fallback shows the App Store smart banner")
        }
    }

    // MARK: - F1 session detail

    private func seedF1Session(key: Int, start: String) async throws {
        let detail = F1SessionDetail(
            sessionKey: key, sessionName: "Race", dateStart: start, totalLaps: 51, timing: nil,
            lapPositions: [F1LapPositions(driverNumber: 63, acronym: "RUS", name: "George Russell", teamColour: "00D7B6", positions: [1, 1])],
            neutralizations: [F1Neutralization(kind: .safetyCar, startLap: 31, endLap: 35)],
            redFlagLaps: [], weather: nil
        )
        try await kv.setJSON(F1SessionDetailJob.detailKey(key, isDebug: false), value: detail, ttl: nil)
        try await kv.setJSON(F1SessionDetailJob.indexKey(isDebug: false),
                             value: [F1SessionDetailJob.IndexEntry(sessionKey: key, sessionName: "Race", dateStart: start)], ttl: nil)
    }

    func testF1SessionMatchesByStartTimeWithinTolerance() async throws {
        try await seedF1Session(key: 11377, start: "2026-09-26T11:00:00.000000+00:00")

        // ESPN's minute-precision start, 0 min off; then 2h off (still matches).
        for start in ["2026-09-26T11:00Z", "2026-09-26T13:00Z"] {
            try app.test(.GET, "v2025/f1/session?start=\(start)", headers: authed) { res in
                XCTAssertEqual(res.status, .ok)
                let detail = try Self.decodeBody(F1SessionDetail.self, from: res)
                XCTAssertEqual(detail.sessionKey, 11377)
                XCTAssertEqual(detail.neutralizations.first?.startLap, 31)
            }
        }
    }

    func testF1SessionNotFoundOutsideTolerance() async throws {
        try await seedF1Session(key: 11377, start: "2026-09-26T11:00:00+00:00")
        try app.test(.GET, "v2025/f1/session?start=2026-09-27T11:00Z", headers: authed) { res in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    func testF1SessionRejectsMissingOrBadStart() throws {
        try app.test(.GET, "v2025/f1/session", headers: authed) { res in
            XCTAssertEqual(res.status, .badRequest)
        }
        try app.test(.GET, "v2025/f1/session?start=not-a-date", headers: authed) { res in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testF1SessionRequiresAPIKey() throws {
        try app.test(.GET, "v2025/f1/session?start=2026-09-26T11:00Z") { res in
            XCTAssertEqual(res.status, .forbidden)
        }
    }
}
