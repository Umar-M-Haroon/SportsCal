# SportsCal — Release Readiness Plan

**Goal:** Ship a polished v1 to the App Store over the next few weeks. Bar: UX feels right, few/no bugs, ads present but not intrusive, server handles realistic load.

**Working mode:** Discovery → triage by severity → fix in approved batches (plan mode, per-batch approval) → verify → submit. No auto-fixing; each batch is reviewed.

**Status legend:** 🔴 Open · 🟡 Partial / needs verify · 🟢 Done · ⚪️ Moot

**Severity:**
- **S0 Blocker** — App Store rejection, prod broken, security/data-loss
- **S1 High** — crash, legal risk, or load failure under realistic traffic
- **S2 Medium** — degraded UX / hygiene; shippable with known issue
- **S3 Low** — polish, defer to v1.1 OK

> Severities below are *my* reconciliation (the April audit over-weighted a few). Disagreements noted inline. Cut line for "polished v1": fix **all S0 + all S1 + most S2**, defer S3.

---

## A. App Store Blockers (S0) — must fix before submission

| ID | Item | Status | Effort | Notes |
|----|------|--------|--------|-------|
| A1 | **Privacy manifest** `PrivacyInfo.xcprivacy` (audit #03) | 🟢 | 1–2h | **DONE (Batch 2).** Authored small first-party manifest (UserDefaults CA92.1+1C8F.1; Device ID + Other collected, not-linked/not-tracking, App Functionality). Added to iOS app + widget (pbxproj) and watch app + watch widgets (synchronized folders). **Verified in build artifact**: present in `Scoreline.app` root + embedded `.appex`, valid plist. Watch bundles verify on a watch-scheme archive. |
| A2 | **Release APS entitlement** = `development` (audit #04) | 🟢 | 2m | **DONE (Batch 1).** Release entitlements now `production`; Debug left `development`. Verify at archive time via `codesign -d --entitlements -`. |
| A3 | **App Privacy nutrition labels** in App Store Connect (audit #12) | 🟡 | 30m | *Manual web-console task (checklist in plan).* Declare: Device ID (collected/not-linked/not-tracking/App Functionality), Other Data (favorites), Crash+Performance (Sentry), Purchases (RevenueCat, linked). **Do NOT list EngagementTracker** (on-device → not collected; corrects April audit). "Used to track you" = none (per C10). Privacy-policy URL required. |
| A4 | **Ad unit IDs**: confirm Release uses real `Constants.nativeAdUnitID`, not Google test unit | 🟡 | 30m | **Code verified ✓** — `NativeAdManager.defaultAdUnitID` already guards DEBUG→test / Release→`Constants.nativeAdUnitID`. **Info.plist `GADApplicationIdentifier` verified real (`ca-app-pub-7626…~5399…`, not Google test ID) — June 9.** Remaining: confirm Xcode Cloud `ADMOB_*` env vars set + device check in Phase 3. |

## B. High (S1) — crashes, legal, load failure

| ID | Item | Status | Effort | Notes |
|----|------|--------|--------|-------|
| B1 | **Force-unwraps in view code** — `GameScoreView.swift:81`, `F1GapRibbonView.swift:157` | 🟢 | 30m | **DONE (3a) — reclassified S1→S3.** On reading: both `parts.last!` are guarded by `count >= 2`, so they can't crash. De-`!`'d anyway for hygiene. Not the crash risk the April pass implied. |
| B2 | **ESPN HTTP→HTTPS** on server (audit #02) — 6× `http://site.api.espn.com` in `ESPNNetworking.swift` | 🟢 | 5m | **DONE (Batch 1).** All 6 → HTTPS; server builds clean. |
| B3 | **Remove ESPN branding** from admin UI/source (audit #05) | 🟢 | 10m | **DONE (Batch 1).** `LiveGames.ts` 80/176/212 genericized; admin builds clean. Endpoint name `live-espn` left (optional rename needs server route change). |
| B4 | **Gate `mock-subscribed` behind `#if DEBUG`** (audit #07) — `SubscriptionManager.swift:34,75` | 🟢 | 5m | **DONE (Batch 1).** Gated env-var path AND the bigger leak: the **Settings "Mock Pro" toggle** (reachable via user-toggleable Debug Mode) + `setMockPro` body now `#if DEBUG`. iOS builds clean. |
| B5 | **Server: unbounded APNS scan+MGET** — used Redis `KEYS` + one `MGET` over all keys + fully serial processing | 🟢 | 2–4h | **DONE (4b).** The real cliff was `KEYS` (blocks the whole server) → replaced with `SCAN` cursor (benefits all callers). MGET chunked (500); per-device processing now bounded-concurrent (8) + per-registration tolerant. Added PushMetrics scanSize/duration/dedup. 450-device batching test passes; existing APNS tests green. Load harness: `Scripts/apns-load-test.sh`. |
| B6 | **Server: no request timeouts on ESPN fetches** | 🟢 | 1–2h | **DONE (4a).** `app.http.client.configuration.timeout` (connect 5s, read 20s) bounds all Vapor-client traffic (ESPN + enrichment); a stall now surfaces as a transport error → existing per-league cooldown + retry. |
| B7 | **Server: enrichment jobs fail-whole** | 🟢 | 1–2h | **DONE (4a) — corrected diagnosis.** Golf + Injuries already do partial-success. F1 fetchers are non-throwing (return empty), so the real bug was **clobbering** last-known-good Redis with empty. Now guards circuit/standings writes; stamps lastUpdate only on a successful refresh. Unit-tested. |
| B8 | **Duplicate live-activity pushes (prod + dev both emitting)** | 🟡 | — | **DECISION: fine for v1.** Single Hetzner prod instance. Real risk isn't replicas — it's prod + a local/dev server both pushing. Already isolated: dev uses sandbox APNS + debug-prefixed Redis keys, so it can't touch prod users' registrations. **Guardrail: never run a dev instance with prod APNS env + non-prefixed keyspace.** Revisit JobLock validation only if scaling to multiple prod replicas. |

## C. Medium (S2) — UX / hygiene, fix most for "polished"

| ID | Item | Status | Effort | Notes |
|----|------|--------|--------|-------|
| C1 | **Sentry DSN → Constants + lower trace rate** (audit #01) | 🟢 | 10m | **DONE (Batch 2).** DSN now `Constants.sentryDSN` (gitignored) via `ci_post_clone.sh`; trace 0.3→0.05; empty-DSN guard logs instead of silently disabling; CI warns if `$SENTRY_DSN` unset. ⚠️ **Set `SENTRY_DSN` in Xcode Cloud before next archive.** No DSN left in tracked source. |
| C2 | **Sentry PII `beforeSend` + mask device-token logs** (audit #06, #10) | 🟢 | 20m | **DONE (Batch 2).** Added `beforeSend` breadcrumb redaction to both blocks; masked token logs (prefix-12) and payload logs (eventID only) at AppDelegate 74/92/148/197/214. |
| C10 | **Ad-tracking posture: orphan ATT string + no EEA consent** | 🟡 | varies | **Partly done (3a):** removed the orphan `NSUserTrackingUsageDescription` (no ATT requested → consistent with `NSPrivacyTracking=false`). **Remaining (ops, not code):** AdMob in the EEA without a Google-certified CMP is an AdMob *policy* gap; address before serving EEA traffic. If you later want personalized ads, add ATT + a CMP. |
| C3 | **Offline UX** — no real offline indicator, only a stale-data banner | 🟢 | 2–4h | **DONE (3c).** Wired the (previously dead) `.failed` path via a race-free task-group result; added observable `isOffline` (from NWPathMonitor) + `lastSuccessfulFetch`. Banner now shows "You're offline" vs "Showing data from {real ago}", Retry disabled offline; full-screen offline placeholder when no cached data. **Needs an airplane-mode device pass to confirm feel.** |
| C4 | **Ad cadence decision** — currently max 3/screen, ~1 per 5 games | 🟡 | June 10 | *Dial-back implemented (June 10):* 1 per 8–10 games (`adaptiveInterval` 8/10), max 2/screen, lists under 8 rows show no ads (`FeedAdPlanner minimumRows: 8`), strategy `everyNGames(n: 9)`. Pinned by `ProFeatureGatingTests`. Remaining: confirm feel on device in Phase 3 (incl. whether GameDetail keeps its single ad). |
| C5 | **Tailscale IP / local-server paths gating** (audit #11) | 🟢 | 15m | **DONE (3b).** `tailscaleHost` + `.local`/`.dev` resolution in `baseURL()`/`rootURL()`/`refreshEnvironment()` gated `#if DEBUG`; Release always returns prod and the IP isn't compiled in. Verify with `strings` on a Release archive (checklist). |
| ~~C6~~ → B9 | **App Attest implementation** — `verifyAppleAttestation`/`verifyAppleAssertion` stubs | ⚪️ | days | **DECISION REVERSED (June 9): ship v1 WITHOUT App Attest → moved to v1.1.** Verified the stubs are fail-closed and not wired to any route, so nothing breaks. Build client attestation + server verify end-to-end in v1.1 (Batch 5 becomes a v1.1 track). |
| C7 | **Push-to-start `X-Install-ID` client migration** — server moved to install-keyed storage | 🟢 | — | **Verified June 9:** client sends `X-Install-ID` on all 4 registration paths in `NetworkHandler.swift` (517/540/667/687). Server deployed with install-keyed storage same day — client+server release coordinated. |
| C8 | **WebSocket reconnect untested** — `GameViewModel.reconnectWebSocketOnly()` backoff | 🟢 | 1–2h | **DONE (3b).** Extracted pure `WebSocketBackoff.delaySeconds(forAttempt:)` + `WebSocketBackoffTests` pinning the quadratic-capped-at-60 curve. (Offline→online reconnect itself is covered by the C3 path-monitor pass.) |

## D. Low (S3) — defer to v1.1 unless cheap

| ID | Item | Status | Effort | Notes |
|----|------|--------|--------|-------|
| D1 | Cleanup ngrok URL in xcscheme (audit #13) | 🟢 | 2m | **DONE (Batch 1).** Both ngrok env vars removed; also disabled `mock-subscribed` in the shared scheme so the free/ad UX is testable in Phase 3. |
| D2 | Standings TTL 90→30d (audit #08) | ⚪️ | — | **Confirmed June 9:** `StandingsSnapshotJob` scheduling is commented out in `configure.swift` → moot. Closed. |
| D3 | "Reset Suggestions" button for EngagementTracker | 🔴 | 30m | Nice privacy affordance; optional. |
| D4 | Skeleton loaders instead of spinners | 🔴 | 2–4h | Polish; v1.1 OK. |
| D5 | Commented-out debug prints `GameViewModel:804–810` | 🟢 | 5m | **DONE (Batch 1).** Removed. |
| C9 | **Developer settings section visible to ALL release users** — `DeveloperSettingsSection` "Debug Mode" toggle has no build guard | 🟢 | 30m | **DONE (3a).** Gated the whole section: rendered only in `#if DEBUG` or TestFlight (`isTestFlight`). App Store production users no longer see Debug Mode / server-env switcher / diagnostics. |

---

## E. Test coverage gaps (drives Phase 3 confidence)

**Server (highest-value gaps):**
- `ESPNFetchJob` schedule-merge (the 9-path team-matching fallback) — **untested, hot path.** Add at least a smoke test (N schedule games + M ESPN results → expected merge).
- `DBUpdateJob` (~600 LOC SQLite sync) — untested.
- Routes layer (`/plays` three-tier lookup, `/ws` streaming, `/sport/:sport`) — untested.
- `ContentState.stableHash()` determinism — no test pinning the hash format (dedup depends on it).

**Client (already decent — matcher, gating, model tests exist):**
- WebSocket reconnect/backoff (C8).
- Offline→online transition + stale-cache display.
- Push-to-start registration handshake (currently server-side only).

## F. Server load & resilience summary

Solid: rate limiting (done), per-job concurrency caps (6), dedup via atomic `SET NX`, TTL backstops, stale-cache pruning.

Risky (→ B5/B6/B7/B8): unbounded APNS cardinality, missing network timeouts, fail-whole enrichment, unvalidated multi-replica. No prod metrics yet (`/api/admin/metrics` returns placeholder zeros) — consider wiring real counters before/just-after launch for observability.

## G. Ad intrusiveness — decision framework (resolve in Phase 3)

Current: `AdConfiguration` `maxAdsPerScreen=3`, `everyNGames(n:5)` (adaptive 3–7); placements in DayPage, BrowsePage (2/sport), GameDetail (1). Pro removes all ads (tested).

Plan: **feel it on a real device with realistic game counts** (a busy NBA+NFL Saturday = long lists = most ads). Then decide between:
- (a) Keep — free tier should feel ads; revenue matters.
- (b) Dial back — e.g. `everyNGames(n:8–10)`, `maxAdsPerScreen=2`, no ad in GameDetail.
- (c) Hybrid — looser cadence on long lists, none on short ones.

Decision recorded here once made: _TBD_.

---

## Execution phases

- **Phase 0 — Consolidate (this doc).** ✅ Done. Single ranked register.
- **Phase 1 — Triage sign-off.** You approve the cut line (which S2s are in/out). Gate before any edits.
- **Phase 2 — Fix in batches** (each proposed in plan mode, then approved):
  - **Batch 1 — Blockers, fast & mechanical:** A2, A4(verify), B2, B3, B4, C1, C5, D1, D5. (Low-risk, high-value; mostly minutes each.)
  - **Batch 2 — Privacy/compliance:** A1, A3, C2, C6 decision, D3. (Manifest + ASC labels + Sentry hygiene.)
  - **Batch 3 — Client crashes & UX:** B1, C3, C8, ad decision C4/§G.
  - **Batch 4 — Server resilience:** B5, B6, B7, + critical tests from §E. (B8 deferred — see decision.)
  - **Batch 5 — App Attest (B9):** client attestation + server verification. Largest batch; own track.
- **Phase 3 — Verification:**
  - Server: add §E smoke tests; load test staging with synthetic 5–10k APNS keys + N live games to find/confirm B5/B6 cliffs; 2-replica JobLock validation (B8).
  - App: run suite + snapshot tests (Xcode MCP); manual device passes — offline→online, follow/unfollow live activity, Pro toggle removes ads, ad cadence feel.
  - Tools: admin stays gated (Caddy), CI green.
- **Phase 4 — Submission:** TestFlight beta round, screenshots, metadata, final Release-scheme secrets/entitlements check, App Privacy labels live.

## Decisions (resolved)
1. ✅ **Single Hetzner instance at launch.** B8 deferred to S2 (see row). Guardrail: keep dev on sandbox APNS + debug keys.
2. ✅ ~~App Attest implemented for v1~~ → **REVERSED June 9: v1 ships without App Attest; implement in v1.1.** Stubs are fail-closed and unwired, so no risk in the meantime.
3. ✅ **EEA ads (C10)**: handled via App Store Connect update (user-owned web-console step) — declare/configure EU ad serving + CMP posture in ASC before serving EEA traffic.

## Open decisions (still need input)
3. **Ad cadence (C4/§G)** — dial-back option (b) implemented June 10 (1 per 8–10, max 2/screen); confirm feel on device in Phase 3.
4. **Which S2s are in the cut line** vs pushed to v1.1 — confirm during/after Batch 1.

---

## ✅ Final Submission Checklist (manual / human steps)

Steps that can't be done in code — do these before hitting "Submit for Review".

### Xcode Cloud environment variables (set before next archive)
- [ ] **`SENTRY_DSN`** — required, else prod ships with crash reporting OFF (build logs a warning). Value: the existing Sentry ingest URL. *(Batch 2 / C1)*
- [ ] **`ADMOB_APP_ID`** and **`ADMOB_NATIVE_AD_UNIT_ID`** — must be the real production values so the generated `Constants.swift` serves real ads, not Google test ads. *(A4)*
- [ ] Confirm `REVENUECAT_API_KEY` and `SPORTSCAL_API_KEY` are set (production values).

### Archive-time verification
- [ ] `codesign -d --entitlements - Scoreline.app` shows **`aps-environment: production`**. *(A2)*
- [ ] Archive ▸ **Generate Privacy Report** renders the manifest + SDK manifests with no errors. *(A1)*
- [ ] Build a **watch-scheme archive** and confirm `PrivacyInfo.xcprivacy` is in the watch app + watch-widgets bundles (iOS build can't verify these). *(A1)*
- [ ] Confirm `Info.plist` `GADApplicationIdentifier` is the **real** AdMob app ID. *(A4)*

### App Store Connect — App Privacy labels *(A3, must match the manifest)*
- [ ] **Identifiers → Device ID**: Collected · Not linked · Not tracking · App Functionality.
- [ ] **Other Data** (favorites / event IDs): Collected · Not linked · Not tracking · App Functionality.
- [ ] **Diagnostics → Crash Data + Performance Data** (Sentry): Collected · Not linked · App Functionality.
- [ ] **Purchases** (RevenueCat): Collected · Linked · App Functionality.
- [ ] Do **NOT** list EngagementTracker (on-device → not collected).
- [ ] "Used to Track You" = **none** (contingent on C10 ad-tracking decision).
- [ ] Privacy-policy URL is present and live.

### Decisions to resolve before submit
- [x] **C10 — ad tracking**: orphan `NSUserTrackingUsageDescription` already removed (3a). EEA/AdMob: handle via App Store Connect update (EU DSA / ad-serving declaration + CMP posture) — manual ASC step before serving EEA traffic.
- [ ] **C4 — ad cadence**: dial-back implemented (June 10); confirm after on-device feel pass.
- [x] **B9 — App Attest**: deferred to v1.1 (June 9 decision).

### Test gates
- [ ] Run full `SportsCalTests` suite green (the MCP runner couldn't auto-launch — run in CI or Xcode; re-confirmed June 9: `RunAllTests` returns 133 "not run").
- [x] Server unit tests green (June 9): all 13 unit suites pass (~115 tests incl. `WorldCupEnrichmentTests` 8/8). Note: `AppTests.AppTests` + `ScheduleCountTests/testLeagueGameCounts` are live-data integration tests that need a populated prod-like Redis — they fail/SIGTRAP on dev machines and are excluded from the local gate.
- [ ] Nightly push-smoke green.

### Deploy log
- **June 9, 2026** — `main` fast-forwarded to `cleanup-staging` (96 release-prep commits) + World Cup commit `d1767c1`; both pushed to origin. Hetzner redeployed from a clean worktree (deploy.sh rsyncs the working tree — never deploy from a dirty checkout). First deploy (`6cc5b8b`) verified: `/ping` pong, schedules 200. Second deploy (`d1767c1`, World Cup routes + enrichment job) followed immediately; `WorldCupEnrichmentJob` first run clean (rounds=0/scorers=0 expected pre-tournament).
- **June 9, 2026 (late)** — Third deploy `1f25981`: **prod was serving 0 MLB and 0 NFL games** (TheSportsDB labels those seasons single-year; the job requested split-year). Caught by `testStableLeagueGameCounts` once the iOS suite was repaired. Fixed via `Leagues.sportsDBSingleYearSeason`; after deploy + `POST /api/admin/redis/refresh`: MLB 5078, NFL 655 events. All 8 leagues populated.

### iOS suite status (June 9)
106/133 pass, 1 skipped (DayPage snapshot — time-relative pixels, record-on-demand via `RECORD_SNAPSHOTS=1`), 26 fail **for environmental reasons only**: 25 × StoreKitIntegrationTests (Xcode 26.3 RC + iOS 18.6 sim never serves `SKTestSession` products — retry added; run on stable Xcode/CI; RevenueCat + SubscriptionManager suites pass) and 1 × testStableLeagueGameCounts (points at the dev server; passes once dev has the season fix).

> Code-side status lives in the tables above (🟢 done). This checklist is only the out-of-band steps.
