# Multi-Source Live-Score Reconcile Engine — Spec

## Context

Today live scores are driven almost entirely by ESPN's undocumented API, polled once
a minute (`ESPNFetchJob`), with TheSportsDB v2 supplying the schedule backbone and a
legacy `/live` fallback. The merge that combines them (`ESPNFetchJob.mergeESPNIntoSchedule`
→ `mergeSportEvents`) is **last-writer-wins**: ESPN dynamic fields unconditionally clobber
schedule fields. That has three structural limits:

1. **ESPN is a single unofficial point of failure** — a 429 trips a global circuit breaker
   (`ESPNNetworking.performGet`) that halts *all* ESPN traffic, and there is no second
   source to fail over to or cross-check against.
2. **No accuracy arbitration** — when sources disagree, or a source glitches a value
   downward and back up, nothing prevents the bad value from being published. On the Live
   Activity path this surfaces as **phantom "Goal!" alerts** (`APNSJob.scoreAlert` fires on
   any score increase vs the last pushed state).
3. **Flat 60s cadence** regardless of game state or per-source refresh floors.

This engine replaces the last-writer merge with **per-field selection by
`priority × freshness × monotonicity`**, adds **provenance** for tuning/telemetry, and lets
us layer in richer free official sources (MLB StatsAPI, NHL api-web) behind a single seam.

### Source characteristics (researched June 2026)

| Source | Refresh floor | Rate ceiling | Key | Role |
|---|---|---|---|---|
| MLB StatsAPI (`statsapi.mlb.com`) | ~10s (pitch-level, `metaData.wait=10`; `diffPatch` for cheap incrementals) | none documented (non-commercial policy) | none | primary live for MLB |
| NHL api-web (`api-web.nhle.com`) | ~20–30s (event-level; underlying ~1×/min; no diff, full re-poll) | undocumented, **429s** → needs backoff | none | primary live for NHL |
| ESPN (`site.api.espn.com`) | ~30–60s | undocumented, ~"few hundred/day", aggressive 429 | none | broad coverage; only practical NBA/NFL/soccer live source |
| TheSportsDB v2 | **120s (hard)** | 100/min ($9 tier) | yes (`X-API-KEY`) | low-res **cross-check / failover only** — never a fast path; `strStatus` is documented-unreliable, trust `strProgress` |

**Key consequence:** TheSportsDB can never be a per-second source. Achievable per-sport
resolution is MLB ~10s, NHL ~25s, NBA/NFL/soccer ~30s (ESPN-bound), all with a 120s TSDB
safety net. Live Activities realistically land at tens-of-seconds regardless of server
resolution (Apple's per-activity push budget); the in-app WebSocket path gets the full speed.

## Principles

- **Identity vs contested fields.** Identity (event/team IDs, names, badges, `isoDate`,
  `tournamentName`, `round`, `playoff`) comes from the TheSportsDB schedule backbone and is
  *preserved*, never contested — same split `mergeSportEvents` already enforces. The
  reconciler only arbitrates the **dynamic set**: score, status, progress, isCompleted,
  lastPlay, linescores, and single-source enrichment.
- **Provenance is server-only.** Never added to `Game`'s `Codable` (it ships to iOS/watch/
  widgets). Lives in a parallel structure + a Redis side-cache, exactly like the transient
  `lastPlayScoreboardID` (decoded as `nil`, never persisted).
- **Selection = priority × freshness × monotonicity.** Not last-writer-wins, not pure priority.
- **Pure & testable.** Free functions in a new `Reconcile/` group, mirroring the existing
  static-pure-helper + `AppTests/Unit` convention.

## Types

```swift
enum DataSource: String, Codable, CaseIterable {
    case mlbStatsAPI, nhlWeb, espn, theSportsDB, schedule
    func priority(for field: FieldClass) -> Int   // schedule wins identity; official > espn > tsdb
    var freshnessTTL: TimeInterval                 // mlb 30 · nhl 90 · espn 120 · tsdb 300 · schedule ∞
}
enum FieldClass { case identity, score, status, clock, play, enrichment }

struct Observation { let source: DataSource; let fetchedAt: Date; let version: String?; let game: Game }
struct GameProvenance: Codable { var score, status, clock, play: DataSource?; var conflicts: [String] }
struct ReconcileResult { let game: Game; let provenance: GameProvenance; let scoreConfirmed: Bool }
```

`version` is the source's own monotonic token: MLB GUMBO timecode · ESPN `lastPlayScoreboardID`
· NHL last play eventId · TSDB `updated`.

## Selection algorithm

For each contested field, over the set of observations that (a) have a non-nil value and
(b) are fresh (`now - fetchedAt <= source.freshnessTTL`), sorted by `priority(for:)` desc:

1. Take the highest-priority fresh candidate.
2. **Monotonicity guard** vs `lastPublished`: reject a regressing value (score down, status
   `post→in`, completion `true→false`) unless a fresh peer of `>=` priority corroborates it;
   fall through to the next candidate, else hold `lastPublished`.
3. Record the winning source in `GameProvenance`; append any fresh disagreement to `conflicts`.

`scoreConfirmed` = a score increase whose winner is official (MLB/NHL) **or** two-source-agreed.
This gates the Live Activity alert (see below).

## Integration

- **Seam = `Integrator`** (`Sources/App/Integrator.swift`). Add `getMLBLiveScore` /
  `getNHLLiveScore` returning a `LiveScore` with only their sport populated — symmetric with
  the existing `getESPNLiveScore` / `getAllLiveScores`.
- **`ESPNFetchJob.runUnderLock`** builds `[gameKey: [Observation]]` from all sources, runs
  `reconcile` per key, and writes the merged `LiveScore` to `latestLiveInfo` exactly as today.
  Every downstream consumer (iOS WebSocket, `/schedules`, `APNSJob`) is unchanged.
- **Game key:** reuse `TeamAliasResolver.dedupKey(home:away:leagueID:day:)`
  (`Sources/App/ScheduleJobs/TeamAliasResolver.swift`) — already battle-tested for cross-source
  matching incl. PSG≡Paris alias cases.
- **ID mapping:** MLB `gamePk`/team IDs and NHL abbrevs map to TSDB IDs via the same Redis
  pattern as the existing `RedisEndpoint.ESPN.espnEventMap` (`ESPN-ID-Map`).
- **Building reconciled games:** `Game.updated(...)` copy-helper (see "Step 1" below) overlays
  reconciled dynamic fields onto the schedule identity skeleton.

## Provenance persistence + telemetry

- Side-cache `RedisEndpoint.recon(gameKey)` → `{lastScoreHome, lastScoreAway, statusRank,
  perSourceVersion}`, short TTL (game length + buffer). Monotonicity memory across ticks.
- Emit every conflict / rejected regression to the existing `Telemetry` seam
  (`Application.telemetry`, `Telemetry.swift`) as `recon.conflict` / `recon.regression_rejected`.
  This is how the priority table gets tuned from production data instead of guesses.

## Live Activities

The reconciler feeds `latestLiveInfo`, which `APNSJob` already consumes — correctness flows
for free. Four LA-specific requirements:

1. **Phantom-goal suppression (headline win).** The monotonicity guard rejects an ESPN
   flicker `1→0→1` before it reaches `latestLiveInfo`, so `APNSJob.scoreAlert` never fires the
   spurious buzz. Free once reconcile is in place.
2. **Alert authority via `scoreConfirmed`.** Pipe the flag to `APNSJob` as a transient
   server-only field (same mechanism as `lastPlayScoreboardID`) and gate `scoreAlert` on it:
   only buzz on official-sourced or two-source-agreed increases; unconfirmed bumps update the
   score silently until corroborated.
3. **Significant-change gate.** `APNSJob` currently re-pushes on *any* `ContentState`
   inequality, including pure `progress` clock ticks. With faster reconcile that would burn
   Apple's per-activity budget. Push only on score / status / material `lastPlay` change; let
   clock-only deltas ride the next meaningful push.
4. **Honest cadence ceiling.** Drive the in-app WebSocket at full reconcile cadence; treat
   Live Activities as "fast on confirmed scoring events, throttled otherwise." Optionally the
   reconcile loop can enqueue an out-of-band urgent push on `scoreConfirmed` (bounded to a
   few/min/activity) so goals hit the lock screen in seconds rather than up to a minute.

## Rollout

1. **`Game.updated(...)` copy-helper** + refactor `translateTeamIDs` to use it. Safe, additive,
   sets up the reconciler. *(done first — see Step 1.)*
2. **`Reconciler` in shadow mode**: run alongside the existing merge, write to a separate
   `recon:shadow:latestLiveInfo` key, log conflicts. Compare for a week. No user impact.
3. **Flip `latestLiveInfo` to reconciler output** (ESPN + TSDB only — smarter merge of the
   two sources we already have). Delivers phantom-goal suppression + failover.
4. **Add MLB StatsAPI**, then **NHL api-web**, as `Observation` sources (new scheduled jobs
   following the `ESPNSoccerJob` + `JobLock.withLock` template; register in `configure.swift`).
5. **`scoreConfirmed` gate + LA significant-change projection.**

## Verification

- `swift build` + `swift test` in `SportsCalAPI/SportsCalServer`.
- New `AppTests/Unit/ReconcilerTests.swift`: priority ordering; stale-high-priority loses to
  fresh-low; score-regression rejected then accepted-on-corroboration; status never `post→in`;
  `scoreConfirmed` only for official/agreed.
- Extend `AppTests/Integration/APNSJobStateDiffTests.swift`: flicker `1→0→1` produces **zero**
  alerts; unconfirmed bump silent; confirmed → one alert.
- Existing `ScheduleMergeTests` / `DedupKeyTests` must stay green through Step 1.
</content>
</invoke>
