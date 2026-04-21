# Issue 8: Reduce Standings Snapshot TTL

**Severity:** MEDIUM | **Release Blocker:** No | **Effort:** 5 min

## Problem

`StandingsSnapshotJob.swift` stores ESPN-sourced standings snapshots in Redis with a 90-day TTL (line 52). This is excessive for data sourced from ESPN without a formal license. The `/standings/:leagueID/history` endpoint also queries up to 90 days of history.

## Files to Change

| File | Lines | Action |
|------|-------|--------|
| `SportsCalAPI/SportsCalServer/Sources/App/ScheduleJobs/StandingsSnapshotJob.swift` | 15, 52 | Change 90-day TTL to 30 days |
| `SportsCalAPI/SportsCalServer/Sources/App/routes.swift` | 450 | Change history query cap from 90 to 30 |

## Current Code

**StandingsSnapshotJob.swift line 15:**
```swift
/// Stores in Redis as "Standings-{leagueID}-{YYYY-MM-DD}" with 90-day TTL.
```

**StandingsSnapshotJob.swift line 52:**
```swift
try await context.application.redis.setex(key, to: json, expirationInSeconds: 90 * 24 * 60 * 60).get()
```

**routes.swift line 450:**
```swift
for dayOffset in 0..<min(days, 90) {
```

## Fix

### Step 1: StandingsSnapshotJob.swift line 15

Change comment:
```swift
/// Stores in Redis as "Standings-{leagueID}-{YYYY-MM-DD}" with 30-day TTL.
```

### Step 2: StandingsSnapshotJob.swift line 52

Change:
```swift
try await context.application.redis.setex(key, to: json, expirationInSeconds: 30 * 24 * 60 * 60).get()
```

### Step 3: routes.swift line 450

Change:
```swift
for dayOffset in 0..<min(days, 30) {
```

## Verification

- Server builds: `cd SportsCalAPI/SportsCalServer && swift build`
- Standings history endpoint still returns data for recent days
- New snapshots get 30-day TTL (verify with `redis-cli TTL "Standings-4387-2026-04-12"` -- should be ~2592000 seconds)
