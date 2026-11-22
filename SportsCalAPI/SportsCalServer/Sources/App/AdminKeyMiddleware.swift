import Vapor
import Crypto

/// Middleware that gates admin endpoints behind a separate credential from the
/// app-facing X-API-Key. Reads `X-Admin-API-Key`, hashes with SHA256, and
/// compares (constant time) against each hash in `ADMIN_API_KEY_HASH`
/// (comma-separated, to allow non-breaking rotation). Fails closed if unset.
struct AdminKeyMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let expected = validHashes(from: "ADMIN_API_KEY_HASH")
        guard !expected.isEmpty,
              let providedKey = request.headers.first(name: "X-Admin-API-Key") else {
            throw Abort(.forbidden)
        }

        let providedHash = sha256Hex(providedKey)
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
