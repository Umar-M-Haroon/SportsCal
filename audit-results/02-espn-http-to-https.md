# Issue 2: ESPN URLs from HTTP to HTTPS

**Severity:** CRITICAL | **Release Blocker:** YES | **Effort:** 5 min

## Problem

All ESPN API calls from the Vapor server use `http://` instead of `https://`. This exposes server-to-ESPN traffic to man-in-the-middle attacks, allowing data tampering. ESPN supports HTTPS on the same endpoints.

## Files to Change

| File | Action |
|------|--------|
| `SportsCalAPI/SportsCalServer/Sources/App/ESPNIntegration/ESPNNetworking.swift` | Replace 6 occurrences of `http://` with `https://` |

## Current Code (all 6 occurrences)

```
Line  18: let urlString = "http://site.api.espn.com/apis/site/v2/sports/"
Line  39: let urlString = "http://site.api.espn.com/apis/site/v2/sports"
Line  68: let urlString = "http://site.api.espn.com/apis/site/v2/sports"
Line  91: let urlString = "http://site.api.espn.com/apis/v2/sports"
Line 113: let urlString = "http://site.api.espn.com/apis/site/v2/sports"
Line 301: let urlString = "http://site.api.espn.com/apis/site/v2/sports/golf/pga/summary?event=\(eventId)"
```

## Fix

Global find-and-replace in `ESPNNetworking.swift`:

**Find:** `http://site.api.espn.com`
**Replace:** `https://site.api.espn.com`

This covers all 6 occurrences. No other changes needed.

## Verification

- Server builds: `cd SportsCalAPI/SportsCalServer && swift build`
- Run server and confirm ESPN data still loads (scores appear in admin dashboard or API response)
- Verify no `http://` ESPN URLs remain: search for `http://site.api.espn` in `ESPNNetworking.swift`
- Note: `https://sports.core.api.espn.com` URLs (F1 endpoints, ~line 204, 256) already use HTTPS -- no change needed there
