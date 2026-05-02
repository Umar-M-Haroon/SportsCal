import Vapor
import Redis
import Crypto

/// Sliding-window rate limit backed by Redis INCR+EXPIRE. Keys on the hashed
/// X-API-Key when present, else the client IP (honoring X-Forwarded-For since
/// we sit behind Caddy). Fail-open on Redis errors — a Redis blip should not
/// take the API offline.
struct RateLimitMiddleware: AsyncMiddleware {
    let limit: Int
    let windowSeconds: Int
    let keyPrefix: String

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let identity = Self.identity(for: request)
        let bucket = RedisKey("\(keyPrefix):\(identity)")

        let count: Int
        do {
            count = try await request.redis.increment(bucket).get()
            if count == 1 {
                _ = try? await request.redis.expire(bucket, after: .seconds(Int64(windowSeconds))).get()
            }
        } catch {
            request.logger.warning("Rate limit Redis error, failing open", metadata: ["error": "\(error)"])
            return try await next.respond(to: request)
        }

        if count > limit {
            let response = Response(status: .tooManyRequests)
            response.headers.add(name: "Retry-After", value: "\(windowSeconds)")
            response.headers.add(name: "X-RateLimit-Limit", value: "\(limit)")
            return response
        }

        return try await next.respond(to: request)
    }

    private static func identity(for request: Request) -> String {
        if let key = request.headers.first(name: "X-API-Key") {
            let hash = SHA256.hash(data: Data(key.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            return "k:\(hash.prefix(16))"
        }
        if let forwarded = request.headers.first(name: "X-Forwarded-For") {
            let first = forwarded.split(separator: ",").first.map {
                $0.trimmingCharacters(in: .whitespaces)
            } ?? forwarded
            return "ip:\(first)"
        }
        return "ip:\(request.remoteAddress?.ipAddress ?? "unknown")"
    }
}
