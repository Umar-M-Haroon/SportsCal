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
| A1 | **Privacy manifest** `PrivacyInfo.xcprivacy` (audit #03) | 🔴 | 1–2h | No file exists. Apple *will reject*. Need app-level manifest covering Sentry/AdMob/RevenueCat/UserDefaults + verify each SDK ships its own. |
| A2 | **Release APS entitlement** = `development` (audit #04) | 🟢 | 2m | **DONE (Batch 1).** Release entitlements now `production`; Debug left `development`. Verify at archive time via `codesign -d --entitlements -`. |
| A3 | **App Privacy nutrition labels** in App Store Connect (audit #12) | 🔴 | 30m | Must match manifest: Product Interaction (EngagementTracker), Device ID (AdMob), Purchase History (RevenueCat), Crash/Perf (Sentry). Plus privacy-policy URL. |
| A4 | **Ad unit IDs**: confirm Release uses real `Constants.nativeAdUnitID`, not Google test unit | 🟡 | 30m | **Code verified ✓** — `NativeAdManager.defaultAdUnitID` already guards DEBUG→test / Release→`Constants.nativeAdUnitID`. Remaining: confirm Xcode Cloud `ADMOB_*` env vars set + Info.plist `GADApplicationIdentifier` is the real app ID + device check in Phase 3. |

## B. High (S1) — crashes, legal, load failure

| ID | Item | Status | Effort | Notes |
|----|------|--------|--------|-------|
| B1 | **Force-unwraps in view code** — `GameScoreView.swift:81` (`parts.last!`), `F1GapRibbonView.swift:157` | 🔴 | 30m | Crash on single-word names / malformed F1 gap strings. Guard both. |
| B2 | **ESPN HTTP→HTTPS** on server (audit #02) — 6× `http://site.api.espn.com` in `ESPNNetworking.swift` | 🟢 | 5m | **DONE (Batch 1).** All 6 → HTTPS; server builds clean. |
| B3 | **Remove ESPN branding** from admin UI/source (audit #05) | 🟢 | 10m | **DONE (Batch 1).** `LiveGames.ts` 80/176/212 genericized; admin builds clean. Endpoint name `live-espn` left (optional rename needs server route change). |
| B4 | **Gate `mock-subscribed` behind `#if DEBUG`** (audit #07) — `SubscriptionManager.swift:34,75` | 🟢 | 5m | **DONE (Batch 1).** Gated env-var path AND the bigger leak: the **Settings "Mock Pro" toggle** (reachable via user-toggleable Debug Mode) + `setMockPro` body now `#if DEBUG`. iOS builds clean. |
| B5 | **Server: unbounded APNS scan+MGET** — `APNSJob` does `SCAN APNS-*` then one `MGET` over all keys every minute | 🔴 | 2–4h | Latency cliff at ~10k devices. Batch MGET (chunks of ~100), bound concurrency. Validate with load test (Phase 3). |
| B6 | **Server: no request timeouts on ESPN fetches** | 🔴 | 1–2h | Hanging ESPN endpoint can block a job past its 1-min tick. Add explicit client timeouts + a circuit-breaker/backoff for repeated failures. |
| B7 | **Server: enrichment jobs fail-whole** (F1/Golf/Injuries use `async let`; any sub-task failure aborts the whole update) | 🔴 | 1–2h | One slow API kills the hourly update; repeats next tick. Make partial-success tolerant. |
| B8 | **Duplicate live-activity pushes (prod + dev both emitting)** | 🟡 | — | **DECISION: fine for v1.** Single Hetzner prod instance. Real risk isn't replicas — it's prod + a local/dev server both pushing. Already isolated: dev uses sandbox APNS + debug-prefixed Redis keys, so it can't touch prod users' registrations. **Guardrail: never run a dev instance with prod APNS env + non-prefixed keyspace.** Revisit JobLock validation only if scaling to multiple prod replicas. |

## C. Medium (S2) — UX / hygiene, fix most for "polished"

| ID | Item | Status | Effort | Notes |
|----|------|--------|--------|-------|
| C1 | **Sentry DSN → Constants + lower trace rate** (audit #01) | 🔴 | 10m | DSN hardcoded; trace rate 0.3 → 0.05. (April marked "critical"; a DSN is a write-only ingest URL — real severity is hygiene/cost, hence S2.) |
| C2 | **Sentry PII `beforeSend` + mask device-token logs** (audit #06, #10) | 🔴 | 20m | Tokens/payloads logged → Sentry breadcrumbs. Mask in `AppDelegate` (lines 74/92/148) + add `beforeSend`. |
| C3 | **Offline UX** — no real offline indicator, only a stale-data banner | 🔴 | 2–4h | Add explicit offline state + retry affordance. Part of the UX pass. |
| C4 | **Ad cadence decision** — currently max 3/screen, ~1 per 5 games | 🔴 | TBD | *Decide on-device in Phase 3.* Candidate dial-back: 1 per 8–10 games, max 2/screen. See §G. |
| C5 | **Tailscale IP / local-server paths gating** (audit #11) | 🟡 | 15m | IP `100.68.255.93` still in `NetworkHandler:237`; some `#if DEBUG` present. Audit that all dev hosts + ATS exception are Debug-only; `strings` the Release binary to confirm. |
| ~~C6~~ → B9 | **App Attest implementation** — `verifyAppleAttestation`/`verifyAppleAssertion` stubs | 🔴 | days | **DECISION: implement for v1 → promoted to S1, own batch (Batch 5).** Real hardware attestation against API abuse/scraping. First confirm stubs aren't currently wired (so nothing breaks pre-implementation), then build verification end-to-end (client attestation + server verify). Scope: days. |
| C7 | **Push-to-start `X-Install-ID` client migration** — server moved to install-keyed storage | 🟡 | — | Ensure the iOS build that ships sends `X-Install-ID`; old `PushToStart-{token}` keys won't migrate. Coordinate client+server release. |
| C8 | **WebSocket reconnect untested** — `GameViewModel.reconnectWebSocketOnly()` backoff | 🔴 | 1–2h | Add a test + a manual offline→online device pass. |

## D. Low (S3) — defer to v1.1 unless cheap

| ID | Item | Status | Effort | Notes |
|----|------|--------|--------|-------|
| D1 | Cleanup ngrok URL in xcscheme (audit #13) | 🟢 | 2m | **DONE (Batch 1).** Both ngrok env vars removed; also disabled `mock-subscribed` in the shared scheme so the free/ad UX is testable in Phase 3. |
| D2 | Standings TTL 90→30d (audit #08) | ⚪️ | — | `StandingsSnapshotJob` is disabled → likely moot. Confirm & close. |
| D3 | "Reset Suggestions" button for EngagementTracker | 🔴 | 30m | Nice privacy affordance; optional. |
| D4 | Skeleton loaders instead of spinners | 🔴 | 2–4h | Polish; v1.1 OK. |
| D5 | Commented-out debug prints `GameViewModel:804–810` | 🟢 | 5m | **DONE (Batch 1).** Removed. |
| C9 | **Developer settings section visible to ALL release users** — `DeveloperSettingsSection` "Debug Mode" toggle has no build guard | 🔴 | 30m | *New finding (Batch 1).* Any user can enable Debug Mode → exposes server-env switcher, cache dump, diagnostics (Mock Pro now gated). Not a Pro leak anymore, but a polished release shouldn't surface dev tools to everyone. Gate the section behind `#if DEBUG \|\| isTestFlight`. Candidate for Batch 3. |

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
2. ✅ **App Attest implemented for v1.** Promoted to B9 / Batch 5.

## Open decisions (still need input)
3. **Ad cadence (C4/§G)** — decide after device pass in Phase 3 (default plan).
4. **Which S2s are in the cut line** vs pushed to v1.1 — confirm during/after Batch 1.
