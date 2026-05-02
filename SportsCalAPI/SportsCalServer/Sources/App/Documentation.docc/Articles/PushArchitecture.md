# Push Architecture

How a score change in ESPN's API turns into a buzz on the user's lock screen.

## Overview

Two scheduled jobs do all the work, plus one wire-format struct that travels between them and the iOS client.

| Concern | Where | Cadence |
|---|---|---|
| Detect "this game just started" → push-to-start | `ESPNFetchJob.runPushToStartPhase` | Every 60s |
| Detect "score changed for a live game" → update push | `APNSJob.runOnce` | Every 60s |
| Wire format the iOS app deserializes | ``ContentState`` (inside ``LiveSportAttributes``) | Per push |

The two jobs are deliberately separate because they answer different questions:

- **`ESPNFetchJob`** owns the polling cycle and writes Redis. While it's there, it cheaply notices `pre → in` transitions and fires push-to-start.
- **`APNSJob`** runs after, reading whatever `ESPNFetchJob` wrote, diffs it against `EventState-{eventID}`, and pushes update / end notifications.

Splitting the responsibilities keeps each job's diff-and-decide logic small enough to test exhaustively (see <doc:PushTestingGuide>).

## The push-to-start path

```
ESPN API ──poll──▶ ESPNFetchJob.run
                         │
                         ├── writes ──▶ Redis "latestLiveInfo"
                         │
                         └── runPushToStartPhase
                                  │
                                  ├── detect pre→in transitions
                                  ├── filter via SentPushToStart-{eventID} dedup
                                  ├── match registered tokens
                                  │       (PushToStart-{token} contains favorites,
                                  │        PushToStartEvents-{token} contains explicit eventIDs)
                                  └── send APNS push-to-start
                                          │
                                          └── iOS: ActivityKit creates activity
```

Dedup keys (`SentPushToStart-{eventID}`) carry an 8-hour TTL — long enough to cover overtime and intermission, short enough that the next day's game with the same teams gets its own push.

## The update path

```
APNSJob.runOnce (every 60s)
       │
       ├── reads "latestLiveInfo" from Redis
       │
       ├── for each Game with hasDoneStatus=false:
       │       │
       │       ├── load EventState-{eventID} from Redis
       │       ├── build ContentState from current Game
       │       ├── if cached == new: skip (no push)
       │       ├── else: send APNS update push
       │       │       │
       │       │       └── on .unregistered/.badDeviceToken:
       │       │             delete APNS-{token}
       │       │
       │       └── write EventState-{eventID} = new ContentState
       │
       └── for each Game with hasDoneStatus=true:
               send end push, delete EventState-{eventID} and APNS-{token}
```

The "skip if equal" check is what keeps the Lock Screen from flickering — `APNSJob` runs every 60s but only fires a push when ``ContentState`` actually changed. The same equality check on the iOS side (`LiveActivityMatcher.resolveUpdate`) handles redundant WebSocket updates.

## Registration handshake

The client side of the picture (the symbols in `SportsCal/Shared/`):

1. App launch creates an `Activity<LiveSportActivityAttributes>.pushToStartTokenUpdates` subscription.
2. When iOS issues a token, `GameViewModel` posts it to `POST /api/registration/pushToStart` with the user's favorites + explicit eventIDs.
3. Server stores `PushToStart-{token}` (favorites) and `PushToStartEvents-{token}` (eventIDs) in Redis with no TTL.
4. When `ESPNFetchJob` fires a push-to-start and gets back `.unregistered`, both keys are deleted and the device re-registers on next launch.

The same flow applies to update tokens (`APNS-{token}` instead of `PushToStart-{token}`); the iOS handler in `GameViewModel.observeLiveActivities()` calls `POST /api/registration/apns` once per `Activity` lifecycle.

## Live Activity contract

The wire format both jobs share with the iOS client:

- ``LiveSportAttributes`` — the immutable identity of the activity (event ID, team names, badges).
- ``ContentState`` — the mutable per-tick state (scores, status, progress, last play, isCompleted).

A push payload is `{ aps: { ..., content-state: ContentState } }`. The iOS app's `Activity<LiveSportAttributes>` reads `content-state` and re-renders.

## Failure modes that the tests pin down

These are all in <doc:PushTestingGuide> in detail; here's the index:

- ``ContentState`` equality regression → silent dropped or duplicated pushes (`ContentStateDiffTests`).
- `APNSJob.matchEvent` ordering bug → wrong activity gets the score (`TeamMatchingTests`).
- Redis key rename → push-to-start, matching, and admin dashboard all silently break (`DedupKeyTests`).
- Stale-token cleanup branch breakage → tokens accumulate forever (`APNSJobErrorHandlingTests`).
- Snapshot pointer bug in `ESPNFetchJob` → either misses transitions or re-fires push-to-start every minute (`ESPNFetchJobPushToStartTests`).

## Related symbols and files

- ``ContentState`` — the diff target for "should I push?"
- ``LiveSportAttributes`` — activity identity
- `APNSJob.swift` — update + end push loop
- `ESPNFetchJob.swift` — polling + push-to-start detection
- `PushMetrics.swift` — in-process counters surfaced via `/api/admin/push/metrics`
- `Clock.swift`, `KeyValueStore.swift`, `APNSSending.swift` — testable seams (in-memory fakes in `Tests/AppTests/Fakes/`)

## See Also

- <doc:ServerOverview>
- <doc:PushTestingGuide>
- <doc:LiveActivityE2EPlaybook>
- ``ContentState``
- ``LiveSportAttributes``
