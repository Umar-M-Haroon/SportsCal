# Setapp build flavor — checklist

Scoreline is architected so the **exact same source** produces both the App Store IAP build
and a fully-unlocked **Setapp** build. The code abstraction is done and verified; this file is
the remaining (deferred) pipeline work to actually ship on Setapp.

> Setapp forbids in-app purchases / paid components. The Setapp build must be fully unlocked and
> show **no** purchase / restore / price UI. Setapp pays via a usage-based revenue share.

## How the unlock works (already implemented)

- `SubscriptionManager` (`Shared/SubscriptionManager.swift`):
  - `#if SETAPP` → `configure()` skips RevenueCat entirely and sets `isPro = true` for the session.
  - `static var isManagedExternally` is `true` under `#if SETAPP`.
- `isPro = true` cascades through the single gating chokepoint: `ProFeature.canUse()` and
  `NotificationGate.decision(isPro:)` both unlock, and every `!isPro`-conditioned paywall/upsell
  surface (PaywallGate, MiniSubscriptionPage, UpsellCoordinator, menu-bar Pro prompt) disappears.
- `isManagedExternally` additionally hides the always-visible IAP affordances that aren't keyed
  on `isPro` (e.g. **Restore Purchases** in Settings/About).
- Invariants covered by `ProFeatureGatingTests`: `testCanUse_proUnlocksEveryFeature`,
  `testIsManagedExternally_falseInAppStoreBuild`.

## Remaining steps to ship on Setapp (deferred — do when accepted as a vendor)

1. **Build configuration** (Xcode UI, ~5 min — safer than editing `project.pbxproj`, which is
   `objectVersion = 70` with per-target configs):
   - Project → Info → duplicate the **Release** configuration → name it `Setapp`.
   - On the app target's `Setapp` config set
     `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) SETAPP`.
   - Duplicate the app scheme → "Scoreline (Setapp)" → set its Run/Archive build config to `Setapp`.
2. **Distribution = Developer ID, NOT App Store**: archive with Developer ID signing.
3. **Universal binary**: ensure `ARCHS = arm64 x86_64` (Setapp requires arm64 + x86_64).
4. **Notarize** the app (`xcrun notarytool`) and staple.
5. **Setapp framework**: add `Setapp.framework` (MacPaw — SPM `github.com/MacPaw/Setapp-framework`
   or CocoaPods) to the `Setapp` config only; report usage after the user hits main functionality
   (≤ 1 report/hour). Reference: https://docs.setapp.com/docs/preparing-your-application-for-setapp
6. **Verify**: build the `Setapp` scheme and confirm — app is fully unlocked, no paywall/restore/
   price UI anywhere, RevenueCat is never initialized.
7. **Vendor onboarding**: apply at https://setapp.com/developers ; submit for Setapp review.

> Note: MacPaw closed **Setapp Mobile** (iOS) on 2026-02-16. **Setapp for Mac is unaffected.**
