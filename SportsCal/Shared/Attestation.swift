//
//  Attestation.swift
//  SportsCal
//
//  Client-side App Attest + JWT flow.
//
//  Public surface is a single call: `Attestation.shared.getValidJWT()`.
//  NetworkHandler uses it to stamp every outbound request with a fresh
//  Bearer token. The actor serializes refreshes so a burst of parallel
//  requests during a token expiry triggers one refresh, not N.
//
//  Secure Enclave key lifecycle:
//    - First launch:   generateKey → attestKey → POST /attest/verify → JWT
//    - Subsequent:     read keyID from Keychain, POST /attest/refresh via
//                      assertion when JWT is within 60s of expiring
//    - Key lost:       (restored-from-backup etc.) Keychain entry survives
//                      but attestation calls fail — detect, wipe, redo
//
//  Simulator & dev builds skip attestation and ask the server for a dev
//  token instead. That route (POST /attest/dev) is only *registered* off
//  production — on prod it 404s, so a simulator build pointed at prod simply
//  gets no JWT and falls back to the shared API key.
//
//  Failing to obtain a token is never fatal: NetworkHandler treats the Bearer
//  header as best-effort while the server still accepts the shared API key
//  (see EitherAuthMiddleware server-side, and docs/app-attest-plan.md).
//

#if os(iOS)
import Foundation
import DeviceCheck
import CryptoKit
import os

actor Attestation {
    static let shared = Attestation()

    private let keychainService = "com.KomodoLLC.SportsCal.attest"
    private let keyIDAccount    = "appAttestKeyID"
    private let jwtAccount      = "sessionJWT"
    private let log = Logger(subsystem: "com.KomodoLLC.SportsCal", category: "Attestation")

    private var cachedJWT: CachedJWT?
    private var inFlight: Task<String, Error>?

    /// Earliest time we may attempt another attestation after a failure.
    /// Caching only successes meant a device that cannot attest — a simulator,
    /// an MDM-restricted device, or any device talking to a server without
    /// JWT_SIGNING_KEY — re-ran the whole flow on *every single API request*,
    /// minting a fresh Secure Enclave key each time and hammering Apple's
    /// rate-limited attest service.
    private var retryNoEarlierThan: Date?
    private var consecutiveFailures = 0

    /// Set when attestation cannot work on this device at all, as opposed to
    /// having merely failed once. No amount of retrying changes the answer, so
    /// we stop asking until `reset()` (or the next launch).
    private var attestationUnavailable = false

    /// The Keychain copy of the token is only useful if we actually read it
    /// back; loaded once, lazily, on the first request of the session.
    private var didLoadPersistedToken = false

    private static let minBackoff: TimeInterval = 30
    private static let maxBackoff: TimeInterval = 30 * 60

    private struct CachedJWT {
        let token: String
        let expiresAt: Date
    }

    /// Returns a JWT valid for at least 60s. Triggers attest/refresh on demand.
    /// All call sites should funnel through this — do not cache the token elsewhere.
    func getValidJWT() async throws -> String {
        if !didLoadPersistedToken {
            didLoadPersistedToken = true
            loadPersistedToken()
        }

        if let cached = cachedJWT, cached.expiresAt.timeIntervalSinceNow > 60 {
            return cached.token
        }
        if let inFlight { return try await inFlight.value }

        // Fail fast while backing off. NetworkHandler calls this on every
        // request and treats a throw as "send the shared API key instead", so
        // returning immediately here is the difference between a silent
        // fallback and a 15s timeout on each request.
        if attestationUnavailable { throw AttestError.unavailable }
        if let retryAt = retryNoEarlierThan, retryAt.timeIntervalSinceNow > 0 {
            throw AttestError.backingOff
        }

        let task = Task<String, Error> {
            defer { inFlight = nil }
            do {
                let token = try await refreshOrAttest()
                consecutiveFailures = 0
                retryNoEarlierThan = nil
                return token
            } catch {
                noteFailure(error)
                throw error
            }
        }
        inFlight = task
        return try await task.value
    }

    /// Records a failed attempt and arms the backoff window.
    ///
    /// A 404 from `/attest/dev` is the documented shape of "this build cannot
    /// attest and the server has no dev route" — a simulator or unsupported
    /// device pointed at production. That is permanent for the session, not
    /// something to retry with backoff.
    private func noteFailure(_ error: Error) {
        if case AttestError.server(404) = error {
            attestationUnavailable = true
            log.info("attestation unavailable on this device/server — staying on the shared API key")
            return
        }
        consecutiveFailures += 1
        let delay = min(
            Self.maxBackoff,
            Self.minBackoff * pow(2, Double(consecutiveFailures - 1))
        )
        retryNoEarlierThan = Date().addingTimeInterval(delay)
        log.warning("attestation failed (\(self.consecutiveFailures, privacy: .public)x) — next attempt in \(Int(delay), privacy: .public)s: \(error.localizedDescription, privacy: .public)")
    }

    /// Wipes local state — call on sign-out, key invalidation errors, or when
    /// the server reports "unknown keyID".
    func reset() {
        cachedJWT = nil
        // Clear the backoff too — a reset is a deliberate "try again from
        // scratch", so it should not sit out a window armed by the old state.
        retryNoEarlierThan = nil
        consecutiveFailures = 0
        attestationUnavailable = false
        keychainDelete(account: keyIDAccount)
        keychainDelete(account: jwtAccount)
    }

    // MARK: - Core flow

    private func refreshOrAttest() async throws -> String {
        #if targetEnvironment(simulator)
        return try await fetchDevToken()
        #else
        guard DCAppAttestService.shared.isSupported else {
            // Very old device, or an MDM profile that blocks App Attest. Try the
            // dev route — which succeeds on a dev server and 404s on prod. The
            // throw is expected there and leaves the caller on the shared API
            // key rather than breaking the app for this small tail of devices.
            return try await fetchDevToken()
        }

        if let keyID = keychainRead(account: keyIDAccount) {
            do {
                let token = try await refreshViaAssertion(keyID: keyID)
                cacheToken(token)
                return token.token
            } catch AttestError.unknownKey {
                log.warning("server rejected keyID — re-attesting")
                keychainDelete(account: keyIDAccount)
                // fall through to full attestation
            }
        }

        let token = try await performFullAttestation()
        cacheToken(token)
        return token.token
        #endif
    }

    private func performFullAttestation() async throws -> TokenResponse {
        let service = DCAppAttestService.shared
        let challenge = try await requestChallenge()

        let keyID = try await service.generateKey()
        // generateKey() returns base64; the server recomputes this exact hash
        // (challenge bytes || raw keyID bytes) when verifying, so the two must
        // not drift.
        guard let keyIDData = Data(base64Encoded: keyID) else { throw AttestError.transport }
        let clientHash = Data(SHA256.hash(data: Data(challenge.challenge.utf8) + keyIDData))
        let attestation = try await service.attestKey(keyID, clientDataHash: clientHash)

        let body = AttestVerifyBody(
            keyID: keyID,
            attestation: attestation.base64EncodedString(),
            challengeID: challenge.challengeID
        )
        let token: TokenResponse = try await postJSON(path: "/attest/verify", body: body)

        keychainWrite(account: keyIDAccount, value: keyID)
        return token
    }

    private func refreshViaAssertion(keyID: String) async throws -> TokenResponse {
        let challenge = try await requestChallenge()
        let clientHash = Data(SHA256.hash(data: Data(challenge.challenge.utf8)))
        let assertion: Data
        do {
            assertion = try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientHash)
        } catch {
            // DCError domain: invalidKey → server forgot us, or Secure Enclave
            // lost the key (backup restore). Signal re-attest.
            throw AttestError.unknownKey
        }
        let body = AssertRefreshBody(
            keyID: keyID,
            assertion: assertion.base64EncodedString(),
            challengeID: challenge.challengeID
        )
        return try await postJSON(path: "/attest/refresh", body: body)
    }

    private func cacheToken(_ t: TokenResponse) {
        let expiresAt = Date().addingTimeInterval(TimeInterval(t.expiresIn))
        cachedJWT = CachedJWT(token: t.token, expiresAt: expiresAt)
        // Store the expiry with the token. A bare token would be unusable on the
        // next launch — we could not tell whether it was still valid without
        // parsing the JWT, so the persisted copy would have to be ignored.
        keychainWrite(account: jwtAccount, value: "\(t.token)|\(expiresAt.timeIntervalSince1970)")
    }

    /// Restores a still-valid token from the Keychain so a cold launch does not
    /// pay a challenge + assertion round trip for a token we already hold.
    private func loadPersistedToken() {
        guard let stored = keychainRead(account: jwtAccount) else { return }
        let parts = stored.split(separator: "|", maxSplits: 1)
        guard parts.count == 2,
              let epoch = TimeInterval(parts[1]) else {
            // Pre-3.2 format (token only, no expiry) — unusable, so drop it.
            keychainDelete(account: jwtAccount)
            return
        }
        let expiresAt = Date(timeIntervalSince1970: epoch)
        guard expiresAt.timeIntervalSinceNow > 60 else { return }
        cachedJWT = CachedJWT(token: String(parts[0]), expiresAt: expiresAt)
    }

    // MARK: - Server calls

    private func requestChallenge() async throws -> ChallengeBody {
        try await postJSON(path: "/attest/challenge", body: EmptyBody())
    }

    private func postJSON<B: Encodable, R: Decodable>(path: String, body: B) async throws -> R {
        // NOTE: base URL selection lives in NetworkHandler. We reach through it
        // rather than duplicating the Bonjour/Tailscale/prod switching logic.
        // Attest routes sit at the server root — NOT under the /v2025 prefix that
        // baseURL() returns — because a client calls them before it has any
        // versioned session at all.
        guard let url = URL(string: NetworkHandler.rootURL().http + path) else {
            throw AttestError.transport
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The attest routes are rate-limited but otherwise open (they must be —
        // they are how a client earns a token). /attest/dev additionally sits
        // behind the shared key, so send it on all of them.
        req.setValue(Constants.apiKey, forHTTPHeaderField: "X-API-Key")
        // Rate-limit identity. Without this the server falls back to `ip:<addr>`,
        // which (a) shares one 30/min bucket across everyone behind the same NAT
        // — carrier-grade NAT, office or stadium Wi-Fi — and (b) skips the far
        // more generous per-IP ceiling entirely, since that branch only applies
        // to `id:` identities. A dozen users launching on one network would 429
        // each other out of attesting.
        req.setValue(InstallID.current(), forHTTPHeaderField: "X-Install-ID")
        req.timeoutInterval = 15
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AttestError.transport }
        if http.statusCode == 401 { throw AttestError.unknownKey }
        guard (200..<300).contains(http.statusCode) else { throw AttestError.server(http.statusCode) }
        return try JSONDecoder().decode(R.self, from: data)
    }

    private func fetchDevToken() async throws -> String {
        // Non-production only — the route is not registered on the prod server,
        // so this throws .server(404) there. Keeps the simulator and unit tests
        // working without fake-attesting.
        let resp: TokenResponse = try await postJSON(path: "/attest/dev", body: EmptyBody())
        cacheToken(resp)
        return resp.token
    }

    // MARK: - Keychain

    private func keychainWrite(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func keychainRead(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func keychainDelete(account: String) {
        SecItemDelete([
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}

// MARK: - Wire types

private struct EmptyBody: Encodable {}
private struct ChallengeBody: Decodable { let challengeID: String; let challenge: String }
private struct TokenResponse: Decodable { let token: String; let expiresIn: Int }
private struct AttestVerifyBody: Encodable { let keyID: String; let attestation: String; let challengeID: String }
private struct AssertRefreshBody: Encodable { let keyID: String; let assertion: String; let challengeID: String }

enum AttestError: Error {
    case transport
    case server(Int)
    case unknownKey
    /// This device/server combination cannot produce a token at all. Callers
    /// should fall back to the shared API key and not retry.
    case unavailable
    /// A recent attempt failed and the backoff window has not elapsed.
    case backingOff
}
#endif
