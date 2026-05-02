# ``App``

Vapor 4 backend that aggregates ESPN + TheSportsDB data, caches in Redis, and pushes Live Activity updates over APNS.

## Overview

The server runs three things in parallel:

1. **Scheduled jobs** that poll upstream APIs and write to Redis (`ESPNFetchJob`, `ESPNSoccerJob`, `ESPNTennisJob`, `ESPNTeamFetchJob`, `ESPNCalendarJob`, `ScheduleUpdateJob`, `StandingsSnapshotJob`, `F1EnrichmentJob`).
2. **REST + WebSocket endpoints** (`/v2025/*`) that serve cached data to the iOS and watchOS apps.
3. **APNS pushers** (`APNSJob`, plus the push-to-start path inside `ESPNFetchJob`) that drive iOS Live Activities for live games the user is following.

The admin dashboard ships as static files under `Public/admin/` and reaches the same backend over a separate `/api/admin/*` namespace, gated by `APIKeyMiddleware`.

The `App` module is consumed by the `Run` executable, which only contains a `main.swift` shim that calls ``configure(_:)``.

## Topics

### Push & Live Activity

- <doc:ServerOverview>
- <doc:PushArchitecture>
- <doc:PushTestingGuide>
- <doc:LiveActivityE2EPlaybook>

### Live Activity types

- ``ContentState``
- ``LiveSportAttributes``

### Bootstrap

- ``configure(_:)``

### Logging

- ``PrettyLogHandler``
