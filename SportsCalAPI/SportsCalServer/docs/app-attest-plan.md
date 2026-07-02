# App Attest → JWT — Implementation Plan (3.2)

Goal: replace the single extractable shared `X-API-Key` with per-device
attested auth. A real Secure Enclave key on a real install becomes the only
thing that can mint a short-lived JWT; write routes require that JWT.

Status going in: the scaffolding is ~80% built. This plan fills the gaps and,
critically, sequences the rollout so **existing users are never locked out**.

## What already exists (do not rewrite)

**Server** (`Sources/App/AttestMiddleware.swift`)
- `SportsCalJWT` payload, `JWTMiddleware` (bearer verify), `AttestController`
  with `/attest/challenge`, `/attest/verify`, `/attest/refresh`, challenge
  Redis storage (single-use, 5-min TTL), keyID→publicKey+counter storage,
  `mintToken` (15-min JWT).
- **Stubbed:** `verifyAppleAttestation(...)` and `verifyAppleAssertion(...)`
  both `throw .notImplemented`.

**iOS** (`SportsCal/Shared/Attestation.swift`)
- `Attestation` actor: `getValidJWT()` (serialized refresh via `inFlight`),
  full-attest path, assertion-refresh path, Keychain storage of keyID+JWT,
  simulator/unsupported fallback to `fetchDevToken()`.
- Wire types match the server DTOs.

## Gaps to close

### Server
1. **Implement `verifyAppleAttestation`** — the load-bearing crypto. Steps
   (Apple's "Validating Apps That Connect to Your Server"):
   1. base64-decode → CBOR-decode `{ fmt, attStmt, authData }` (`fmt` must be
      `apple-appattest`).
   2. `attStmt.x5c` = cert chain. Verify it chains to **Apple App Attestation
      Root CA** (pin the root PEM under `Sources/App/Resources/`; load at boot).
   3. `clientDataHash = SHA256(challenge.utf8 || keyID-decoded)` — must match
      exactly how the client computes it (`Attestation.swift:105`).
   4. `nonce = SHA256(authData || clientDataHash)`; assert it equals the leaf
      cert's nonce extension (OID `1.2.840.113635.100.8.2`, a DER-wrapped octet
      string).
   5. Extract the P-256 public key from `authData`'s credential data; assert
      `SHA256(pubKey) == keyID bytes`.
   6. `rpIdHash` (first 32 bytes of `authData`) must equal
      `SHA256("9GDU5ZNHX7.com.KomodoLLC.SportsCal")`.
   7. counter (bytes 33..37) == 0; `aaguid` == `appattest␀␀␀␀␀␀␀` in prod or
      `appattestdevelop` in dev — gate on `app.environment`.
   - Return the extracted public key (stored for future assertions).
2. **Implement `verifyAppleAssertion`** — CBOR `{ signature, authenticatorData }`;
   `nonce = SHA256(authenticatorData || SHA256(challenge.utf8))`; verify
   ECDSA-P256 signature over `nonce` with the stored pubkey; assert
   `counter > previousCounter` (replay guard); check `rpIdHash`. Return new counter.
3. **Configure a JWT signer** in `configure.swift`: `app.jwt.signers.use(.hs256(key: env JWT_SIGNING_KEY))` (or ES256 with a keypair). Add `JWT_SIGNING_KEY` to `.env`/prod. Without this, `req.jwt.sign/verify` throws.
4. **Register `AttestController`** at top level in `routes.swift` (NOT behind
   `APIKeyMiddleware`/`JWTMiddleware`).
5. **Add `POST /attest/dev`** (referenced by the client's `fetchDevToken()` but
   missing). Gate to `app.environment != .production`; mint a JWT with
   `plt: "dev"` signed by the same signer. In prod, return 404/403.
6. **CBOR + X.509**: need a CBOR decoder and cert-chain verification. Evaluate
   `PotentCodables`/`SwiftCBOR` for CBOR and `swift-certificates`
   (`X509`)/`swift-asn1` for the chain + nonce-extension parsing. Add to
   `Package.swift`. (swift-certificates is the Apple-maintained option.)
7. **Watch/proxy path**: watch app has no App Attest. Decide: the iOS app mints
   a `plt: "ios-proxy-watch"` token the watch reuses, or the watch stays on the
   shared key. Simplest for 3.2: watch keeps the shared key, iOS moves to JWT.

### iOS
8. **Wire `getValidJWT()` into `NetworkHandler.authenticatedRequest`**: add
   `Authorization: Bearer <jwt>` alongside (initially) the existing `X-API-Key`.
   Keep the actor's single-flight refresh. Handle a 401 by resetting attest
   state (`Attestation.shared.reset()`) and retrying once.
9. **Failure fallbacks**: unsupported device / MDM / attest error must degrade
   gracefully (today: dev token — which prod will reject). Decide the prod
   behavior for the rare no-App-Attest device (allow via shared key? read-only?).
10. **WebSocket** (`/ws`) auth: currently unauthenticated read stream — decide
    whether it needs the JWT too (probably yes for parity, via a query param or
    first-frame auth since URLSession WS can't easily set Authorization).

## Rollout sequencing — the existing-user constraint

The server **cannot require JWT on a route until every shipped client sends one**,
or old apps break. Staged rollout:

- **Phase 0 (this branch):** implement + unit-test both verifiers against Apple
  sample vectors. Register controller + signer. Routes still gated by
  `APIKeyMiddleware` only. `/attest/*` live but unused by prod clients.
- **Phase 1 (3.2 ships):** the 3.2 app sends BOTH `X-API-Key` and `Bearer`.
  Server accepts either — add JWT as an *alternative*, not a requirement (an
  `EitherAuthMiddleware`: pass if valid JWT OR valid API key). Watch keeps API key.
- **Phase 2 (after 3.2 adoption ≥ ~95%, weeks later):** flip **write routes**
  (`rl:write` group) to require JWT only. Reads stay dual-auth longer.
- **Phase 3:** rotate/retire the shared `X-API-Key` entirely for iOS; keep it
  only for the watch (or migrate watch to proxy tokens).

Ties into the multi-hash key rotation already landed (see
`project_security_audit_2026_07`): the shared key stays valid throughout, so
Phases 1–2 are non-breaking.

## Testing
- Server unit tests with Apple's published attestation/assertion sample vectors
  (deterministic — no device needed). Test: good attestation passes, tampered
  nonce/counter/rpId/cert-chain each fail closed, replayed counter rejected,
  expired challenge rejected.
- Device test on TestFlight: fresh install → attest → refresh cycle; restore-
  from-backup → `invalidKey` → re-attest path.
- Confirm `/attest/dev` is unreachable in prod.

## Open decisions for Umar
- Signer: HS256 (one shared secret, simplest) vs ES256 (keypair, better if
  multiple verifiers). HS256 is fine for a single server.
- Watch auth: proxy token vs keep shared key (recommend: keep shared key for 3.2).
- No-App-Attest device fallback policy in prod.
- CBOR/X.509 library choice (recommend swift-certificates + a CBOR lib).
