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
///
/// Bypass hardening: because identity is a CLIENT-SUPPLIED header, an attacker
/// can send a fresh random `X-Install-ID` per request and land every request in
/// its own bucket, defeating the per-install limit entirely. To close that
/// without reintroducing the global-bucket regression, we ALSO enforce a
/// separate, much-more-generous per-IP ceiling (`ipCeiling`). Legit users keyed
/// to one install ID never approach it; users behind carrier-grade NAT share
/// only the generous ceiling; a single host cycling install IDs hits it fast.
struct RateLimitMiddleware: AsyncMiddleware {
    let limit: Int
    let windowSeconds: Int
    let keyPrefix: String
    /// Optional per-IP request ceiling per window, enforced IN ADDITION to the
    /// per-install `limit`. Set well above `limit` (it's an abuse backstop, not
    /// the primary limit) so shared-NAT users aren't caught. Nil disables it.
    let ipCeiling: Int?

    init(limit: Int, windowSeconds: Int, keyPrefix: String, ipCeiling: Int? = nil) {
        self.limit = limit
        self.windowSeconds = windowSeconds
        self.keyPrefix = keyPrefix
        self.ipCeiling = ipCeiling
    }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let identity = Self.identity(for: request)

        // Primary per-identity bucket (per-install when an X-Install-ID is sent).
        if let rejection = try await checkBucket(
            "\(keyPrefix):\(identity)", limit: limit, identity: identity, request: request
        ) { throw rejection }

        // Per-IP ceiling. Only meaningful when identity is install-based; when it
        // already IS the IP the primary bucket covers it, so skip the double count.
        if let ipCeiling, identity.hasPrefix("id:") {
            let ip = Self.clientIP(for: request)
            if let rejection = try await checkBucket(
                "\(keyPrefix):ipcap:\(ip)", limit: ipCeiling, identity: "ip:\(ip)", request: request
            ) { throw rejection }
        }

        return try await next.respond(to: request)
    }

    /// Increments `bucket`, arms its TTL, and returns an Abort to throw if the
    /// count exceeds `limit`. Returns nil when under the limit. Fails OPEN (nil)
    /// on Redis errors — a Redis blip should not take the API offline.
    private func checkBucket(_ bucket: String, limit: Int, identity: String, request: Request) async throws -> Abort? {
        let count: Int
        do {
            count = try await request.redis.increment(RedisKey(bucket)).get()
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
            return nil
        }

        guard count > limit else { return nil }
        // Throw (via caller) rather than return a bare Response: a returned 429
        // never reaches ErrorMiddleware, so it logs nothing — which is precisely
        // how the global-write-bucket regression went unnoticed. Recording a
        // counter here makes a future spike alertable.
        await request.telemetry.warning("ratelimit.rejected", [
            "bucket": keyPrefix,
            "identity": identity,
            "count": "\(count)",
            "limit": "\(limit)",
        ])
        return Abort(.tooManyRequests, headers: [
            "Retry-After": "\(windowSeconds)",
            "X-RateLimit-Limit": "\(limit)",
        ])
    }

    /// Per-device first. `X-Install-ID` is a stable per-install identifier the
    /// client sends on every write endpoint; the shared `X-API-Key` is
    /// deliberately NOT used as identity (it's identical across all installs).
    /// Falls back to the forwarded client IP, then the socket peer.
    static func identity(for request: Request) -> String {
        if let install = request.headers.first(name: "X-Install-ID"), !install.isEmpty {
            return "id:\(install)"
        }
        return "ip:\(clientIP(for: request))"
    }

    /// Best-effort client IP. Trusts `X-Forwarded-For`'s first hop because the
    /// app sits behind Caddy, which overwrites it — the origin must NOT be
    /// directly reachable, or XFF becomes spoofable and the ceiling evadable.
    static func clientIP(for request: Request) -> String {
        if let forwarded = request.headers.first(name: "X-Forwarded-For") {
            let first = forwarded.split(separator: ",").first.map {
                $0.trimmingCharacters(in: .whitespaces)
            } ?? forwarded
            if !first.isEmpty { return first }
        }
        return request.remoteAddress?.ipAddress ?? "unknown"
    }
}
