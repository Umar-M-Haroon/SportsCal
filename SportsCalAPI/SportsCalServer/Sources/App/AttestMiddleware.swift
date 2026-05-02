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
    func boot(routes: RoutesBuilder) throws {
        let grp = routes.grouped("attest")
        grp.post("challenge", use: challenge)
        grp.post("verify",    use: verify)
        grp.post("refresh",   use: refresh)
    }

    /// Issues a random 32-byte challenge and stores it in Redis with 5min TTL.
    /// Client will embed the challenge hash in the next attestation/assertion.
    func challenge(_ req: Request) async throws -> ChallengeResponse {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }

        let challenge  = Data(bytes).base64EncodedString()
        let challengeID = UUID().uuidString

        try await req.redis.set(
            RedisKey("attest:challenge:\(challengeID)"),
            to: challenge,
            onCondition: .none
        ).get()
        try await req.redis.expire(RedisKey("attest:challenge:\(challengeID)"), after: .seconds(300)).get()

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

        return try mintToken(keyID: body.keyID, platform: "ios", on: req)
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

        try await req.redis.hset("counter", to: "\(newCounter)", in: RedisKey("attest:key:\(body.keyID)")).get()

        return try mintToken(keyID: body.keyID, platform: "ios", on: req)
    }

    // MARK: - Helpers

    private func consumeChallenge(_ id: String, on req: Request) async throws -> String {
        let key = RedisKey("attest:challenge:\(id)")
        guard let c = try await req.redis.get(key).get().string else {
            throw Abort(.badRequest, reason: "challenge expired or unknown")
        }
        // Single-use: delete before handing back.
        try await req.redis.delete(key).get()
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

// MARK: - Apple verification (STUBS — replace before shipping)

/// Verifies an App Attest attestation blob per Apple's spec.
///
/// TODO: implement. Required steps (see
/// https://developer.apple.com/documentation/devicecheck/validating_apps_that_connect_to_your_server):
///   1. Base64-decode attestation → CBOR-decode into `{ fmt, attStmt, authData }`
///   2. attStmt contains `x5c` (cert chain) + `receipt`. Verify chain terminates
///      at Apple App Attestation Root CA (pin the PEM in /Resources).
///   3. Compute clientDataHash = SHA256(challenge.utf8 + keyID-decoded).
///   4. Compute nonce = SHA256(authData || clientDataHash). Assert it matches
///      the nonce extension in the leaf cert (OID 1.2.840.113635.100.8.2).
///   5. Extract public key from authData. Assert SHA256(pubKey) == keyID bytes.
///   6. Parse authData RP ID: must equal SHA256("<TEAM_ID>.com.KomodoLLC.SportsCal").
///   7. Assert authData counter == 0, aaguid == "appattest\0\0\0\0\0\0\0" (prod)
///      or "appattestdevelop" (dev — gate by app.environment).
///
/// Until this is real, the function refuses everything. That's deliberate —
/// failing closed is the only safe default for an unverified attestation.
private func verifyAppleAttestation(
    attestation: String,
    keyID: String,
    challenge: String,
    on req: Request
) async throws -> Data {
    req.logger.error("⚠️ verifyAppleAttestation is a stub — refusing. See file-level TODO.")
    throw Abort(.notImplemented, reason: "attestation verification not yet implemented")
}

/// Verifies a DCAppAttestService assertion.
///
/// TODO: implement.
///   1. Base64-decode assertion → CBOR `{ signature, authenticatorData }`.
///   2. clientDataHash = SHA256(challenge.utf8).
///   3. nonce = SHA256(authenticatorData || clientDataHash).
///   4. Verify ECDSA-P256 signature(nonce) using stored public key.
///   5. Read `counter` (bytes 33..<37, big-endian UInt32) from authenticatorData.
///      Assert counter > previousCounter. Return new counter.
///   6. Assert authenticatorData RP ID hash matches our app.
private func verifyAppleAssertion(
    assertion: String,
    publicKey: Data,
    challenge: String,
    previousCounter: UInt32,
    on req: Request
) async throws -> UInt32 {
    req.logger.error("⚠️ verifyAppleAssertion is a stub — refusing. See file-level TODO.")
    throw Abort(.notImplemented, reason: "assertion verification not yet implemented")
}
