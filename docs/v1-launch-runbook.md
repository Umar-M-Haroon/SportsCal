# V1 Launch Runbook — manual steps to submission

Consolidated, ordered checklist of every **human/out-of-band** step left before
"Submit for Review". Code-side work is done and tracked in
[`RELEASE-READINESS.md`](../RELEASE-READINESS.md) (item IDs below cross-reference it);
this doc only covers what can't be automated. Work top to bottom — each section
gates the next.

---

## 1. Xcode Cloud environment variables (one-time, BEFORE the next archive)

`ci_scripts/ci_post_clone.sh` writes these into the generated `Shared/Constants.swift`.
It only **warns** when one is missing — a missing value ships silently.

- [ ] `SENTRY_DSN` — production Sentry ingest URL. **If unset, crash reporting is OFF in prod.** *(C1)*
- [ ] `ADMOB_APP_ID` — real production AdMob app ID (not the Google sample ID). *(A4)*
- [ ] `ADMOB_NATIVE_AD_UNIT_ID` — real production native ad unit. *(A4)*
- [ ] Confirm `REVENUECAT_API_KEY` is set (production key).
- [ ] Confirm `SPORTSCAL_API_KEY` is set (matches the server's `API_KEY_HASH`).

## 2. Local test gates (run before archiving)

- [ ] **Server** (from `SportsCalAPI/SportsCalServer/`):
  ```bash
  swift test --skip AppTests.AppTests --skip ScheduleCountTests
  ```
  Expected: ~150 tests green. The skipped suites are live-data integration tests
  that need a populated prod-like Redis and fail/SIGTRAP on dev machines.
- [ ] **iOS**: full `SportsCalTests` suite green in Xcode (⌘U) or CI. The MCP
  `RunAllTests` runner has a known "not run" issue — run per-class or in Xcode.
- [ ] Nightly push-smoke green (check the most recent run before submitting).

## 3. Device-feel pass (TestFlight or dev device — pick a busy game day)

- [ ] **Ad cadence (C4)** — the dial-back (1 per 8–10 games, max 2/screen, short
  lists ad-free) is live in code. Verify feel on: a long list (busy NBA/MLB day),
  a short list (should show **zero** ads), and Browse.
- [ ] **GameDetail ad decision** — GameDetail still shows its single ad. Decide
  keep vs remove (one-line revert: the placement in `ModernGameDetailSections.swift`
  / `GameDetailView.swift`). Record the decision in `RELEASE-READINESS.md` §G.
- [ ] Pro subscription removes **all** ads.
- [ ] **Offline pass (C3)**: airplane mode with cached data → stale banner; with a
  fresh install → full-screen offline placeholder; restore network → banner clears,
  live updates resume (WebSocket reconnects immediately).
- [ ] **Skeleton loaders (D4)**: kill + relaunch on Classic theme and open a Browse
  sport — loading states show shimmer rows, not spinners.
- [ ] **Reset Suggestions (D3)**: Settings ▸ Personalization ▸ Reset Suggestions →
  confirm → "For You" suggestions disappear and stay gone after relaunch.
- [ ] Live Activity round-trip: follow a live game → activity starts and updates →
  unfollow → updates stop.

## 4. Archive-time verification

- [ ] `codesign -d --entitlements - Scoreline.app` shows `aps-environment: production`. *(A2)*
- [ ] Organizer ▸ archive ▸ **Generate Privacy Report** renders the app manifest +
  SDK manifests with no errors. *(A1)*
- [ ] Build a **watch-scheme archive** and confirm `PrivacyInfo.xcprivacy` is present
  in the watch app and watch-widgets bundles (the iOS archive can't verify these). *(A1)*
- [ ] `Info.plist` `GADApplicationIdentifier` is the **real** AdMob app ID. *(A4)*
- [ ] `strings` the Release binary and confirm no Tailscale/dev-server IP ships. *(C5)*

## 5. App Store Connect — privacy nutrition labels *(A3 — must match the privacy manifest)*

- [ ] **Identifiers → Device ID**: Collected · Not linked to you · Not used for tracking · App Functionality.
- [ ] **Other Data** (favorites / followed event IDs): Collected · Not linked · Not tracking · App Functionality.
- [ ] **Diagnostics → Crash Data + Performance Data** (Sentry): Collected · Not linked · App Functionality.
- [ ] **Purchases** (RevenueCat): Collected · **Linked** · App Functionality.
- [ ] Do **NOT** list EngagementTracker data — it is on-device only (never leaves the
  phone, user-resettable via D3) → "not collected".
- [ ] "Data Used to Track You" = **none**.
- [ ] Privacy-policy URL is filled in and the page is live.

## 6. App Store Connect — EEA ads *(C10)*

- [ ] Complete the EU DSA / ad-serving declaration in ASC.
- [ ] Posture: **non-personalized ads only** — no Google-certified CMP ships in v1,
  so do not enable personalized ads for EEA traffic. (If personalized ads are wanted
  later: add ATT prompt + certified CMP first — v1.1+.)

## 7. Submission

- [ ] TestFlight build distributed and the §3 device pass completed on it.
- [ ] Screenshots / metadata / release notes ready in ASC.
- [ ] Server is current: prod deploys **from `main` only**, from a **clean worktree**
  (`deploy/deploy.sh` rsyncs the working tree — never deploy from a dirty checkout).
  Merge `cleanup-staging` → `main` (fast-forward) and redeploy before submitting if
  server changes are pending.
- [ ] Submit for review.

## Post-submit / launch-week watch list

- Sentry: crash-free rate after release.
- AdMob: fill rate + eCPM with the dialed-back cadence (C4) — revisit cadence with data.
- Server: `/ping` + schedule counts after any deploy (June 9 incident: MLB/NFL served
  0 games until `sportsDBSingleYearSeason` fix — check all 8 leagues are populated).
- v1.1 backlog already decided: App Attest (B9), CMP/ATT if personalized ads wanted,
  admin metrics counters (§F).
