# App Attest → JWT — Implementation Plan (3.2)

Goal: replace the single extractable shared `X-API-Key` with per-device
attested auth. A real Secure Enclave key on a real install becomes the only
thing that can mint a short-lived JWT; write routes require that JWT.

**Status: every phase is implemented; phases 2–3 are switched off.** All the
machinery exists and is tested — advancing the rollout is a deployment decision
(`AUTH_POLICY`, below) rather than a code change. It ships set to `dual`, which
is byte-for-byte the pre-App-Attest behaviour, because the server cannot demand
a JWT until effectively every installed client sends one and 3.2 has not
shipped yet.

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
- `Tests/AppTests/Integration/AttestControllerTests.swift` — the stateful layer:
  `EitherAuthMiddleware` accept/fall-through/reject plus the guarantee that a
  handler error is never replayed down the API-key path; challenge single-use
  (GETDEL) and TTL; counter compare-and-set monotonicity; the re-attest header
  contract; `/attest/dev` unregistered off production. 17 tests — the Redis ones
  skip when no Redis is reachable.
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
That constraint is now expressed as a single env var rather than a code edit:

| `AUTH_POLICY` | Reads | Writes | When |
|---|---|---|---|
| `dual` (default) | JWT or API key | JWT or API key | Phase 1 — ships with 3.2 |
| `jwt-writes` | JWT or API key | **JWT** (`ios`/`dev` only) | Phase 2 — at ~95% 3.2 adoption |
| `jwt-strict` | **JWT** | **JWT** (`ios`/`dev` only) | Phase 3 — once widget + watch relay is in the field |

Unset or unrecognized resolves to `dual`, and `jwt-writes`/`jwt-strict` refuse
to boot without `JWT_SIGNING_KEY`. Both defaults point the same way: a mistake
in the deploy environment must not lock every installed client out of the API.

- **Phase 0 — done.** Verifiers implemented and unit-tested.
- **Phase 1 — done (ships with 3.2).** Client sends both credentials; server
  accepts either.
- **Phase 2 — code done, awaiting adoption.** Set `AUTH_POLICY=jwt-writes`.
  Safe for the widget and watch: every caller of the four write routes
  (`liveActivity` POST/DELETE, `pushToStart/register` POST/DELETE) is in the iOS
  app — Live Activity push-token observation and the foreground/BGAppRefresh
  re-register — and the app is the only target that can attest.
- **Phase 3 — code done, awaiting phase 2 + adoption of the relay.** Set
  `AUTH_POLICY=jwt-strict`. Requires the widget and watch to be carrying tokens,
  so it must not precede a release containing the relay described below.

Ties into the multi-hash key rotation (see `project_security_audit_2026_07`):
the shared key stays valid throughout, so phases 1–2 are non-breaking.

## How non-attesting clients get a token

App Attest attests `<TEAM_ID>.<BUNDLE_ID>`, so only the main app
(`com.KomodoLLC.SportsCal`) can attest as itself. The other two targets are
given tokens rather than minting them:

- **Widget extension** (`…SportsCal.SportsWidget`) reads the app's token from
  the App Group (`group.Komodo.SportsCal`, `SharedAttestToken`). It is genuinely
  the same principal, and it avoids a Secure Enclave round trip inside a widget
  refresh's time budget. App Group defaults rather than the Keychain: sharing
  Keychain items needs a `keychain-access-groups` entitlement the widget lacks,
  and adding one churns provisioning.
- **Watch** (`…SportsCal.watchkitapp`) has no `DCAppAttestService` at all. The
  phone calls `POST /attest/proxy` with its own token and relays the result over
  the existing WatchConnectivity application context (`WatchRelayedToken`). The
  proxy token carries `plt: "ios-proxy-watch"`, inherits the phone's `sub` so
  revoking the phone's key cascades, and is refused by every write route and by
  `/attest/proxy` itself — a watch cannot bootstrap further credentials.

Both stores treat "expired" and "absent" identically, because neither holder can
refresh: a token that dies in flight fails the request, where no token at all
falls back to the shared key.

## 401 handling

Two distinct 401s, distinguished by the `X-Attest-Action: re-attest` header
(`AttestAction`):

- **with the header** — the server holds no public key for this keyID. The
  client discards its Secure Enclave key and attests afresh.
- **without it** — the assertion was rejected (bad signature, replayed counter),
  or a session token was refused. `attestKey` is rate-limited by Apple, so the
  client must *not* burn a key here.

On the protected routes, `NetworkHandler.performAuthorized` retries once on 401
after calling `Attestation.invalidateCachedToken()` — which drops the session
token but keeps the key, so the retry costs one cheap assertion refresh. Only
the main app retries; the widget and watch hold relayed tokens they cannot
refresh.

The live WebSocket carries the token as an `Authorization` header on the
handshake `URLRequest` (which is how `X-API-Key` has always travelled there) —
deliberately not a query parameter, which would put a live credential into every
access log it passes. It reads the last published token synchronously, because
its three call sites are synchronous and `GameViewModel` compiles into the
widget target too; a socket opened with a stale token is closed and retried by
the existing reconnect path.

## Keyspace maintenance

`AppAttestMaintenanceJob` runs hourly at :55 behind a `JobLock`, and walks
`attest:key:*` once to do two things:

- **Refresh due receipts.** Apple's receipts can only be redeemed inside
  `[notBefore (field 19), expiry (field 21))`; outside it a refresh is a wasted
  round trip or a guaranteed failure. Capped at 200 Apple calls per tick —
  whatever is missed this hour is picked up the next. The environment is read
  from the record, because a receipt is only redeemable against the host
  matching the client build that produced it and the attestation blob is long
  gone by then.
- **Reap abandoned records.** `lastUsedAt` is written on every successful
  assertion refresh, so an install that is genuinely gone is identifiable.
  Records untouched for 180 days are deleted; the owner of a reaped key
  re-attests silently on next launch (which is exactly why the `X-Attest-Action`
  contract had to land first). Deliberately generous, and a record with no dates
  at all is *kept* — reaping a live key is the only irreversible mistake here.

That bounds the growth the keyspace previously had no answer for.

## The risk metric

Collected at attestation and refreshed by the job above; still **not enforced**.
The blocker was never the plumbing, it was that a threshold picked without a
distribution is a guess, and a wrong guess locks real users out.

`AppAttestRisk` now emits a bucketed `attest.risk_metric` counter (0 / 1 / 2 /
3-5 / 6-10 / 11-25 / 26+, tagged by environment) into the same per-day Redis
counters the admin dashboard reads. Buckets rather than raw values so the
keyspace stays bounded and the tail is readable. Once those numbers show where
normal ends, enforcement is a decision rather than a guess — and it should
follow the `AUTH_POLICY` pattern: implemented, off by default, advanced
deliberately.
- **Device testing.** The verifiers are tested against synthesized vectors
  anchored at a test root (Apple publishes no sample vectors, and a real blob
  needs physical hardware). Still to confirm on TestFlight: fresh install →
  attest → refresh, restore-from-backup → `invalidKey` → re-attest,
  `/attest/dev` 404ing in production, and the watch relay arriving over a real
  pairing.
- **Phase 2/3 flip is a judgement call on adoption.** Check 3.2 share before
  setting `AUTH_POLICY`; there is no automatic gate.
