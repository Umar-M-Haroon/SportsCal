# Issue 1: Move Sentry DSN to Constants.swift

**Severity:** CRITICAL | **Release Blocker:** YES | **Effort:** 10 min

## Problem

Sentry DSN is hardcoded in version-controlled `AppDelegate.swift` (lines 44 and 175). Anyone with repo access can spam your Sentry project with fake crash reports. The trace sample rate (0.3 = 30%) is also too high for production.

## Files to Change

| File | Action |
|------|--------|
| `SportsCal/Shared/Constants.swift` | Add `sentryDSN` property |
| `SportsCal/ci_scripts/ci_post_clone.sh` | Add `$SENTRY_DSN` env var |
| `SportsCal/Shared/AppDelegate.swift` | Reference `Constants.sentryDSN` instead of hardcoded string |

## Current Code

**AppDelegate.swift line 44 (iOS):**
```swift
SentrySDK.start { options in
    options.dsn = "https://02afdbcbf12d400f865620093257a781@o4505270524772352.ingest.sentry.io/4505282684321792"
    options.tracesSampleRate = 0.3
}
```

**AppDelegate.swift line 174 (macOS):**
```swift
SentrySDK.start { options in
    options.dsn = "https://02afdbcbf12d400f865620093257a781@o4505270524772352.ingest.sentry.io/4505282684321792"
    options.tracesSampleRate = 0.3
}
```

## Fix

### Step 1: Add `sentryDSN` to Constants.swift (line 14, after `nativeAdUnitID`)

```swift
struct Constants {
    static let revenueCatAPIKey = "appl_PjHrjVeBZgvkmhEEpzDKXSODirZ"
    static let apiKey = "NKeW2YkXuiRbLQuLHIj-DM_UxhkxqMxaj-JJATUoeK8"
    static let adMobAppID = "ca-app-pub-7626210410574910~5399782511"
    static let nativeAdUnitID = "ca-app-pub-7626210410574910/3695818608"
    static let sentryDSN = "YOUR_SENTRY_DSN_HERE"  // <-- ADD THIS
}
```

### Step 2: Update ci_post_clone.sh to include SENTRY_DSN

Replace the existing printf on line 9 with:
```bash
printf "import Foundation\nstruct Constants {\n\t   static let revenueCatAPIKey = \"%s\"\n\t   static let apiKey = \"%s\"\n\t   static let adMobAppID = \"%s\"\n\t   static let nativeAdUnitID = \"%s\"\n\t   static let sentryDSN = \"%s\"\n}" $REVENUECAT_API_KEY $SPORTSCAL_API_KEY $ADMOB_APP_ID $ADMOB_NATIVE_AD_UNIT_ID $SENTRY_DSN > ../Shared/Constants.swift
```

### Step 3: Update AppDelegate.swift

**Line 44 (iOS block):** Change to:
```swift
options.dsn = Constants.sentryDSN
options.tracesSampleRate = 0.05
```

**Line 175 (macOS block):** Change to:
```swift
options.dsn = Constants.sentryDSN
options.tracesSampleRate = 0.05
```

### Step 4: Set SENTRY_DSN in Xcode Cloud environment variables

Add `SENTRY_DSN` with value `https://02afdbcbf12d400f865620093257a781@o4505270524772352.ingest.sentry.io/4505282684321792` to your Xcode Cloud workflow environment variables.

## Verification

- Build succeeds
- Constants.swift is still in `.gitignore` (verify with `git check-ignore SportsCal/Shared/Constants.swift`)
- No Sentry DSN string appears in any tracked file: `git grep -l "sentry.io" -- ':!audit-results'` should return nothing
