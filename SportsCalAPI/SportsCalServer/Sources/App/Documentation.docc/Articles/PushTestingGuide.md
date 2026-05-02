# Push Testing Reference

Reference for the test harness, fakes, suites, and observability that cover the push-notification + Live Activity pipeline.

## Overview

Start here before touching `APNSJob.swift`, `ESPNFetchJob.swift`, `GameViewModel.swift` push paths, or the Redis registration schema. For the high-level testing index see <doc:ServerOverview>; for manual on-device scenarios see <doc:LiveActivityE2EPlaybook>.

## What exists

| Layer | Location | How to run | Runtime |
|---|---|---|---|
| Server unit tests | `SportsCalAPI/SportsCalServer/Tests/AppTests/Unit/` | `swift test --filter '<Name>'` | < 10ms |
| Server integration tests | `SportsCalAPI/SportsCalServer/Tests/AppTests/Integration/` | `swift test --filter '<Name>'` | < 500ms total |
| iOS Codable tests | `SportsCal/SportsCalTests/LiveActivityCodableTests.swift` | Xcode test runner | < 1s |
| iOS matcher tests | `SportsCal/SportsCalTests/LiveActivityMatcherTests.swift` | Xcode test runner | < 1s |
| Manual device E2E | <doc:LiveActivityE2EPlaybook> | Physical iPhone + dev server | ~15 min |
| CI — per-PR | `.github/workflows/server-tests.yml` | Triggered automatically | ~2 min |
| CI — nightly | `.github/workflows/nightly-push-smoke.yml` | 08:17 UTC daily | ~5 min |
| Admin observability | `GET /api/admin/push/metrics` | curl with admin key | instant |

## Running server tests

### All push/live-activity tests

```bash
cd SportsCalAPI/SportsCalServer
swift test --filter 'ContentStateDiffTests|TeamMatchingTests|DedupKeyTests|RegistrationCodableTests|APNSJobStateDiffTests|APNSJobErrorHandlingTests|ESPNFetchJobPushToStartTests'
```

Expected: **63 tests, 0 failures, ~120ms**.

### Just unit tests (pure logic, no fakes)

```bash
swift test --filter 'ContentStateDiffTests|TeamMatchingTests|DedupKeyTests|RegistrationCodableTests'
```

### Just integration tests (full job loop with in-memory fakes)

```bash
swift test --filter 'APNSJobStateDiffTests|APNSJobErrorHandlingTests|ESPNFetchJobPushToStartTests'
```

### Running a single test by name

```bash
swift test --filter 'ESPNFetchJobPushToStartTests/test_dedupKeyExpires_reEnablesNextSend'
```

### Known pre-existing failures

`AppTests.swift` has `testLive`, `testNumberOfTeams`, `testGamesWithoutCodes`, `testLiveGames` — these require a running Redis + bypass of `APIKeyMiddleware` and were already failing before the push-testing work. Ignore them when evaluating push test results; filter by name to avoid the noise.

## What each suite covers

### `ContentStateDiffTests` (8 tests)

The equality semantics of ``ContentState`` — the struct whose equality check drives "should we send a push on this tick or not". A regression here silently either drops updates or sends duplicates; both are user-invisible until someone complains. Tests cover each field (`homeScore`, `awayScore`, `status`, `progress`) and nil-optional handling, plus full JSON round-trip.

### `TeamMatchingTests` (12 tests)

The matching logic in `APNSJob.matchEvent`. Covers:

- eventID-first precedence (even when team names would also match)
- Case-insensitive team-name fallback
- Home/away ordering (a Lakers @ Warriors registration must NOT match Warriors @ Lakers)
- Duplicate team names across leagues (NFL Giants vs MLB Giants — documents current "return first" behavior)
- Legacy plain-eventID registration format (pre-JSON migration)
- Token extraction from `APNS-{token}` and `debug-APNS-{token}` keys

### `DedupKeyTests` (8 tests)

Pins the exact Redis key format for every push-related entry. A rename silently breaks push-to-start delivery, `APNSJob` matching, and the admin dashboard all at once. Covers prod + debug variants of `SentPushToStart-`, `PushToStart-`, `PushToStartEvents-`, and `EventState-`. Also asserts `PushToStart-*` glob would match `PushToStartEvents-*` without filtering — this is why `ESPNFetchJob.runPushToStartPhase` explicitly filters.

### `RegistrationCodableTests` (5 tests)

Round-trip JSON encoding for `APNSRegistration`, `PushToStartRegistration`, ``LiveSportAttributes``. Includes decoding a request without the optional `eventIDs` field (what most clients send).

### `APNSJobStateDiffTests` (9 tests)

End-to-end job-loop tests using `InMemoryKeyValueStore` + `MockAPNSClient`:

- No push when state cache matches current state
- Update on home/away score increment
- Update on status change
- End push + both Redis keys deleted when game reaches `hasDoneStatus`
- `EventState` cache written before send (documents current ordering)
- Team-name fallback works through full loop
- No-op when there are no registrations
- Scheduled games (empty score strings) skipped silently

### `APNSJobErrorHandlingTests` (7 tests)

APNS failure branching. Pins who gets cleaned up vs retained:

- `.unregistered` → delete `APNS-{token}`
- `.badDeviceToken` → delete `APNS-{token}` (we now treat both as stale-token)
- `.tooManyRequests` / `.internalServerError` / `.payloadTooLarge` / `.tokenAuthFailure` → retain token, log, move on
- End-push failure does not un-delete the registration — game is over, the user doesn't need further updates

### `ESPNFetchJobPushToStartTests` (14 tests)

Transition detection + push-to-start dispatch:

- Detects `pre → in` transition
- Doesn't re-detect a game that was already `in` in the previous snapshot
- Cold-start (nil previous) treats all in-progress games as newly started
- Favorites matching: home team, away team, neither
- Auto-follow event ID matching
- Dedup key prevents re-sends within 8h; TTL expiry re-enables
- Both favorites + event-ID registered for same game → exactly one push (dedup catches the second pass)
- `PushToStart-*` scan must not match `PushToStartEvents-*` (regression guard)
- Stale-token cleanup removes both `PushToStart-{token}` and `PushToStartEvents-{token}`
- Debug env uses `debug-` prefix exclusively

## Adding a new test

1. **Decide which layer it belongs in.** Pure logic (no I/O, no async) → `Unit/`. Exercises the full job loop or endpoint → `Integration/`.

2. **Reuse `TestGameFactory`** for building `Game` objects — the real `Game` initializer has 40+ parameters and most tests only care about 5 of them.

3. **For integration tests, the boilerplate is:**

```swift
override func setUp() async throws {
    clock = MutableClock()
    kv = InMemoryKeyValueStore(clock: clock)  // clock must be shared or TTLs won't expire
    apns = MockAPNSClient()
}
```

> Important: pass the same `clock` to `InMemoryKeyValueStore` that your test code calls `advance(by:)` on. Otherwise the store uses `SystemClock` and your TTL-expiry assertions silently pass without actually testing anything.

4. **Seed Redis state via `kv.setJSON` / `kv.setString`**, run the job via `APNSJob.runOnce(...)` or `ESPNFetchJob.runPushToStartPhase(...)`, then assert:
   - `apns.recorded` for pushes that went out
   - `kv.rawSnapshot` for what's left in Redis

5. **To script APNS errors:**

```swift
apns.queueError(APNSSendError(reason: .unregistered, underlying: nil), for: token)
```

FIFO queue — next send to that token throws that error, subsequent sends succeed. Use `apns.setGlobalError(_:)` if you want every send to fail.

6. **Run just your new test** while iterating:

```bash
swift test --filter 'YourSuiteName/test_your_specific_test'
```

## Reading the admin metrics endpoint

```bash
curl -H "X-Admin-Key: $ADMIN_API_KEY_HASH" $DEV_URL/api/admin/push/metrics
```

Response shape (all counters reset on server restart):

```json
{
  "sent": { "update": 42, "end": 3, "start": 7 },
  "errors": { "unregistered": 2, "tooManyRequests": 1 },
  "tokenCleanup": { "unregistered": 2 },
  "dedupHit": 5,
  "dedupMiss": 7,
  "lastUpdated": "2026-04-23T18:24:17Z"
}
```

### How to interpret

- **`sent.update` growing, `sent.end` not** — games aren't being marked finished. Likely an ESPN status parsing issue or `hasDoneStatus` regression.
- **`errors.unregistered` > 0 but `tokenCleanup.unregistered` == 0** — cleanup branch is broken. `APNSJob.swift:110-113` or `ESPNFetchJob.swift:718-726` stopped deleting stale tokens.
- **`dedupMiss` >> `dedupHit`** — push-to-start is firing for games it shouldn't (dedup key not being written). Check `SentPushToStart-*` in Redis.
- **`sent.start` == 0 after game transitions you know should have triggered it** — either favorites/event-ID matching is failing, or `ESPNFetchJob.detectNewlyStartedGames` isn't seeing the transition (previous snapshot bug).
- **`errors.tokenAuthFailure`** — APNS auth key (`.p8`) expired or `APNSkeyID` / `TeamID` env vars wrong. Server restart won't help; fix the config.
- **`lastUpdated` is hours old while the server is live** — no push activity at all; check if `APNSConfiguredKey` is actually true via the health endpoint.

## CI gates

### Per-PR (`server-tests.yml`)

Runs on any change to `SportsCalAPI/**` or `SportsCalModel/**`. Executes the 63 unit + integration tests using in-memory fakes. Blocks merge on failure. Expected to take < 2 minutes.

### Nightly (`nightly-push-smoke.yml`) — 08:17 UTC daily

Two jobs:

1. **Docker Redis smoke** — boots `redis:7-alpine` and runs the full server suite against it. Catches RediStack-specific regressions (SCAN cursor semantics, TTL edge cases) that the in-memory fake deliberately doesn't replicate.
2. **E2E vs staging sandbox APNS** — gated by `vars.STAGING_E2E_ENABLED == 'true'`; runs tests tagged `E2E`. Posts to Slack on failure if `SLACK_WEBHOOK_URL` secret is set.

The E2E harness itself isn't built yet — the workflow is skeleton only. When staging creds are available, add `Tests/AppTests/E2E/E2EHarness.swift` and the workflow will pick it up.

## iOS tests

Two suites under `SportsCalTests/`:

### `LiveActivityCodableTests` (6 tests)

`LiveSportActivityAttributes` + `ContentState` Codable round-trip (with and without nil optionals), equality, and server-payload compatibility (server omits `lastPlay`; client must still decode).

### `LiveActivityMatcherTests` (12 tests)

Tests `LiveActivityMatcher` — the pure logic extracted from `GameViewModel.updateLiveActivities()`. This is the iOS-side counterpart to the server-side `APNSJob.matchEvent` tests, and locks in the exact same eventID-first / team-name-fallback semantics so the two layers stay in sync. Covers:

- `buildLookup` — eventID and team-key indexes built correctly, missing eventIDs handled, team keys lowercased
- `matchedState` — eventID precedence, case-insensitive team fallback, home/away ordering enforced, no-match returns nil
- `resolveUpdate` — returns nil when state is unchanged (avoids redundant `Activity.update` calls), returns new state on score change
- End-to-end: TheSportsDB ↔ ESPN event-ID divergence still resolves via team-name fallback (regression guard for the most common silent-failure mode)

### Running

```bash
cd SportsCal
xcodebuild test \
  -project SportsCal.xcodeproj \
  -scheme "SportsCal (iOS)" \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -only-testing:"SportsCalTests/LiveActivityCodableTests" \
  -only-testing:"SportsCalTests/LiveActivityMatcherTests"
```

Or in Xcode: ⌘U with the iOS scheme selected, or right-click either class in the test navigator → Run.

Expected: **18 tests pass in < 1s**.

## Troubleshooting

### "Tests pass locally but fail in CI"

Almost always a clock issue. If you're using `MutableClock.advance(by:)`, confirm you passed the same clock into `InMemoryKeyValueStore(clock:)` at the top of `setUp()`. The bug is invisible locally because TTLs happen to not matter for most assertions — in CI a slightly different execution order exposes it.

### "Integration test fails with 0 pushes when I expected 1"

Check the log output — most likely it says `Already sent push-to-start for {eventID}` because a previous test or test-setup step wrote the dedup key and you didn't call `apns.reset()` + re-seed favorites. Or the favorites key was TTL'd and expired when you advanced the clock.

### "My new test fails with 'No such module App'"

SourceKit LSP false positive — the SPM build graph isn't visible in isolation. `swift build` will compile fine. If `swift test` actually fails with this, your test file is probably missing from a `testTarget` in `Package.swift`, but `AppTests` sweeps all Swift files in `Tests/AppTests/` so this shouldn't happen.

### "The server build passes but the admin dashboard shows push metrics as empty"

Server restarts reset the counters — this is expected. `lastUpdated: distantPast` in the response means no push activity since boot. Trigger a fake game transition via `DebugLiveActivityTestView` to generate traffic.

### "I changed the Redis key format and now nothing matches"

`DedupKeyTests` should have failed. If it didn't, update it — the tests pin the exact wire format precisely so changes are deliberate, not accidental. Then manually flush the old Redis keys in dev + staging; existing registrations won't match the new scheme.

## Related files

- Seams: `Clock.swift`, `KeyValueStore.swift`, `APNSSending.swift` (all in `Sources/App/`)
- Fakes: `Tests/AppTests/Fakes/MutableClock.swift`, `InMemoryKeyValueStore.swift`, `MockAPNSClient.swift`, `TestGameFactory.swift`
- Jobs under test: `ScheduleJobs/APNSJob.swift`, `ScheduleJobs/ESPNFetchJob.swift`
- Observability: `PushMetrics.swift`, `Controllers/AdminController.swift` (`pushMetrics(req:)`)

## See Also

- <doc:ServerOverview>
- <doc:LiveActivityE2EPlaybook>
- <doc:PushArchitecture>
