import Vapor
import Crypto

/// Middleware that gates admin endpoints behind a separate credential from the
/// app-facing X-API-Key. Reads `X-Admin-API-Key`, hashes with SHA256, and
/// compares against `ADMIN_API_KEY_HASH`. Fails closed if the env var is unset.
struct AdminKeyMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let expectedHash = Environment.get("ADMIN_API_KEY_HASH"),
              let providedKey = request.headers.first(name: "X-Admin-API-Key") else {
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
