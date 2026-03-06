import Vapor
import Crypto

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

        guard providedHash == expectedHash else {
            throw Abort(.forbidden)
        }

        return try await next.respond(to: request)
    }
}
