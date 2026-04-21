# Issue 4: Fix Release Entitlements APS Environment

**Severity:** CRITICAL | **Release Blocker:** YES | **Effort:** 2 min

## Problem

`SportsCal (iOS)Release.entitlements` has `aps-environment` set to `development` on lines 5-8. Production users will NOT receive push notifications because the app will connect to Apple's development APNs cluster instead of production.

## Files to Change

| File | Action |
|------|--------|
| `SportsCal/SportsCal (iOS)Release.entitlements` | Change `development` to `production` (2 places) |

## Current Code

```xml
<key>aps-environment</key>
<string>development</string>
<key>com.apple.developer.aps-environment</key>
<string>development</string>
```

## Fix

Change lines 6 and 8 in `SportsCal/SportsCal (iOS)Release.entitlements`:

**Line 6:** `<string>development</string>` --> `<string>production</string>`
**Line 8:** `<string>development</string>` --> `<string>production</string>`

The file should look like:
```xml
<key>aps-environment</key>
<string>production</string>
<key>com.apple.developer.aps-environment</key>
<string>production</string>
```

## Verification

1. Verify the Debug entitlements (`SportsCal (iOS).entitlements`) still say `development` -- do NOT change that file
2. In Xcode: Build Settings > Code Signing Entitlements -- confirm the Release configuration points to `SportsCal (iOS)Release.entitlements`
3. Archive the app and check the entitlements in the .app bundle: `codesign -d --entitlements - SportsCal.app` should show `aps-environment: production`
