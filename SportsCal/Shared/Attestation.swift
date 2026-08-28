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

    private struct CachedJWT {
        let token: String
        let expiresAt: Date
    }

    /// Returns a JWT valid for at least 60s. Triggers attest/refresh on demand.
    /// All call sites should funnel through this — do not cache the token elsewhere.
    func getValidJWT() async throws -> String {
        if let cached = cachedJWT, cached.expiresAt.timeIntervalSinceNow > 60 {
            return cached.token
        }
        if let inFlight { return try await inFlight.value }

        let task = Task<String, Error> {
            defer { inFlight = nil }
            return try await refreshOrAttest()
        }
        inFlight = task
        return try await task.value
    }

    /// Wipes local state — call on sign-out, key invalidation errors, or when
    /// the server reports "unknown keyID".
    func reset() {
        cachedJWT = nil
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
        cachedJWT = CachedJWT(
            token: t.token,
            expiresAt: Date().addingTimeInterval(TimeInterval(t.expiresIn))
        )
        keychainWrite(account: jwtAccount, value: t.token)
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
}
#endif
