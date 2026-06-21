import Vapor
import Redis
@preconcurrency import RediStack
import Crypto

/// Fixed-window rate limit backed by Redis INCR + EXPIRE. Keys on the per-device
/// `X-Install-ID` when present, else the client IP (honoring X-Forwarded-For
/// since we sit behind Caddy). Fail-open on Redis errors — a Redis blip should
/// not take the API offline.
///
/// History / why it's shaped this way: identity used to key on the hashed
/// `X-API-Key`, but every install ships the SAME shared app key, so that
/// collapsed the entire user base into one bucket — the write limit of 20/60s
/// applied globally, and once that bucket lost its TTL the counter climbed
/// forever and silently 429'd every write (registration, live-activity) for
/// weeks. Two guards now prevent a recurrence: (1) per-device identity, and
/// (2) `EXPIRE … NX` on every hit so a counter can never get stuck without a TTL.
struct RateLimitMiddleware: AsyncMiddleware {
    let limit: Int
    let windowSeconds: Int
    let keyPrefix: String

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let identity = Self.identity(for: request)
        let bucket = "\(keyPrefix):\(identity)"
        let bucketKey = RedisKey(bucket)

        let count: Int
        do {
            count = try await request.redis.increment(bucketKey).get()
            // Arm the window on every hit, not just when count == 1: `EXPIRE … NX`
            // is a no-op when a TTL already exists, but it self-heals any key that
            // somehow lost its expiry — the failure mode that bricked all writes.
            // Requires Redis 7+ for the NX flag.
            _ = try? await request.redis.send(command: "EXPIRE", with: [
                bucket.convertedToRESPValue(),
                Int64(windowSeconds).convertedToRESPValue(),
                "NX".convertedToRESPValue()
            ]).get()
        } catch {
            request.logger.warning("Rate limit Redis error, failing open", metadata: ["error": "\(error)"])
            return try await next.respond(to: request)
        }

        if count > limit {
            // Throw rather than return a bare Response: a returned 429 never
            // reaches ErrorMiddleware, so it logs nothing — which is precisely how
            // the global-write-bucket regression went unnoticed. Throwing makes it
            // visible in logs AND records a counter so a future spike is alertable.
            await request.telemetry.warning("ratelimit.rejected", [
                "bucket": keyPrefix,
                "identity": identity,
                "count": "\(count)",
                "limit": "\(limit)",
            ])
            throw Abort(.tooManyRequests, headers: [
                "Retry-After": "\(windowSeconds)",
                "X-RateLimit-Limit": "\(limit)",
            ])
        }

        return try await next.respond(to: request)
    }

    /// Per-device first. `X-Install-ID` is a stable per-install identifier the
    /// client sends on every write endpoint; the shared `X-API-Key` is
    /// deliberately NOT used as identity (it's identical across all installs).
    /// Falls back to the forwarded client IP, then the socket peer.
    static func identity(for request: Request) -> String {
        if let install = request.headers.first(name: "X-Install-ID"), !install.isEmpty {
            return "id:\(install)"
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
