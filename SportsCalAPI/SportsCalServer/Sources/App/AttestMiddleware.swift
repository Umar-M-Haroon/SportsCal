import Vapor
import JWT
import Crypto
import Redis

// MARK: - JWT payload

/// Claims we ship in every SportsCal session token.
/// `sub` is the App Attest keyID (base64) — binds the JWT to a specific
/// Secure Enclave key on a specific install. `exp` keeps the window tight
/// so a leaked token ages out quickly; refresh is cheap via assertion.
struct SportsCalJWT: JWTPayload {
    var sub: SubjectClaim       // App Attest keyID
    var exp: ExpirationClaim    // 15 min from issue
    var iat: IssuedAtClaim
    var plt: String             // "ios" | "ios-proxy-watch" | "dev"

    func verify(using signer: JWTSigner) throws {
        try exp.verifyNotExpired()
    }
}

// MARK: - JWT bearer middleware

/// Gates API routes. Reads `Authorization: Bearer <jwt>`, verifies signature
/// + expiry, stashes the payload in `req.auth` so handlers can read the
/// caller's keyID without re-parsing.
struct JWTMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let header = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "missing bearer token")
        }
        let payload: SportsCalJWT
        do {
            payload = try request.jwt.verify(header, as: SportsCalJWT.self)
        } catch {
            throw Abort(.unauthorized, reason: "invalid token")
        }
        request.auth.login(payload)
        return try await next.respond(to: request)
    }
}

extension SportsCalJWT: Authenticatable {}

// MARK: - Dual auth (rollout phase 1)

/// Accepts a request that carries EITHER a valid App Attest JWT OR a valid
/// shared `X-API-Key`.
///
/// This exists purely for the migration window. The server cannot require a JWT
/// until effectively every installed client sends one, and clients in the field
/// today only know about the shared key. So 3.2 ships sending both, this
/// middleware accepts either, and once adoption is high enough the write routes
/// swap to plain `JWTMiddleware` (see docs/app-attest-plan.md, phases 2-3).
///
/// It is strictly no weaker than `APIKeyMiddleware` alone, which is what these
/// routes used before.
struct EitherAuthMiddleware: AsyncMiddleware {
    private let apiKey = APIKeyMiddleware()

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Authenticate the bearer token *inline* rather than delegating to
        // JWTMiddleware, and keep `next` strictly outside the do/catch. If the
        // handler ran inside it, any ordinary downstream error — a 404, a decode
        // failure, a Redis blip — would be caught, misread as an auth failure,
        // and the handler would run a SECOND time via the API-key path. On these
        // write routes that means duplicate Redis writes and APNS registrations.
        var authenticated = false
        if let token = request.headers.bearerAuthorization?.token {
            do {
                let payload = try request.jwt.verify(token, as: SportsCalJWT.self)
                request.auth.login(payload)
                authenticated = true
            } catch {
                // A malformed/expired bearer token is not fatal while the shared
                // key is still valid — fall through so a client whose attestation
                // broke mid-session keeps working. Logged so we can watch the
                // failure rate during rollout before flipping to JWT-only.
                request.logger.info("bearer token rejected, falling back to API key")
            }
        }
        if authenticated {
            return try await next.respond(to: request)
        }
        return try await apiKey.respond(to: request, chainingTo: next)
    }
}

// MARK: - DTOs

struct ChallengeResponse: Content {
    let challengeID: String   // opaque server-side key
    let challenge: String     // 32 random bytes, base64
}

struct AttestRequest: Content {
    let keyID: String          // base64 (from DCAppAttestService.generateKey)
    let attestation: String    // base64 CBOR blob
    let challengeID: String
}

struct AssertRequest: Content {
    let keyID: String
    let assertion: String      // base64
    let challengeID: String
}

struct TokenResponse: Content {
    let token: String
    let expiresIn: Int         // seconds — let the client refresh proactively
}

// MARK: - Routes

/// Exposes: POST /attest/challenge, POST /attest/verify, POST /attest/refresh.
/// Register at the top level — NOT behind JWTMiddleware (obviously).
struct AttestController: RouteCollection {

    /// Whether to expose `POST /attest/dev`. False in production — the route is
    /// not merely blocked there, it is never registered.
    let allowDevTokens: Bool

    init(allowDevTokens: Bool) {
        self.allowDevTokens = allowDevTokens
    }

    func boot(routes: RoutesBuilder) throws {
        // Attestation is unauthenticated by necessity (it is how a client earns
        // credentials), so it carries its own rate limit. The ceiling is low:
        // a healthy client attests once per install and refreshes every ~15 min.
        let grp = routes
            .grouped(RateLimitMiddleware(limit: 30, windowSeconds: 60, keyPrefix: "rl:attest", ipCeiling: 300))
            .grouped("attest")
        grp.post("challenge", use: challenge)
        grp.post("verify",    use: verify)
        grp.post("refresh",   use: refresh)

        if allowDevTokens {
            // Simulator and unit tests can't attest. This mints an equivalent
            // JWT with plt:"dev" so the rest of the stack behaves identically.
            // Still behind the shared API key so it isn't an open token faucet
            // on a reachable dev host.
            grp.grouped(APIKeyMiddleware()).post("dev", use: devToken)
        }
    }

    /// Non-production only. Mints a `plt: "dev"` token not bound to any Secure
    /// Enclave key. Handlers that care about provenance can check `plt`.
    func devToken(_ req: Request) async throws -> TokenResponse {
        guard allowDevTokens else { throw Abort(.notFound) }
        req.logger.notice("issued a dev attestation token — this must never happen in production")
        return try mintToken(keyID: "dev-\(UUID().uuidString)", platform: "dev", on: req)
    }

    /// Issues a random 32-byte challenge and stores it in Redis with 5min TTL.
    /// Client will embed the challenge hash in the next attestation/assertion.
    func challenge(_ req: Request) async throws -> ChallengeResponse {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }

        let challenge  = Data(bytes).base64EncodedString()
        let challengeID = UUID().uuidString

        // SETEX, not SET-then-EXPIRE: two round trips leave the key immortal if
        // the connection drops between them. This endpoint is unauthenticated,
        // so that failure mode is an attacker-drivable Redis leak.
        try await req.redis.setex(
            RedisKey("attest:challenge:\(challengeID)"),
            to: challenge,
            expirationInSeconds: 300
        ).get()

        return ChallengeResponse(challengeID: challengeID, challenge: challenge)
    }

    /// Full attestation: client did `DCAppAttestService.attestKey(...)` for the
    /// first time on this install. We verify with Apple, store the public key
    /// keyed by keyID, then issue a JWT.
    func verify(_ req: Request) async throws -> TokenResponse {
        let body = try req.content.decode(AttestRequest.self)
        let challenge = try await consumeChallenge(body.challengeID, on: req)

        let publicKey = try await verifyAppleAttestation(
            attestation: body.attestation,
            keyID: body.keyID,
            challenge: challenge,
            on: req
        )

        // Store (keyID → publicKey, counter=0). Lives forever unless we revoke.
        try await req.redis.hmset([
            "publicKey": publicKey.base64EncodedString(),
            "counter":   "0",
            "createdAt": "\(Int(Date().timeIntervalSince1970))"
        ], in: RedisKey("attest:key:\(body.keyID)")).get()

        recordFraudRisk(attestation: body.attestation, keyID: body.keyID, on: req)

        return try mintToken(keyID: body.keyID, platform: "ios", on: req)
    }

    /// Exchanges the attestation's receipt with Apple for the device's risk
    /// metric, and stores it beside the key.
    ///
    /// Detached on purpose: this is a round-trip to Apple, and attestation must
    /// not block on it — a slow or unreachable Apple server would otherwise
    /// stall a user's first launch. Uses `application.client` rather than
    /// `req.client` because the work outlives the request. Every failure is
    /// logged and swallowed; the metric is a signal, not a gate.
    private func recordFraudRisk(attestation: String, keyID: String, on req: Request) {
        guard let deviceCheck = req.application.deviceCheck else { return }
        guard let attestationData = Data(base64Encoded: attestation),
              let receipt = AppAttestVerifier.receipt(fromAttestation: attestationData) else {
            req.logger.debug("attestation carried no receipt — skipping fraud-risk lookup")
            return
        }
        // The redemption host follows the AAGUID this attestation actually
        // carried. The attestation is already verified by this point, so an
        // unreadable environment here means a blob shape we do not expect.
        guard let environment = AppAttestVerifier.environment(fromAttestation: attestationData) else {
            req.logger.debug("could not read attestation environment — skipping fraud-risk lookup")
            return
        }

        let app = req.application
        let logger = req.logger
        Task.detached {
            do {
                guard let result = try await deviceCheck.fetchReceipt(
                    receipt, environment: environment, on: app.client, logger: logger
                ) else { return }   // 304: nothing new to store

                var fields: [String: String] = [
                    "receipt": result.raw.base64EncodedString(),
                    "receiptFetchedAt": "\(Int(Date().timeIntervalSince1970))"
                ]
                if let metric = result.parsed.riskMetric { fields["riskMetric"] = "\(metric)" }
                if let notBefore = result.parsed.notBefore {
                    fields["receiptNotBefore"] = "\(Int(notBefore.timeIntervalSince1970))"
                }
                if let expires = result.parsed.expirationTime {
                    fields["receiptExpiresAt"] = "\(Int(expires.timeIntervalSince1970))"
                }
                try await app.redis.hmset(fields, in: RedisKey("attest:key:\(keyID)")).get()

                logger.info("App Attest risk metric for \(keyID.prefix(8))…: \(result.parsed.riskMetric.map(String.init) ?? "n/a") (\(result.parsed.receiptType))")
            } catch {
                logger.warning("fraud-risk lookup failed (non-fatal): \(error)")
            }
        }
    }

    /// Assertion-based refresh: client proves possession of the Secure Enclave
    /// key by signing a fresh challenge. Cheaper than re-attesting; rate-limited
    /// by challenge TTL + Apple's per-key assertion counter.
    func refresh(_ req: Request) async throws -> TokenResponse {
        let body = try req.content.decode(AssertRequest.self)
        let challenge = try await consumeChallenge(body.challengeID, on: req)

        guard let pkB64 = try await req.redis.hget("publicKey", from: RedisKey("attest:key:\(body.keyID)")).get().string,
              let publicKey = Data(base64Encoded: pkB64) else {
            throw Abort(.unauthorized, reason: "unknown keyID — re-attest")
        }

        let storedCounter = (try await req.redis.hget("counter", from: RedisKey("attest:key:\(body.keyID)")).get().string)
            .flatMap(UInt32.init) ?? 0

        let newCounter = try await verifyAppleAssertion(
            assertion: body.assertion,
            publicKey: publicKey,
            challenge: challenge,
            previousCounter: storedCounter,
            on: req
        )

        try await storeCounterMonotonically(newCounter, keyID: body.keyID, on: req)

        return try mintToken(keyID: body.keyID, platform: "ios", on: req)
    }

    // MARK: - Helpers

    /// Advances the stored assertion counter, never backwards.
    ///
    /// The counter is the replay guard: Apple increments it inside the Secure
    /// Enclave on every assertion, so a replayed assertion carries a counter we
    /// have already seen. Storing it with a plain HSET made that guard racy —
    /// two concurrent refreshes both read N, verify N+1 and N+2, and whichever
    /// HSET lands last wins, so the *lower* value can end up stored and the
    /// higher assertion becomes replayable. This compare-and-set keeps the
    /// stored value monotonic regardless of arrival order.
    private func storeCounterMonotonically(_ counter: UInt32, keyID: String, on req: Request) async throws {
        let script = """
        local current = redis.call('HGET', KEYS[1], 'counter')
        if current and tonumber(current) >= tonumber(ARGV[1]) then return 0 end
        redis.call('HSET', KEYS[1], 'counter', ARGV[1])
        return 1
        """
        _ = try await req.redis.send(command: "EVAL", with: [
            .init(from: script),
            .init(from: 1),
            .init(from: RedisKey("attest:key:\(keyID)")),
            .init(from: "\(counter)")
        ]).get()
    }

    private func consumeChallenge(_ id: String, on req: Request) async throws -> String {
        let key = RedisKey("attest:challenge:\(id)")
        // GETDEL, so read-and-consume is one atomic step. A GET followed by a
        // DELETE lets two requests racing on the same challengeID both read it
        // before either deletes — which is exactly the replay "single-use" is
        // supposed to prevent.
        let response = try await req.redis.send(
            command: "GETDEL", with: [.init(from: key)]
        ).get()
        guard let c = response.string else {
            throw Abort(.badRequest, reason: "challenge expired or unknown")
        }
        return c
    }

    private func mintToken(keyID: String, platform: String, on req: Request) throws -> TokenResponse {
        let ttl = 15 * 60
        let payload = SportsCalJWT(
            sub: .init(value: keyID),
            exp: .init(value: Date().addingTimeInterval(TimeInterval(ttl))),
            iat: .init(value: Date()),
            plt: platform
        )
        let token = try req.jwt.sign(payload)
        return TokenResponse(token: token, expiresIn: ttl)
    }
}

// MARK: - Application configuration

extension Application {
    private struct AppAttestVerifierKey: StorageKey { typealias Value = AppAttestVerifier }

    /// The configured App Attest verifier. Set once in `configure.swift`.
    /// Absent means attestation was never configured — every attest route then
    /// fails closed rather than guessing at an app ID.
    var appAttest: AppAttestVerifier? {
        get { storage[AppAttestVerifierKey.self] }
        set { storage[AppAttestVerifierKey.self] = newValue }
    }
}

extension Application {
    private struct DeviceCheckClientKey: StorageKey { typealias Value = DeviceCheckClient }

    /// Optional — only set when a DeviceCheck key is configured. Its absence
    /// disables fraud-risk metrics and nothing else.
    var deviceCheck: DeviceCheckClient? {
        get { storage[DeviceCheckClientKey.self] }
        set { storage[DeviceCheckClientKey.self] = newValue }
    }
}

extension Request {
    var appAttest: AppAttestVerifier {
        get throws {
            guard let verifier = application.appAttest else {
                logger.error("App Attest verifier is not configured — check APP_ATTEST_APP_ID")
                throw Abort(.serviceUnavailable, reason: "attestation not configured")
            }
            return verifier
        }
    }
}
// MARK: - Apple verification

/// Verifies a full App Attest attestation and returns the attested public key
/// (X9.63) to store against the keyID.
///
/// The crypto lives in `AppAttestVerifier`; this wrapper only bridges request
/// context and maps verification failures onto HTTP. Failures are logged with
/// the specific reason but reported to the client as a flat 401 — telling a
/// forger *which* check they failed is free oracle access.
private func verifyAppleAttestation(
    attestation: String,
    keyID: String,
    challenge: String,
    on req: Request
) async throws -> Data {
    guard let attestationData = Data(base64Encoded: attestation),
          let keyIDData = Data(base64Encoded: keyID) else {
        throw Abort(.badRequest, reason: "malformed attestation payload")
    }

    // Must match the client byte-for-byte (Attestation.swift, performFullAttestation):
    // SHA256(challenge-as-UTF8 || raw keyID bytes). The challenge is the one the
    // server issued and just consumed — never a value from the request body.
    let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8) + keyIDData))

    do {
        return try await req.appAttest.verifyAttestation(
            attestation: attestationData,
            keyID: keyIDData,
            clientDataHash: clientDataHash
        )
    } catch let error as AppAttestError {
        req.logger.warning("attestation rejected: \(error.description)")
        throw Abort(.unauthorized, reason: "attestation failed")
    } catch let error as CBORError {
        req.logger.warning("attestation rejected: \(error.description)")
        throw Abort(.badRequest, reason: "malformed attestation payload")
    }
}

/// Verifies an assertion and returns the new signature counter to persist.
private func verifyAppleAssertion(
    assertion: String,
    publicKey: Data,
    challenge: String,
    previousCounter: UInt32,
    on req: Request
) async throws -> UInt32 {
    guard let assertionData = Data(base64Encoded: assertion) else {
        throw Abort(.badRequest, reason: "malformed assertion payload")
    }

    // Assertions bind only the challenge — no keyID (Attestation.swift,
    // refreshViaAssertion).
    let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))

    do {
        return try await req.appAttest.verifyAssertion(
            assertion: assertionData,
            publicKey: publicKey,
            clientDataHash: clientDataHash,
            previousCounter: previousCounter
        )
    } catch let error as AppAttestError {
        req.logger.warning("assertion rejected: \(error.description)")
        // A counter that failed to advance means a replay, not a lost key —
        // don't send the client into a pointless re-attest loop for it.
        throw Abort(.unauthorized, reason: "assertion failed")
    } catch let error as CBORError {
        req.logger.warning("assertion rejected: \(error.description)")
        throw Abort(.badRequest, reason: "malformed assertion payload")
    }
}
