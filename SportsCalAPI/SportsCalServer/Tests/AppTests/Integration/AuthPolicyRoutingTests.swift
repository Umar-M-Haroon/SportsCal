@testable import App
import XCTVapor
import Redis
import Crypto
import JWT

/// End-to-end proof that `AUTH_POLICY` actually changes what the real route
/// tree accepts.
///
/// `AttestControllerTests` covers the middlewares in isolation; this file boots
/// `routes(app)` under each policy and checks the credential requirement on a
/// genuine write route (`/v2025/pushToStart/register`) and a genuine read route.
/// That distinction is the whole rollout: writes tighten first, reads stay open
/// to the shared key until the widget and watch carry tokens of their own.
///
/// Follows `RoutesTests`: in-memory KV, Redis pointed at a closed port so the
/// rate limiter fails open, no `configure(app)`.
final class AuthPolicyRoutingTests: XCTestCase {

    private static let apiKey = "test-policy-key"
    private static let signingKey = "test-signing-key-at-least-32-bytes-long!"

    private let writeRoute = "v2025/pushToStart/register"
    private let readRoute  = "v2025/teams"

    var app: Application!

    private func boot(policy: AuthPolicy) async throws {
        app = Application(.testing)
        app.kv = InMemoryKeyValueStore()
        app.redis.configuration = try RedisConfiguration(hostname: "127.0.0.1", port: 1)
        app.jwt.signers.use(.hs256(key: Self.signingKey))
        setenv("API_KEY_HASH", sha256Hex(Self.apiKey), 1)
        app.authPolicy = policy
        try routes(app)
    }

    override func tearDown() async throws {
        if app != nil {
            try await app.asyncShutdown()
            app = nil
        }
    }

    // MARK: - Helpers

    private func token(platform: String) throws -> String {
        try app.jwt.signers.sign(
            SportsCalJWT(
                sub: .init(value: "phone-key"),
                exp: .init(value: Date().addingTimeInterval(900)),
                iat: .init(value: Date()),
                plt: platform
            )
        )
    }

    private var sharedKeyOnly: HTTPHeaders {
        ["X-API-Key": Self.apiKey, "X-Install-ID": UUID().uuidString]
    }

    private func bearer(_ platform: String, withSharedKey: Bool = false) throws -> HTTPHeaders {
        var headers: HTTPHeaders = ["X-Install-ID": UUID().uuidString]
        if withSharedKey { headers.add(name: "X-API-Key", value: Self.apiKey) }
        headers.bearerAuthorization = .init(token: try token(platform: platform))
        return headers
    }

    /// Auth is the only thing under test. A request that gets past it may still
    /// fail on a malformed body or the deliberately-unreachable Redis — what
    /// matters is that it was not turned away at the door.
    private func assertAuthorized(_ res: XCTHTTPResponse, _ message: String) {
        XCTAssertNotEqual(res.status, .unauthorized, message)
        XCTAssertNotEqual(res.status, .forbidden, message)
    }

    // MARK: - Phase 1: dual

    func testDualPolicyAcceptsSharedKeyOnWrites() async throws {
        try await boot(policy: .dual)
        // The pre-3.2 installed base sends exactly this and nothing else.
        try await app.test(.POST, writeRoute, headers: sharedKeyOnly, body: .init(string: "{}")) { res in
            assertAuthorized(res, "phase 1 must not break clients that only have the shared key")
        }
    }

    func testDualPolicyAcceptsJWTOnWrites() async throws {
        try await boot(policy: .dual)
        try await app.test(.POST, writeRoute, headers: try bearer("ios"), body: .init(string: "{}")) { res in
            assertAuthorized(res, "a 3.2 client's token must work during dual auth")
        }
    }

    // MARK: - Phase 2: jwt-writes

    func testJWTWritesPolicyRejectsSharedKeyOnWrites() async throws {
        try await boot(policy: .jwtWrites)
        try await app.test(.POST, writeRoute, headers: sharedKeyOnly, body: .init(string: "{}")) { res in
            XCTAssertEqual(res.status, .unauthorized, "phase 2 must refuse a bare shared key on writes")
        }
    }

    func testJWTWritesPolicyAcceptsAttestedWrites() async throws {
        try await boot(policy: .jwtWrites)
        try await app.test(.POST, writeRoute, headers: try bearer("ios", withSharedKey: true), body: .init(string: "{}")) { res in
            assertAuthorized(res, "an attested main-app client must still be able to write in phase 2")
        }
    }

    /// The watch and widget cannot attest as themselves, so phase 2 deliberately
    /// leaves reads on dual auth. Tightening both at once is what would break them.
    func testJWTWritesPolicyLeavesReadsOnDualAuth() async throws {
        try await boot(policy: .jwtWrites)
        try await app.test(.GET, readRoute, headers: sharedKeyOnly) { res in
            assertAuthorized(res, "phase 2 must not tighten reads — the widget and watch still need them")
        }
    }

    func testJWTWritesPolicyRejectsRelayedWatchTokenOnWrites() async throws {
        try await boot(policy: .jwtWrites)
        try await app.test(.POST, writeRoute, headers: try bearer("ios-proxy-watch"), body: .init(string: "{}")) { res in
            XCTAssertEqual(res.status, .forbidden, "a relayed watch token must never register push tokens")
        }
    }

    // MARK: - Phase 3: jwt-strict

    func testJWTStrictPolicyRejectsSharedKeyOnReads() async throws {
        try await boot(policy: .jwtStrict)
        try await app.test(.GET, readRoute, headers: sharedKeyOnly) { res in
            XCTAssertEqual(res.status, .unauthorized, "phase 3 retires the shared key on reads too")
        }
    }

    /// The watch's whole purpose for a proxy token: reads must work with it.
    func testJWTStrictPolicyAcceptsRelayedWatchTokenOnReads() async throws {
        try await boot(policy: .jwtStrict)
        try await app.test(.GET, readRoute, headers: try bearer("ios-proxy-watch")) { res in
            assertAuthorized(res, "the watch's relayed token must satisfy reads under phase 3")
        }
    }

    func testJWTStrictPolicyStillRejectsRelayedWatchTokenOnWrites() async throws {
        try await boot(policy: .jwtStrict)
        try await app.test(.POST, writeRoute, headers: try bearer("ios-proxy-watch"), body: .init(string: "{}")) { res in
            XCTAssertEqual(res.status, .forbidden)
        }
    }

    func testJWTStrictPolicyAcceptsAttestedReadsAndWrites() async throws {
        try await boot(policy: .jwtStrict)
        try await app.test(.GET, readRoute, headers: try bearer("ios")) { res in
            assertAuthorized(res, "attested reads must work under phase 3")
        }
        try await app.test(.POST, writeRoute, headers: try bearer("ios"), body: .init(string: "{}")) { res in
            assertAuthorized(res, "attested writes must work under phase 3")
        }
    }

    // MARK: - Unauthenticated surface is unaffected by policy

    func testPingStaysOpenUnderEveryPolicy() async throws {
        for policy in [AuthPolicy.dual, .jwtWrites, .jwtStrict] {
            try await boot(policy: policy)
            try await app.test(.GET, "ping") { res in
                XCTAssertEqual(res.status, .ok, "health checks must not depend on the auth policy (\(policy.rawValue))")
            }
            try await app.asyncShutdown()
            app = nil
        }
    }
}
