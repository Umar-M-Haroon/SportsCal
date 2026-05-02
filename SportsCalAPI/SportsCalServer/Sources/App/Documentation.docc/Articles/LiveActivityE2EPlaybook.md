# Live Activity E2E Playbook

Manual on-device test scenarios for push notifications and iOS Live Activities. Use a physical iPhone — the simulator does not participate in real APNS push delivery.

## Overview

Run this checklist against a dev server (`.development` env) before shipping any change that touches push notifications, live activities, or the scheduled jobs that drive them (`APNSJob`, `ESPNFetchJob`).

## Prerequisites

- Physical iPhone on iOS 16.2+ running a debug build of the app pointing at the dev server.
- Dev server running with `swift run` (or `./force-restart.sh`) in `.development` env, so it uses `debug-*` Redis key prefixes and sandbox APNS.
- `$ADMIN_API_KEY_HASH` set locally for the debug-trigger endpoint.
- Open `SettingsView → Developer → Live Activity Testing` (the `DebugLiveActivityTestView`) — every scenario below is driven from that screen.
- Keep `Console.app` open, filtered on subsystem `com.umar.SportsCal` with category `liveActivity`, so you can read the client side of the handshake without squinting at the device.

## Scenarios

### 1. Happy path (full lifecycle)

1. Open the debug view; confirm the pipeline checklist starts with "Push-to-start token obtained" ✅ and "Token registered with server" ✅. If either is ❌, the rest of the playbook is moot — debug those first.
2. Tap "Create fake upcoming game" and pick a sport.
3. Confirm the event ID is marked "auto-follow" and is listed under "Event IDs sent to server".
4. Tap "Transition to live" (uses `DebugGameFactory.transitionToLive()` under the hood).
5. **Assert:** push-to-start notification arrives within 30s; Lock Screen shows the activity; Dynamic Island shows compact/expanded representations.
6. Tap "Simulate score +7 home"; **assert:** Lock Screen updates within the next `APNSJob` tick (≤ 60s) and Dynamic Island follows.
7. Tap "Force final status"; **assert:** end push arrives; activity dismisses via the dismissal policy; `debug-APNS-{token}` and `debug-EventState-{eventID}` are removed from Redis (verify via Admin → Redis Viewer).

### 2. Relaunch with an active activity

1. Start a fake live activity (steps 1–4 above).
2. Force-quit the app (swipe up in app switcher).
3. Relaunch. In the debug view, confirm pipeline checklist still shows green for registration — `observeLiveActivities()` should have re-subscribed on launch.
4. Tap "Simulate score +3"; **assert:** update push still arrives and Lock Screen reflects it.

### 3. Manual trigger via admin endpoint

```bash
curl -H "X-Admin-Key: $ADMIN_API_KEY_HASH" \
  -X POST $DEV_URL/debug/trigger-push-to-start \
  -H "Content-Type: application/json" \
  -d '{"eventID":"debug-fake-123","homeTeam":"Lakers","awayTeam":"Warriors"}'
```

**Assert:** response JSON shows `notified >= 1` with your token in the `tokens` array; Lock Screen activity appears.

### 4. Late registration

1. Before starting a fake game, make sure you have no favorites/auto-follows set.
2. Transition a fake game to "in" (scenario 1, steps 2–4) — push-to-start should fire for anyone else following, but you shouldn't receive one.
3. Now add the team to your favorites.
4. **Assert:** no push-to-start fires retroactively (correct dedup behavior — game already in progress when you started following). The scheduled `APNSJob` will still deliver updates the next time the score changes, because the liveActivity subscription is event-scoped, not push-to-start-scoped.

### 5. Duplicate favorites (idempotency)

1. Register the same token twice from the debug view (tap "Re-register").
2. Transition a fake game matching your favorites to "in".
3. **Assert:** exactly one push-to-start arrives; exactly one activity is visible on the Lock Screen.

### 6. Airplane mode recovery

1. Start a live activity (scenario 1, steps 1–4).
2. Enable airplane mode for at least 5 minutes.
3. During airplane mode: tap "Simulate score +14" — this updates the server's cached LiveScore but can't deliver an APNS push to an offline device.
4. Disable airplane mode.
5. **Assert:** Lock Screen catches up with the correct score within the next `APNSJob` tick (≤ 60s from re-connection).

### 7. APNs environment banner sanity

1. Force a mismatch: point the iOS app (debug build, sandbox APNS) at a prod server (production APNS).
2. **Assert:** `APNsEnvironmentMismatchBanner` in `SettingsView.swift:41` is visible with the correct warning.
3. Revert to matching envs; confirm banner disappears.

## Device/UI visual checklist (pre-App Store submission)

Run once per release across the matrix:

- [ ] **Dynamic Island — compact:** team logos + score visible, no truncation, team colors correct.
- [ ] **Dynamic Island — expanded:** progress string (`"2:14 - 3rd"` / inning / etc.) visible, not truncated.
- [ ] **Dynamic Island — minimal:** leading team's color/logo visible.
- [ ] **Lock Screen — 6.1" (844×390):** light + dark; readable at arm's length.
- [ ] **Lock Screen — 6.7" (932×430):** light + dark; readable at arm's length.
- [ ] **Dynamic Type XL:** text doesn't clip, scores remain legible.
- [ ] **Reduce Transparency enabled:** backgrounds don't go translucent.
- [ ] **StandBy mode** (iPhone 14 Pro+): activity visible on the side-mounted display, correct tinting.
- [ ] **Always-On Display** (iPhone 14 Pro+): activity persists, updates coalesce without flicker.
- [ ] **Notification Center:** swipe down — expanded layout renders correctly.
- [ ] **Watch mirror:** if the iPhone is paired to an Apple Watch, the activity mirrors on the watch face (or gracefully declines if the user has it disabled).
- [ ] **End animation:** `.end(dismissalPolicy: .after(4h))` plays the end animation exactly once; the activity then collapses rather than staying in a zombie state.

## Troubleshooting

- **Pipeline checklist stuck at "Push-to-start token obtained ❌"**: the system needs a few seconds after first launch to produce the token. If it persists, check `Activity<LiveSportActivityAttributes>.pushToStartTokenUpdates` isn't blocked on an unrelated main-actor hop.
- **Push arrives on simulator logs but not on the device**: you're on sandbox APNS but the device's provisioning profile is production-signed. Rebuild with a debug configuration.
- **No push at all after `POST /debug/trigger-push-to-start`**: confirm `apnsConfigured=true` in the response trace. If false, the server didn't find `AuthKey_{keyID}.p8` — check its `configure.swift:24-44` guard.
- **Activity updates but Lock Screen stays stale**: iOS coalesces low-priority ActivityKit updates. Our updates use `.immediately` priority so this should be rare; if it happens consistently, double-check `APNSJob.swift:91` still sets `priority: .immediately`.

## See Also

- <doc:ServerOverview>
- <doc:PushTestingGuide>
- <doc:PushArchitecture>
