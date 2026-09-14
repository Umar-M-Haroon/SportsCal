@testable import App
import XCTVapor
import Redis
import Crypto
import JWT

/// Controller-layer tests for the App Attest routes.
///
/// `AppAttestVerifierTests` covers the crypto; this file covers the stateful
/// layer around it, which is where every bug found in review actually lived:
/// dual-auth fall-through re-running handlers, challenge reuse, and a counter
/// that could be walked backwards.
///
/// Two groups, with different needs:
///   - `EitherAuthMiddleware` needs no Redis (the rate limiter fails open
///     against a closed port, exactly as `RoutesTests` does).
///   - Challenge and counter behaviour is the Redis semantics — GETDEL
///     atomicity and a Lua compare-and-set — so a fake store would test the
///     fake. These use a real Redis and skip when one isn't reachable.
final class AttestControllerTests: XCTestCase {

    private static let apiKey = "test-attest-key"
    private static let signingKey = "test-signing-key-at-least-32-bytes-long!"
    private static let appID = "9GDU5ZNHX7.com.KomodoLLC.SportsCal"

    var app: Application!

    override func setUp() async throws {
        app = Application(.testing)
        app.jwt.signers.use(.hs256(key: Self.signingKey))
        setenv("API_KEY_HASH", sha256Hex(Self.apiKey), 1)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    // MARK: - Helpers

    /// Points the app at a closed port so every Redis call errors instantly.
    /// The rate limiter fails open by design, so the middleware chain stays
    /// intact without a server behind it.
    private func useUnreachableRedis() throws {
        app.redis.configuration = try RedisConfiguration(hostname: "127.0.0.1", port: 1)
    }

    /// Points the app at a real Redis, or skips the test.
    ///
    /// Boots explicitly: `app.redis` has no pool until the application has
    /// booted, and these tests touch Redis directly rather than only through
    /// `app.test()`.
    private func useRealRedis() async throws {
        app.redis.configuration = try RedisConfiguration(hostname: "127.0.0.1", port: 6379)
        try await app.asyncBoot()
        do {
            _ = try await app.redis.ping().get()
        } catch {
            throw XCTSkip("Redis is not reachable on 127.0.0.1:6379 — skipping")
        }
    }

    /// Best-effort cleanup. Keys are UUID-scoped so a leaked one is harmless,
    /// but tests that pass shouldn't leave records behind.
    private func deleteKeyRecord(_ keyID: String) async {
        _ = try? await app.redis.delete(keyRecord(keyID)).get()
    }

    private func signedToken(expiresIn: TimeInterval = 900, platform: String = "ios") throws -> String {
        try app.jwt.signers.sign(
            SportsCalJWT(
                sub: .init(value: "test-key-id"),
                exp: .init(value: Date().addingTimeInterval(expiresIn)),
                iat: .init(value: Date()),
                plt: platform
            )
        )
    }

    /// Every attest route is rate-limited per install. Real-Redis tests would
    /// otherwise share one 30/min bucket across runs and start 429ing.
    private func freshInstallHeaders() -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: "X-Install-ID", value: UUID().uuidString)
        headers.contentType = .json
        return headers
    }

    private func keyRecord(_ keyID: String) -> RedisKey { RedisKey("attest:key:\(keyID)") }

    // MARK: - EitherAuthMiddleware

    /// Registers a route behind `EitherAuthMiddleware` that counts its own
    /// invocations, so a handler run twice is directly observable.
    /// `handlerError`, when set, is thrown *from the handler* — i.e. after auth
    /// has already succeeded.
    private func registerCountingRoute(handlerError: Error? = nil) -> (count: () -> Int, Void) {
        let counter = Counter()
        app.grouped(EitherAuthMiddleware()).get("guarded") { _ -> String in
            counter.increment()
            if let handlerError { throw handlerError }
            return "ok"
        }
        return ({ counter.value }, ())
    }

    private var apiKeyHeaders: HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: "X-API-Key", value: Self.apiKey)
        return headers
    }

    func testValidJWTAlonePasses() async throws {
        try useUnreachableRedis()
        _ = registerCountingRoute()
        var headers = HTTPHeaders()
        headers.bearerAuthorization = .init(token: try signedToken())

        try await app.test(.GET, "guarded", headers: headers) { res in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testAPIKeyAlonePasses() async throws {
        try useUnreachableRedis()
        _ = registerCountingRoute()

        try await app.test(.GET, "guarded", headers: apiKeyHeaders) { res in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testExpiredJWTFallsBackToAPIKey() async throws {
        try useUnreachableRedis()
        _ = registerCountingRoute()
        var headers = apiKeyHeaders
        headers.bearerAuthorization = .init(token: try signedToken(expiresIn: -60))

        // The whole point of dual auth: a client whose attestation broke
        // mid-session keeps working on the shared key.
        try await app.test(.GET, "guarded", headers: headers) { res in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testGarbageBearerTokenFallsBackToAPIKey() async throws {
        try useUnreachableRedis()
        _ = registerCountingRoute()
        var headers = apiKeyHeaders
        headers.bearerAuthorization = .init(token: "not.a.jwt")

        try await app.test(.GET, "guarded", headers: headers) { res in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testNoCredentialsRejected() async throws {
        try useUnreachableRedis()
        let (count, _) = registerCountingRoute()

        try await app.test(.GET, "guarded") { res in
            XCTAssertEqual(res.status, .forbidden)
            XCTAssertEqual(count(), 0, "handler must not run without credentials")
        }
    }

    func testBadJWTAndBadAPIKeyRejected() async throws {
        try useUnreachableRedis()
        let (count, _) = registerCountingRoute()
        var headers = HTTPHeaders()
        headers.add(name: "X-API-Key", value: "wrong-key")
        headers.bearerAuthorization = .init(token: try signedToken(expiresIn: -60))

        try await app.test(.GET, "guarded", headers: headers) { res in
            XCTAssertEqual(res.status, .forbidden)
            XCTAssertEqual(count(), 0)
        }
    }

    /// The regression this middleware was rewritten for.
    ///
    /// When the handler ran inside the do/catch that verifies the bearer token,
    /// ANY downstream error — a 404, a decode failure, a Redis blip — was caught,
    /// misread as an auth failure, and the request was replayed down the API-key
    /// path. On the write routes that meant duplicate Redis writes and duplicate
    /// APNS registrations for a single client call.
    func testHandlerErrorIsNotRetriedDownTheAPIKeyPath() async throws {
        try useUnreachableRedis()
        let (count, _) = registerCountingRoute(handlerError: Abort(.notFound))
        var headers = apiKeyHeaders   // deliberately BOTH credentials present
        headers.bearerAuthorization = .init(token: try signedToken())

        try await app.test(.GET, "guarded", headers: headers) { res in
            XCTAssertEqual(res.status, .notFound, "the handler's own error must surface unchanged")
            XCTAssertEqual(count(), 1, "handler ran twice — dual auth is replaying requests")
        }
    }

    /// Same guarantee for a non-Abort error, which is the shape a decode failure
    /// or a Redis error actually arrives in.
    func testUnexpectedHandlerErrorAlsoRunsOnce() async throws {
        struct Boom: Error {}
        try useUnreachableRedis()
        let (count, _) = registerCountingRoute(handlerError: Boom())
        var headers = apiKeyHeaders
        headers.bearerAuthorization = .init(token: try signedToken())

        try await app.test(.GET, "guarded", headers: headers) { res in
            XCTAssertEqual(res.status, .internalServerError)
            XCTAssertEqual(count(), 1)
        }
    }

    // MARK: - Challenge lifecycle (real Redis)

    func testChallengeIsSingleUse() async throws {
        try await useRealRedis()
        try app.register(collection: AttestController(allowDevTokens: false))

        let headers = freshInstallHeaders()
        var challengeID = ""
        try await app.test(.POST, "attest/challenge", headers: headers, body: .init(string: "{}")) { res in
            XCTAssertEqual(res.status, .ok)
            challengeID = try res.content.decode(ChallengeResponse.self).challengeID
        }

        // A keyID we hold no record for, so the request fails *after* the
        // challenge is consumed — which is what we're actually measuring.
        let body = #"{"keyID":"unknown","assertion":"AAAA","challengeID":"\#(challengeID)"}"#

        try await app.test(.POST, "attest/refresh", headers: headers, body: .init(string: body)) { res in
            XCTAssertEqual(res.status, .unauthorized, "first use should get past the challenge check")
        }
        try await app.test(.POST, "attest/refresh", headers: headers, body: .init(string: body)) { res in
            XCTAssertEqual(res.status, .badRequest, "a consumed challenge must not be reusable")
        }
    }

    func testUnknownChallengeIDIsRejected() async throws {
        try await useRealRedis()
        try app.register(collection: AttestController(allowDevTokens: false))

        let body = #"{"keyID":"unknown","assertion":"AAAA","challengeID":"\#(UUID().uuidString)"}"#
        try await app.test(.POST, "attest/refresh", headers: freshInstallHeaders(), body: .init(string: body)) { res in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testChallengeIsStoredWithATTL() async throws {
        try await useRealRedis()
        try app.register(collection: AttestController(allowDevTokens: false))

        var challengeID = ""
        try await app.test(.POST, "attest/challenge", headers: freshInstallHeaders(), body: .init(string: "{}")) { res in
            challengeID = try res.content.decode(ChallengeResponse.self).challengeID
        }

        // SETEX, not SET-then-EXPIRE: an unauthenticated endpoint that can leave
        // immortal keys behind is an attacker-drivable Redis leak.
        let ttl = try await app.redis.send(command: "TTL", with: [.init(from: RedisKey("attest:challenge:\(challengeID)"))]).get()
        let seconds = ttl.int ?? -1
        XCTAssertGreaterThan(seconds, 0, "challenge key has no TTL")
        XCTAssertLessThanOrEqual(seconds, 300)
    }

    // MARK: - Re-attest signalling (real Redis)

    /// A keyID the server holds no public key for is the ONE case where the
    /// client should discard its Secure Enclave key and attest afresh.
    func testUnknownKeyIDAsksTheClientToReAttest() async throws {
        try await useRealRedis()
        try app.register(collection: AttestController(allowDevTokens: false))

        let headers = freshInstallHeaders()
        var challengeID = ""
        try await app.test(.POST, "attest/challenge", headers: headers, body: .init(string: "{}")) { res in
            challengeID = try res.content.decode(ChallengeResponse.self).challengeID
        }

        let body = #"{"keyID":"no-such-key","assertion":"AAAA","challengeID":"\#(challengeID)"}"#
        try await app.test(.POST, "attest/refresh", headers: headers, body: .init(string: body)) { res in
            XCTAssertEqual(res.status, .unauthorized)
            XCTAssertEqual(
                res.headers.first(name: AttestAction.header), AttestAction.reAttest,
                "client cannot tell it needs to re-attest"
            )
        }
    }

    /// A rejected assertion is NOT a lost key. Re-attesting spends one of
    /// Apple's rate-limited `attestKey` calls and fixes nothing, so the server
    /// must not ask for it.
    func testRejectedAssertionDoesNotAskTheClientToReAttest() async throws {
        try await useRealRedis()
        app.appAttest = AppAttestVerifier(appID: Self.appID, allowDevelopmentEnvironment: true)
        try app.register(collection: AttestController(allowDevTokens: false))

        // Register a key, then assert with a DIFFERENT one: well-formed CBOR,
        // valid ECDSA structure, wrong signer.
        let realKey = P256.Signing.PrivateKey()
        let impostor = P256.Signing.PrivateKey()
        let keyID = UUID().uuidString
        try await app.redis.hmset(
            ["publicKey": realKey.publicKey.x963Representation.base64EncodedString(), "counter": "0"],
            in: keyRecord(keyID)
        ).get()

        let headers = freshInstallHeaders()
        var challenge = ChallengeResponse(challengeID: "", challenge: "")
        try await app.test(.POST, "attest/challenge", headers: headers, body: .init(string: "{}")) { res in
            challenge = try res.content.decode(ChallengeResponse.self)
        }

        let assertion = try AssertionVector.make(
            key: impostor, appID: Self.appID, challenge: challenge.challenge, counter: 1
        )
        let body = #"{"keyID":"\#(keyID)","assertion":"\#(assertion.base64EncodedString())","challengeID":"\#(challenge.challengeID)"}"#

        try await app.test(.POST, "attest/refresh", headers: headers, body: .init(string: body)) { res in
            XCTAssertEqual(res.status, .unauthorized)
            XCTAssertNil(
                res.headers.first(name: AttestAction.header),
                "a bad assertion must not send the client into a re-attest loop"
            )
        }
        await deleteKeyRecord(keyID)
    }

    // MARK: - Counter monotonicity (real Redis)

    /// The counter is the assertion replay guard. A plain HSET made it racy:
    /// two concurrent refreshes both read N, verify N+1 and N+2, and whichever
    /// write lands last wins — so the LOWER value could end up stored and the
    /// higher assertion became replayable.
    func testStoredCounterNeverGoesBackwards() async throws {
        try await useRealRedis()
        let controller = AttestController(allowDevTokens: false)
        let keyID = UUID().uuidString
        let req = Request(application: app, method: .POST, url: "/x", on: app.eventLoopGroup.next())

        try await controller.storeCounterMonotonically(9, keyID: keyID, on: req)
        let afterFirst = try await storedCounter(keyID)
        XCTAssertEqual(afterFirst, 9)

        // The out-of-order arrival: a lower counter must not overwrite.
        try await controller.storeCounterMonotonically(3, keyID: keyID, on: req)
        let afterRewind = try await storedCounter(keyID)
        XCTAssertEqual(afterRewind, 9, "a stale assertion rewound the replay guard")

        // Equal is not an advance either — that is precisely a replay.
        try await controller.storeCounterMonotonically(9, keyID: keyID, on: req)
        let afterReplay = try await storedCounter(keyID)
        XCTAssertEqual(afterReplay, 9)

        try await controller.storeCounterMonotonically(10, keyID: keyID, on: req)
        let afterAdvance = try await storedCounter(keyID)
        XCTAssertEqual(afterAdvance, 10, "a genuine advance must be stored")
        await deleteKeyRecord(keyID)
    }

    func testCounterIsStoredFromAbsent() async throws {
        try await useRealRedis()
        let controller = AttestController(allowDevTokens: false)
        let keyID = UUID().uuidString
        let req = Request(application: app, method: .POST, url: "/x", on: app.eventLoopGroup.next())

        try await controller.storeCounterMonotonically(1, keyID: keyID, on: req)
        let stored = try await storedCounter(keyID)
        XCTAssertEqual(stored, 1)
        await deleteKeyRecord(keyID)
    }

    private func storedCounter(_ keyID: String) async throws -> UInt32? {
        try await app.redis.hget("counter", from: keyRecord(keyID)).get().string.flatMap(UInt32.init)
    }

    // MARK: - Rollout policy

    func testAuthPolicyDefaultsToDual() {
        unsetenv("AUTH_POLICY")
        XCTAssertEqual(AuthPolicy.fromEnvironment(app.logger), .dual)
    }

    func testUnrecognizedAuthPolicyFallsBackToDual() {
        // Fail toward availability: a typo in the deploy env must not lock every
        // installed client out of the API.
        setenv("AUTH_POLICY", "jwt-everything", 1)
        defer { unsetenv("AUTH_POLICY") }
        XCTAssertEqual(AuthPolicy.fromEnvironment(app.logger), .dual)
    }

    func testAuthPolicyParsesEachPhase() {
        for (raw, expected) in [("dual", AuthPolicy.dual), ("jwt-writes", .jwtWrites), ("jwt-strict", .jwtStrict)] {
            setenv("AUTH_POLICY", raw, 1)
            XCTAssertEqual(AuthPolicy.fromEnvironment(app.logger), expected, "AUTH_POLICY=\(raw)")
        }
        // Case and padding come from hand-edited env files.
        setenv("AUTH_POLICY", "  JWT-Writes ", 1)
        XCTAssertEqual(AuthPolicy.fromEnvironment(app.logger), .jwtWrites)
        unsetenv("AUTH_POLICY")
    }

    func testDualPolicyLayersNoExtraWriteAuth() {
        XCTAssertNil(AuthPolicy.dual.writeMiddleware, "phase 1 must not tighten writes")
        XCTAssertNotNil(AuthPolicy.jwtWrites.writeMiddleware)
        XCTAssertNotNil(AuthPolicy.jwtStrict.writeMiddleware)
    }

    // MARK: - Platform-scoped JWT

    /// A relayed watch token is a real credential for reads and must stay
    /// useless for writes — that is the whole reason it carries its own `plt`.
    func testWriteRoutesRejectRelayedWatchTokens() async throws {
        try useUnreachableRedis()
        let counter = Counter()
        app.grouped(JWTMiddleware(allowedPlatforms: AuthPolicy.writeCapablePlatforms))
            .get("write-ish") { _ -> String in counter.increment(); return "ok" }

        var headers = HTTPHeaders()
        headers.bearerAuthorization = .init(token: try signedToken(platform: "ios-proxy-watch"))
        try await app.test(.GET, "write-ish", headers: headers) { res in
            XCTAssertEqual(res.status, .forbidden)
            XCTAssertEqual(counter.value, 0)
        }

        headers.bearerAuthorization = .init(token: try signedToken(platform: "ios"))
        try await app.test(.GET, "write-ish", headers: headers) { res in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testUnrestrictedJWTMiddlewareAcceptsProxyTokens() async throws {
        try useUnreachableRedis()
        // Reads under jwt-strict use the unrestricted form — the watch must pass.
        app.grouped(JWTMiddleware()).get("read-ish") { _ in "ok" }

        var headers = HTTPHeaders()
        headers.bearerAuthorization = .init(token: try signedToken(platform: "ios-proxy-watch"))
        try await app.test(.GET, "read-ish", headers: headers) { res in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testJWTMiddlewareRejectsMissingAndInvalidTokens() async throws {
        try useUnreachableRedis()
        app.grouped(JWTMiddleware()).get("read-ish") { _ in "ok" }

        try await app.test(.GET, "read-ish") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        var headers = HTTPHeaders()
        headers.bearerAuthorization = .init(token: try signedToken(expiresIn: -60))
        try await app.test(.GET, "read-ish", headers: headers) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        // The shared key is explicitly NOT a substitute here — that is the point
        // of phase 3.
        try await app.test(.GET, "read-ish", headers: apiKeyHeaders) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    // MARK: - Watch proxy tokens

    func testProxyTokenIsMintedForAnAttestedCaller() async throws {
        try await useRealRedis()
        try app.register(collection: AttestController(allowDevTokens: false))

        var headers = freshInstallHeaders()
        headers.bearerAuthorization = .init(token: try signedToken(platform: "ios"))

        try await app.test(.POST, "attest/proxy", headers: headers, body: .init(string: "{}")) { res in
            XCTAssertEqual(res.status, .ok)
            let token = try res.content.decode(TokenResponse.self)
            let payload = try app.jwt.signers.verify(token.token, as: SportsCalJWT.self)
            XCTAssertEqual(payload.plt, "ios-proxy-watch")
            XCTAssertEqual(payload.sub.value, "test-key-id", "proxy token must inherit the phone's keyID so revocation cascades")
        }
    }

    /// A watch cannot bootstrap further credentials from the one it was handed.
    func testProxyTokenCannotMintAnotherProxyToken() async throws {
        try await useRealRedis()
        try app.register(collection: AttestController(allowDevTokens: false))

        var headers = freshInstallHeaders()
        headers.bearerAuthorization = .init(token: try signedToken(platform: "ios-proxy-watch"))
        try await app.test(.POST, "attest/proxy", headers: headers, body: .init(string: "{}")) { res in
            XCTAssertEqual(res.status, .forbidden)
        }
    }

    /// Minting a credential must never be reachable with the shared key that
    /// App Attest exists to replace.
    func testProxyTokenIsNotReachableWithTheSharedKey() async throws {
        try await useRealRedis()
        try app.register(collection: AttestController(allowDevTokens: false))

        var headers = freshInstallHeaders()
        headers.add(name: "X-API-Key", value: Self.apiKey)
        try await app.test(.POST, "attest/proxy", headers: headers, body: .init(string: "{}")) { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    // MARK: - Dev token route

    func testDevTokenRouteIsNotRegisteredInProduction() async throws {
        try await useRealRedis()
        try app.register(collection: AttestController(allowDevTokens: false))

        // Not merely blocked — never registered, so it 404s rather than 403s.
        try await app.test(.POST, "attest/dev", headers: freshInstallHeaders(), body: .init(string: "{}")) { res in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    func testDevTokenRouteStillRequiresTheSharedKey() async throws {
        try await useRealRedis()
        try app.register(collection: AttestController(allowDevTokens: true))

        try await app.test(.POST, "attest/dev", headers: freshInstallHeaders(), body: .init(string: "{}")) { res in
            XCTAssertEqual(res.status, .forbidden, "dev tokens must not be an open faucet on a reachable dev host")
        }

        var headers = freshInstallHeaders()
        headers.add(name: "X-API-Key", value: Self.apiKey)
        try await app.test(.POST, "attest/dev", headers: headers, body: .init(string: "{}")) { res in
            XCTAssertEqual(res.status, .ok)
            let token = try res.content.decode(TokenResponse.self)
            let payload = try app.jwt.signers.verify(token.token, as: SportsCalJWT.self)
            XCTAssertEqual(payload.plt, "dev", "dev tokens must be distinguishable from attested ones")
        }
    }
}

/// Minimal thread-safe counter — the handler runs on an event loop, the
/// assertion on the test thread.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}
