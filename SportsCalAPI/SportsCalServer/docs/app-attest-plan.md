# App Attest → JWT — Implementation Plan (3.2)

Goal: replace the single extractable shared `X-API-Key` with per-device
attested auth. A real Secure Enclave key on a real install becomes the only
thing that can mint a short-lived JWT; write routes require that JWT.

**Status: Phase 0 and Phase 1 are implemented.** Attestation and assertion
verification are real, the routes are live, and the 3.2 client sends a bearer
token alongside the shared key. Phases 2–3 (requiring the JWT) are deliberately
not started — they can only begin once 3.2 adoption is high enough.

## What is implemented

**Server**
- `Sources/App/Attest/CBOR.swift` — strict, hand-rolled CBOR decoder for the
  App Attest subset. Rejects indefinite lengths, tags, floats, duplicate map
  keys, trailing bytes, and deep nesting. 19 unit tests.
- `Sources/App/Attest/AppAttestVerifier.swift` — the real crypto:
  - attestation: CBOR decode → `fmt == apple-appattest` → X.509 chain validated
    to Apple's root → `nonce == SHA256(authData || clientDataHash)` against the
    leaf's `1.2.840.113635.100.8.2` extension → `SHA256(pubKey) == keyID` →
    rpIdHash → counter 0 → AAGUID → credentialId. Returns the attested key.
  - assertion: ECDSA-P256 over `SHA256(authenticatorData || clientDataHash)`,
    rpIdHash, and a strictly-increasing counter.
- `Sources/App/Attest/AppleAppAttestRoot.swift` — Apple App Attestation Root CA
  pinned as source (fingerprint asserted in tests).
- `AttestMiddleware.swift` — `AttestController` (`/attest/challenge|verify|
  refresh`, plus `/attest/dev` off production), rate-limited at 30/min;
  `EitherAuthMiddleware` (JWT **or** API key); `app.appAttest` configuration.
- `configure.swift` — HS256 signer from `JWT_SIGNING_KEY` (min 32 bytes),
  verifier from `APP_ATTEST_APP_ID`. Both warn-and-degrade if unset.
- `routes.swift` — `AttestController` registered at top level; `v2025` and
  legacy groups moved from `APIKeyMiddleware` to `EitherAuthMiddleware`.
- `Attest/AppAttestReceipt.swift` + `Attest/DeviceCheckClient.swift` — fraud-risk
  metrics. After a successful attestation the receipt is exchanged with Apple's
  attestationData endpoint for one carrying field 17, the count of attested keys
  that device produced in 30 days; it lands in `attest:key:<keyID>` alongside
  the receipt, its not-before and expiry. Runs detached — Apple being slow or
  down must never block a user's first launch — and every failure is logged and
  swallowed. Currently recorded and logged only, not enforced.

**iOS**
- `Attestation.swift` added to the SportsCal (iOS) and SportsWidgetExtension
  targets (it was on disk but in no target, so it had never compiled).
- `NetworkHandler.authenticatedRequest` is now `async` and stamps
  `Authorization: Bearer <jwt>` alongside `X-API-Key`, main app only.
- `com.apple.developer.devicecheck.appattest-environment` added to both
  entitlements files (`development` / `production`).

## Decisions taken

- **Signer:** HS256. One server both mints and verifies; no public key to
  distribute.
- **No-App-Attest devices** (old hardware, MDM, simulator against prod): fall
  back to the shared API key. The security claim for 3.2 is "most traffic is
  attested", not "all traffic is".
- **Watch:** stays on the shared API key. watchOS has no `DCAppAttestService`.
- **Widgets:** stay on the shared API key. An extension has a different bundle
  identifier, so a token minted there would fail the server's rpId check.
- **CBOR:** hand-rolled rather than a third-party package — it parses
  unauthenticated bytes, so a readable ~150 lines beats a dependency.

## Deployment prerequisites

**All of these are now done** (2026-08-27) — recorded here because the server
degrades quietly if any regresses. Check the boot logs after deploying.

1. `JWT_SIGNING_KEY` in the prod environment. Generate with
   `openssl rand -base64 48`. Absent → attest routes cannot mint, clients stay
   on the shared key.
2. `APP_ATTEST_APP_ID=9GDU5ZNHX7.com.KomodoLLC.SportsCal`. Absent →
   verification disabled entirely.
3. `DEVICECHECK_KEY_ID` plus the key mounted at `DEVICECHECK_KEY_PATH`
   (`docker-compose.yml` mounts `./AuthKey_DeviceCheck.p8`). Optional — absent,
   only the fraud-risk metric is lost.
4. **App Attest capability on the App ID.** Not settable through the App Store
   Connect API — `APP_ATTEST` is absent from the public `capabilityType` enum.
   Xcode's automatic signing registers it: a signed build
   (`-allowProvisioningUpdates`) adds the capability and regenerates the profile.

## Remaining work

- **401 handling (blocks phase 2).** `authenticatedRequest` treats the bearer
  token as best-effort and there is no reset-and-retry on 401. That is correct
  while dual auth is on, and must be built before any route requires JWT.
- **Two client paths are still shared-key only** (`NetworkHandler.apiKeyRequest`),
  because they are built synchronously and can't await a token:
  - the `/ws` WebSocket handshake — URLSession's WS client can't easily carry an
    `Authorization` header anyway, so this needs a query param or first-frame
    auth;
  - `pushToStartRegistrationRequest`, which is a **write** route and therefore
    has to be moved onto the async builder before phase 2 flips `rl:write` to
    JWT-only.
- **Refresh job for the risk metric.** The metric is fetched once, at
  attestation. Apple's receipts expire (field 21) and can only be refreshed
  after their not-before date (field 19); a periodic job should walk
  `attest:key:*` and refresh those in-window. Without it the metric ages out
  and stops updating.
- **Nothing acts on the metric yet.** It is logged and stored. Apple's guidance
  is to tune a threshold against observed traffic before enforcing, so decide
  what a "too many keys" response should be once there is baseline data.
- **Device testing.** The verifiers are tested against synthesized vectors
  anchored at a test root (Apple publishes no sample vectors, and a real blob
  needs physical hardware). Still to confirm on TestFlight: fresh install →
  attest → refresh, restore-from-backup → `invalidKey` → re-attest, and that
  `/attest/dev` 404s in production.

## Rollout sequencing — the existing-user constraint

The server cannot require JWT on a route until every shipped client sends one.

- **Phase 0 — done.** Verifiers implemented and unit-tested; controller and
  signer registered.
- **Phase 1 — done (ships with 3.2).** Client sends both credentials; server
  accepts either via `EitherAuthMiddleware`.
- **Phase 2 — after 3.2 adoption ≥ ~95%.** Flip the `rl:write` group to
  `JWTMiddleware`. Requires the 401 retry above. Reads stay dual-auth longer.
- **Phase 3.** Retire the shared key for iOS; keep it for the watch, or migrate
  the watch to proxy tokens.

Ties into the multi-hash key rotation (see `project_security_audit_2026_07`):
the shared key stays valid throughout, so phases 1–2 are non-breaking.
