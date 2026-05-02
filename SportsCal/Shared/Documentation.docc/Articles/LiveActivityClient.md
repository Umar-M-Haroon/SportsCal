# Live Activity Client

The iOS-side counterpart to the server's push pipeline: how the app subscribes, matches incoming updates to running activities, and avoids redundant Lock Screen redraws.

## Overview

The server (`SportsCalServer`) pushes updates to APNS; the iOS side decides which running `Activity<LiveSportActivityAttributes>` should consume which update, and whether the change is worth re-rendering. Manual on-device verification of this whole flow lives in the server's documentation under `LiveActivityE2EPlaybook`.

## The three responsibilities

| Concern | Where | What it does |
|---|---|---|
| Lifecycle | `GameViewModel.observeLiveActivities()` | Subscribes to `Activity.activityUpdates` + `pushTokenUpdates` for every active activity; re-subscribes after force-quit |
| Matching | `LiveActivityMatcher` | Pure logic: given an incoming `Game` from the WebSocket, find the matching running activity (eventID first, then case-insensitive team-name fallback) |
| Suppression | `LiveActivityMatcher.resolveUpdate` | Returns `nil` when the new state equals the cached state — prevents redundant `Activity.update(...)` calls that flicker the Lock Screen |

`LiveActivityMatcher` is deliberately stateless and pure so its 12 unit tests can run in milliseconds without standing up `ActivityKit`. It's the iOS-side counterpart to the server's `APNSJob.matchEvent` — both layers must agree on team-name normalization and eventID precedence, which is why each layer has matching tests pinning the same semantics.

## Match precedence

Same on both sides:

1. **eventID.** If the incoming `Game.idEvent` matches an activity's `attributes.eventID`, use that activity. End of story.
2. **Team-name fallback.** Lowercase both home and away names, compare in order. A "Lakers @ Warriors" registration must NOT match "Warriors @ Lakers" — order is meaningful.
3. **No match.** Return nil; the update is dropped silently. This is correct: an activity for an event the user no longer follows shouldn't randomly receive someone else's score.

## Suppression rules

`Activity.update(...)` is *cheap to call* but *expensive to render* — every call wakes the Lock Screen renderer. `resolveUpdate` returns the new `ContentState` only when one of:

- `homeScore` changed
- `awayScore` changed
- `status` changed (e.g. `pre` → `in`, `in` → `final`)
- `progress` changed (`"2:14 - 3rd"`)

If none changed, returns nil and the caller skips `Activity.update`. The same equality check on the server side (`ContentState` equality) prevents the push from going out in the first place — but client-side suppression is needed because WebSocket updates arrive on every tick whether they changed or not.

## The handshake

Activity registration is a two-token handshake:

1. **Push-to-start token.** Issued by iOS on first launch via `Activity<LiveSportActivityAttributes>.pushToStartTokenUpdates`. Posted to `POST /api/registration/pushToStart` with the user's favorites + auto-followed eventIDs. Server stores `PushToStart-{token}` and `PushToStartEvents-{token}` in Redis.
2. **Per-activity token.** When iOS actually creates an `Activity` (because `ESPNFetchJob` sent push-to-start, or because the user tapped "Follow this game"), `Activity.pushTokenUpdates` issues a *second* token specific to that activity. Posted to `POST /api/registration/apns` with the eventID. Server stores `APNS-{token}` so `APNSJob` can target updates to it.

If the server gets `.unregistered` or `.badDeviceToken` from APNS, it deletes the matching key — the next launch re-registers.

## Debugging from the app

`SettingsView → Developer → Live Activity Testing` opens `DebugLiveActivityTestView`. It exposes:

- **Pipeline checklist** — five red/green indicators (token obtained, token registered, event IDs synced, APNS configured, notifications-sent count). If any are red, fix those before debugging anything else.
- **Fake game factory** — `DebugGameFactory.createFakeGame(...)`, `transitionToLive()`, `forceFinal()`. Used end-to-end by every scenario in the server's playbook.
- **Auto-follow controls** — add/remove fake event IDs from the auto-follow list to test late-registration semantics.
- **Event log** — every `AutoFollowLogger` entry, useful for reading the iOS → server handshake without leaving the device.

## Console logs

For richer debugging, open `Console.app` on the Mac with the device connected:

```
subsystem:com.umar.SportsCal category:liveActivity
```

This filters to just the matcher / activity-update lifecycle logs. The Mac console is significantly more readable than Xcode's debug console for this use case because the device tail can be left running across builds.

## See Also

- <doc:ViewModelArchitecture>
- <doc:SnapshotTesting>
