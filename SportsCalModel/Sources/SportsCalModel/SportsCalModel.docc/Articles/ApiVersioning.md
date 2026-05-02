# API Versioning

How the iOS app and the Vapor server stay in sync as the wire format evolves.

## Overview

The API uses year-based URL path versioning. The current version is **v2025**.

| Version | Path | Status |
|---------|------|--------|
| 2025 | `/v2025/*` | Current |
| Legacy | `/*` | Deprecated (backward compatible) |

All v2025 responses include two headers:

- `X-API-Version: 2025` — the version that produced the response.
- `X-Min-App-Version: 1.5.0` — the lowest iOS app version still supported.

The iOS app reads `X-Min-App-Version` after every response and surfaces an "update required" prompt when its bundle version falls below the floor.

## v2025 response shape

The v2025 endpoints wrap the model types in versioned envelopes so that future changes (new envelope fields, deprecation flags) don't require breaking the inner shape:

- ``V2LiveScoreResponse`` — wraps ``LiveScore`` for `/v2025/schedules`, `/v2025/live`, `/v2025/all-live-games`.
- ``V2TeamsResponse`` — wraps `[Team]` and `[Leagues: TeamResponse]` for `/v2025/teams` and `/v2025/teams-by-league`.
- ``V2ScheduleResponse`` — wraps a single sport's ``LiveEvent`` for `/v2025/sport/:sport`.
- ``V2NoDataResponse`` — for endpoints that only return metadata (registration, ack endpoints).

## Endpoint inventory

![API endpoints](api-endpoints)

## What v2025 trimmed from the wire

The v2025 cutover removed fields the clients no longer use, shrinking responses by ~20%:

**Removed (not sent):**
- `strPlayer`, `idPlayer` — no player-level UI on the client.
- `intEventScore`, `intEventScoreTotal` — legacy ESPN fields.
- `updated`, `strEventTime`, `dateEvent` — redundant timestamps; `isoDate` carries the canonical value.

**Computed client-side (omitted on the wire):**
- `strSport` — derived from `idLeague` via ``Leagues``.
- `strLeague` — derived from `idLeague` via ``Leagues``.

**Kept:**
- `strHomeTeamBadge`, `strAwayTeamBadge` — kept on the wire because computing from `idHomeTeam` / `idAwayTeam` requires a separate teams cache lookup.

## Adding a v2026

When the wire format breaks, mint `/v2026/*` endpoints alongside `/v2025/*`. The legacy path stays mounted only for the months it takes the App Store install base to roll forward past `X-Min-App-Version`.

## See Also

- <doc:DataModel>
- ``Leagues``
