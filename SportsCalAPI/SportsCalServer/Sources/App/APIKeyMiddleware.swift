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

/// Middleware that validates API key authentication on protected routes.
/// Reads the `X-API-Key` header, hashes it with SHA256, and compares against
/// the `API_KEY_HASH` environment variable. Skipped in development mode.
struct APIKeyMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let expectedHash = Environment.get("API_KEY_HASH"),
              let providedKey = request.headers.first(name: "X-API-Key") else {
            throw Abort(.forbidden)
        }

        let providedHash = SHA256.hash(data: Data(providedKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        guard constantTimeEquals(providedHash, expectedHash) else {
            throw Abort(.forbidden)
        }

        return try await next.respond(to: request)
    }
}
