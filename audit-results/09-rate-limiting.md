# Issue 9: Add Rate Limiting Middleware

**Severity:** MEDIUM | **Release Blocker:** No | **Effort:** 1-2 hours

## Problem

No rate limiting exists on any API endpoint. A single client could hammer the server with unlimited requests, causing DoS or excessive Redis load.

## Files to Create/Change

| File | Action |
|------|--------|
| `SportsCalAPI/SportsCalServer/Sources/App/RateLimitMiddleware.swift` | Create new middleware |
| `SportsCalAPI/SportsCalServer/Sources/App/routes.swift` | Apply middleware to route groups |

## Fix

### Step 1: Create RateLimitMiddleware.swift

Create `SportsCalAPI/SportsCalServer/Sources/App/RateLimitMiddleware.swift`:

```swift
import Vapor

/// Simple in-memory rate limiter using sliding window per client IP.
struct RateLimitMiddleware: AsyncMiddleware {
    let maxRequests: Int
    let windowSeconds: Int

    init(maxRequests: Int = 60, windowSeconds: Int = 60) {
        self.maxRequests = maxRequests
        self.windowSeconds = windowSeconds
    }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let clientIP = request.peerAddress?.description ?? "unknown"
        let now = Date()
        let windowStart = now.addingTimeInterval(-Double(windowSeconds))

        // Use application storage for the rate limit tracker
        let tracker = request.application.storage[RateLimitStorageKey.self] ?? RateLimitTracker()
        request.application.storage[RateLimitStorageKey.self] = tracker

        let count = await tracker.recordAndCount(key: clientIP, now: now, windowStart: windowStart)

        if count > maxRequests {
            throw Abort(.tooManyRequests, reason: "Rate limit exceeded. Try again later.")
        }

        return try await next.respond(to: request)
    }
}

private struct RateLimitStorageKey: StorageKey {
    typealias Value = RateLimitTracker
}

/// Thread-safe in-memory request counter with automatic cleanup.
actor RateLimitTracker {
    private var requests: [String: [Date]] = [:]

    func recordAndCount(key: String, now: Date, windowStart: Date) -> Int {
        // Remove expired entries
        requests[key] = (requests[key] ?? []).filter { $0 > windowStart }
        // Record this request
        requests[key, default: []].append(now)
        return requests[key]?.count ?? 0
    }
}
```

### Step 2: Apply to route groups in routes.swift (lines 55-61)

Change:
```swift
let v2025 = app.grouped("v2025").grouped(APIKeyMiddleware())
```
To:
```swift
let v2025 = app.grouped("v2025").grouped(RateLimitMiddleware()).grouped(APIKeyMiddleware())
```

Change:
```swift
let legacy = app.grouped(APIKeyMiddleware())
```
To:
```swift
let legacy = app.grouped(RateLimitMiddleware()).grouped(APIKeyMiddleware())
```

RateLimitMiddleware runs first so rate-limited requests are rejected before API key validation (cheaper).

## Verification

- Server builds: `cd SportsCalAPI/SportsCalServer && swift build`
- Test with rapid requests: `for i in $(seq 1 70); do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/v2025/test-call -H "X-API-Key: YOUR_KEY"; done` -- should see 429 responses after 60 requests
- Normal app usage (a few requests per second) is unaffected
- Consider making limits configurable via environment variables for production tuning
