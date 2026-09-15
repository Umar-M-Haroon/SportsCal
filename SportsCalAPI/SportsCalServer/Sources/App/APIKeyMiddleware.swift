import Vapor
import Crypto

/// Constant-time byte compare of two strings. Returns false for mismatched
/// lengths without leaking timing. Inputs here are SHA256 hex digests (64 chars),
/// so length parity is expected on the happy path.
func constantTimeEquals(_ a: String, _ b: String) -> Bool {
    let aBytes = Array(a.utf8)
    let bBytes = Array(b.utf8)
    guard aBytes.count == bBytes.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<aBytes.count { diff |= aBytes[i] ^ bBytes[i] }
    return diff == 0
}

/// SHA256 hex digest of a string, lowercased — the on-the-wire form we compare
/// pre-shared keys against.
func sha256Hex(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}

/// Parses a comma-separated list of SHA256 hashes from an env var into a
/// normalized (lowercased, trimmed, non-empty) array. Supporting MULTIPLE valid
/// hashes is what makes key rotation non-breaking: during a rollout the server
/// accepts both the old key (baked into already-installed app binaries) and the
/// new key (shipped in the next release). Once the old build is retired, drop
/// the old hash from the list. Never fails open — an unset/blank var yields [].
func validHashes(from envName: String) -> [String] {
    (Environment.get(envName) ?? "")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { !$0.isEmpty }
}

/// Middleware that validates API key authentication on protected routes.
/// Reads the `X-API-Key` header, hashes it with SHA256, and compares (in
/// constant time) against each hash in `API_KEY_HASH` (comma-separated).
/// Fails closed if the env var is unset — there is NO development bypass.
struct APIKeyMiddleware: AsyncMiddleware {
    /// Emergency kill switch: `API_KEY_ENFORCEMENT=off` lets requests through
    /// with no key or a wrong key. Exists because 3.2 shipped with an empty key
    /// baked in (Xcode Cloud env vars unset) and 403'd on every call; turn it
    /// back on once 3.2.1 has replaced it. Anything else (including unset)
    /// enforces. Admin routes use `AdminKeyMiddleware` and are unaffected.
    static var enforcementDisabled: Bool {
        Environment.get("API_KEY_ENFORCEMENT")?.trimmingCharacters(in: .whitespaces).lowercased() == "off"
    }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        if Self.enforcementDisabled {
            return try await next.respond(to: request)
        }

        let expected = validHashes(from: "API_KEY_HASH")
        guard !expected.isEmpty,
              let providedKey = request.headers.first(name: "X-API-Key") else {
            throw Abort(.forbidden)
        }

        let providedHash = sha256Hex(providedKey)
        // Compare against every accepted hash without short-circuiting, so the
        // number of comparisons doesn't leak which/how-many keys are configured.
        var matched = false
        for hash in expected where constantTimeEquals(providedHash, hash) {
            matched = true
        }
        guard matched else {
            throw Abort(.forbidden)
        }

        return try await next.respond(to: request)
    }
}
