# Push & Live Activity Testing

Single entry point for testing the push-notification and Live Activity pipeline. Three layers — automated server tests, automated iOS tests, manual on-device E2E — plus a live observability endpoint.

## Overview

> **Total coverage today:** 81 automated tests (63 server + 18 iOS), passing in < 2s combined. Plus a 7-scenario manual playbook for the parts ActivityKit will not let you automate.

For deeper context, see <doc:PushTestingGuide> (server-side test reference), <doc:LiveActivityE2EPlaybook> (manual on-device scenarios), and <doc:PushArchitecture> (how the symbols connect).

## TL;DR — run all the automated tests

```bash
# 1. Server (63 tests, ~150ms)
cd SportsCalAPI/SportsCalServer
swift test --filter 'ContentStateDiffTests|TeamMatchingTests|DedupKeyTests|RegistrationCodableTests|APNSJobStateDiffTests|APNSJobErrorHandlingTests|ESPNFetchJobPushToStartTests'

# 2. iOS (18 tests, ~1s — needs a booted iPhone simulator)
cd ../../SportsCal
xcodebuild test \
  -project SportsCal.xcodeproj \
  -scheme "SportsCal (iOS)" \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -only-testing:"SportsCalTests/LiveActivityCodableTests" \
  -only-testing:"SportsCalTests/LiveActivityMatcherTests"
```

Both should print `0 failures` / `TEST SUCCEEDED`.

## Layer 1 — server (Swift Package Manager)

**Where:** `SportsCalAPI/SportsCalServer/Tests/AppTests/`
**What it covers:** Everything that happens server-side — `APNSJob`'s send/diff/cleanup logic, `ESPNFetchJob`'s push-to-start detection and dedup, registration endpoints' Redis writes, error handling for every APNS failure mode.
**Test fakes:** `InMemoryKeyValueStore` (TTL-aware, glob-match scan), `MockAPNSClient` (records sends, scriptable errors), `MutableClock` (advanceable time), `TestGameFactory` (concise `Game` builder).

### Run by suite

```bash
# Pure unit tests (state diff, team matching, dedup keys, codability)
swift test --filter 'ContentStateDiffTests|TeamMatchingTests|DedupKeyTests|RegistrationCodableTests'

# Integration tests (full job loop with in-memory fakes)
swift test --filter 'APNSJobStateDiffTests|APNSJobErrorHandlingTests|ESPNFetchJobPushToStartTests'
```

### What each suite does — at a glance

| Suite | Tests | Pins down |
|---|---|---|
| `ContentStateDiffTests` | 8 | ``ContentState`` equality (the no-push-when-unchanged decision) |
| `TeamMatchingTests` | 12 | `APNSJob.matchEvent` — eventID-first, case-insensitive fallback, legacy registration format |
| `DedupKeyTests` | 8 | Exact Redis key formats for prod + debug envs |
| `RegistrationCodableTests` | 5 | JSON wire format for client→server registrations |
| `APNSJobStateDiffTests` | 9 | Full job loop: when does an update fire, when does end fire, cache write ordering |
| `APNSJobErrorHandlingTests` | 7 | Stale-token cleanup vs. transient-failure retention |
| `ESPNFetchJobPushToStartTests` | 14 | Transition detection, favorites/auto-follow targeting, dedup |

## Layer 2 — iOS (Xcode)

**Where:** `SportsCal/SportsCalTests/`
**What it covers:** Codability of `LiveSportActivityAttributes` + `ContentState`, and the pure match logic in `LiveActivityMatcher` that decides which incoming WebSocket update should be written to which active Live Activity.

| Suite | Tests | Pins down |
|---|---|---|
| `LiveActivityCodableTests` | 6 | `LiveSportActivityAttributes` + `ContentState` round-trip; server-payload compat (server omits `lastPlay`) |
| `LiveActivityMatcherTests` | 12 | iOS-side counterpart to server's `TeamMatchingTests` — same eventID-first / team-name-fallback semantics, plus the redundant-update suppression that prevents Lock Screen flicker |

## Layer 3 — manual on-device E2E (physical iPhone)

See <doc:LiveActivityE2EPlaybook> for the full playbook.

ActivityKit's lifecycle (push token issuance, Lock Screen rendering, Dynamic Island) cannot be exercised on a simulator — real APNS sandbox + real device is the only signal that matters for that layer. Run the playbook before every App Store submission, and any time you change `APNSJob.swift`, `ESPNFetchJob.swift`'s push-to-start path, or `GameViewModel`'s ActivityKit code.

## Layer 4 — live observability

The server keeps in-process counters of every push attempt. Read them while the dev or staging server is running:

```bash
curl -H "X-Admin-Key: $ADMIN_API_KEY_HASH" $DEV_URL/api/admin/push/metrics
```

Response:

```json
{
  "sent": { "update": 42, "end": 3, "start": 7 },
  "errors": { "unregistered": 2, "tooManyRequests": 1 },
  "tokenCleanup": { "unregistered": 2 },
  "dedupHit": 5,
  "dedupMiss": 7,
  "lastUpdated": "2026-04-28T19:24:17Z"
}
```

Counters reset on server restart. Use during the manual playbook to confirm "yes the push actually went out" without tailing logs. The interpretation table is in <doc:PushTestingGuide>.

## CI

Two GitHub Actions workflows under `.github/workflows/`:

- **`server-tests.yml`** — runs the 63 server tests on every PR that touches `SportsCalAPI/**` or `SportsCalModel/**`. Blocks merge on failure.
- **`nightly-push-smoke.yml`** — 08:17 UTC daily. Boots a real Docker Redis and runs the full server suite against it (catches RediStack-specific regressions the in-memory fake deliberately doesn't replicate). Optionally runs E2E vs staging sandbox APNS if `vars.STAGING_E2E_ENABLED == 'true'`. Informational, doesn't block merges.

iOS tests aren't yet wired into CI — Xcode Cloud handles iOS builds via `SportsCal/ci_scripts/ci_post_clone.sh`. To add the iOS LiveActivity suites to a Xcode Cloud test action, point the action at the `SportsCal (iOS)` scheme and let the test plan pick them up automatically.

## Pre-deploy checklist

Before tagging a release that touches push code:

1. ✅ All 63 server tests pass
2. ✅ All 18 iOS tests pass
3. ✅ Manual on-device playbook scenarios 1, 2, 5, 6 pass on a physical iPhone
4. ✅ Visual checklist (<doc:LiveActivityE2EPlaybook>) walked through on at least one device size
5. ✅ `/api/admin/push/metrics` shows non-zero `sent.start` and `sent.update` after the playbook run
6. ✅ Nightly Docker-Redis smoke green (check the workflow run history)

## Troubleshooting

**Server tests fail with "Connection refused" or Redis errors** — you're running `swift test` without the filter, which picks up the legacy `AppTests.swift` that requires a live Redis. Use the filter command above.

**iOS tests can't find a simulator** — list booted simulators with `xcrun simctl list devices booted`. Pass the device ID directly: `-destination "platform=iOS Simulator,id=<UUID>"`.

**A test passes locally but fails in CI** — almost always a clock issue. If you're using `MutableClock.advance(by:)`, confirm you passed the same clock into `InMemoryKeyValueStore(clock:)` at the top of `setUp()`.

**`/api/admin/push/metrics` returns empty / `lastUpdated: distantPast`** — server restarted or no push activity since boot. Trigger a fake game transition via `DebugLiveActivityTestView` or the admin trigger endpoint.

**Pre-existing `AppTests.swift` failures** — `testLive`, `testNumberOfTeams`, `testGamesWithoutCodes`, `testLiveGames` were already failing before the push-testing work. They require a live Redis + bypass of `APIKeyMiddleware`. Filter them out.

## Where the implementation lives

| Concern | File |
|---|---|
| Server seams | `SportsCalAPI/SportsCalServer/Sources/App/{Clock,KeyValueStore,APNSSending}.swift` |
| Server fakes | `SportsCalAPI/SportsCalServer/Tests/AppTests/Fakes/{InMemoryKeyValueStore,MockAPNSClient,MutableClock,TestGameFactory}.swift` |
| Server jobs (under test) | `SportsCalAPI/SportsCalServer/Sources/App/ScheduleJobs/{APNSJob,ESPNFetchJob}.swift` |
| Server observability | `SportsCalAPI/SportsCalServer/Sources/App/PushMetrics.swift` |
| iOS match logic | `SportsCal/Shared/Model/LiveActivityMatcher.swift` |
| iOS Live Activity types | `SportsCal/Shared/LiveSportActivityAttributes.swift` |
| iOS debug harness | `SportsCal/Shared/Views/DebugLiveActivityTestView.swift` |
| CI | `.github/workflows/{server-tests,nightly-push-smoke}.yml` |

## See Also

- <doc:PushArchitecture>
- <doc:PushTestingGuide>
- <doc:LiveActivityE2EPlaybook>
- ``ContentState``
- ``LiveSportAttributes``
