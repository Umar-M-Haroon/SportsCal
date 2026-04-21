# Issue 5: Remove ESPN Branding from Admin Dashboard

**Severity:** HIGH | **Release Blocker:** No | **Effort:** 10 min

## Problem

The admin dashboard source code explicitly references "ESPN" in UI text, log messages, and endpoint names. Even though admin routes are dev-only, these references exist in version-controlled source code and could create licensing/attribution issues if discovered.

## Files to Change

| File | Action |
|------|--------|
| `SportsCalAdmin/src/components/LiveGames.ts` | Remove 3 ESPN references in UI/logs |
| `SportsCalAdmin/src/components/HealthMonitor.ts` | Job name references (optional, internal) |
| `SportsCalAPI/SportsCalServer/Sources/App/Controllers/AdminController.swift` | Rename endpoint (optional) |

## Current Code

**LiveGames.ts:**
```
Line  80: logger.log('Fetching live games from /api/admin/live-espn...', 'info')
Line  87: const fetchPromise = fetch('/api/admin/live-espn').then(async (response) => {
Line 176: logger.log(`Displaying ${liveGamesCount} live games (${totalGamesCount} total from ESPN)`, ...)
Line 212: <h3 ...>ESPN Scoreboard Summary</h3>
```

## Fix

### Step 1: LiveGames.ts changes

**Line 80:** Change to:
```typescript
logger.log('Fetching live games...', 'info')
```

**Line 176:** Change to:
```typescript
logger.log(`Displaying ${liveGamesCount} live games (${totalGamesCount} total)`, ...)
```

**Line 212:** Change to:
```html
<h3 ...>Live Scoreboard Summary</h3>
```

### Step 2 (Optional): Rename server endpoint

If you want to also rename the endpoint itself:

1. In `AdminController.swift`, find the route registration for `live-espn` and rename to `live-scores`
2. In `LiveGames.ts` line 87, update the fetch URL from `/api/admin/live-espn` to `/api/admin/live-scores`

### Step 3 (Optional): HealthMonitor.ts

Line 135 references job names like `ESPNTeamFetchJob` and `ESPNFetchJob` -- these are internal server job names and renaming them would require server-side changes too. Lower priority since they're implementation details visible only to you.

## Verification

- `cd SportsCalAdmin && npm run build` succeeds
- Search for "ESPN" in admin dashboard source: `grep -rn "ESPN" SportsCalAdmin/src/` -- only internal job name references should remain
- Admin dashboard still loads and displays live games correctly
