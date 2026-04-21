# Issue 6: Add Sentry PII Filtering and Reduce Sample Rate

**Severity:** HIGH | **Release Blocker:** No (but do before release) | **Effort:** 20 min

## Problem

Sentry has no `beforeSend` hook configured, so device tokens, push notification payloads, and API URLs could be sent to Sentry as part of error context/breadcrumbs. The trace sample rate (0.3 = 30%) is also too high for production -- it generates excessive data and costs.

Additionally, several log statements in `AppDelegate.swift` log full device tokens and push notification payloads, which feed into Sentry breadcrumbs.

## Files to Change

| File | Lines | Action |
|------|-------|--------|
| `SportsCal/Shared/AppDelegate.swift` | 43-50 | Add `beforeSend` hook, reduce sample rate (iOS block) |
| `SportsCal/Shared/AppDelegate.swift` | 174-177 | Add `beforeSend` hook, reduce sample rate (macOS block) |
| `SportsCal/Shared/AppDelegate.swift` | 74 | Mask device token in log |
| `SportsCal/Shared/AppDelegate.swift` | 92 | Mask push payload in log |
| `SportsCal/Shared/AppDelegate.swift` | 148 | Mask notification payload in log |

## Fix

### Step 1: Add beforeSend hook to iOS Sentry init (lines 43-50)

Replace the current block:
```swift
SentrySDK.start { options in
    options.dsn = "https://02afdbcbf12d400f865620093257a781@o4505270524772352.ingest.sentry.io/4505282684321792"
    options.tracesSampleRate = 0.3
}
```

With:
```swift
SentrySDK.start { options in
    options.dsn = "https://02afdbcbf12d400f865620093257a781@o4505270524772352.ingest.sentry.io/4505282684321792"
    options.tracesSampleRate = 0.05
    options.beforeSend = { event in
        // Strip breadcrumb messages that may contain device tokens or PII
        event.breadcrumbs = event.breadcrumbs?.map { crumb in
            if let msg = crumb.message,
               (msg.contains("token") || msg.contains("notification")) {
                crumb.message = "[REDACTED]"
            }
            return crumb
        }
        return event
    }
}
```

> Note: If you've already completed Issue 1 (moving DSN to Constants.swift), use `Constants.sentryDSN` instead of the hardcoded string.

### Step 2: Same change for macOS block (lines 174-177)

Apply the identical `beforeSend` hook and sample rate reduction.

### Step 3: Mask device token in log (line 74)

Change:
```swift
AppLogger.notifications.info("Registered for remote notifications with token: \(tokenString)")
```
To:
```swift
AppLogger.notifications.info("Registered for remote notifications with token: \(tokenString.prefix(12))...")
```

### Step 4: Mask push payload in log (line 92)

Change:
```swift
AppLogger.notifications.info("Received remote notification: \(userInfo)")
```
To:
```swift
AppLogger.notifications.info("Received remote notification for event: \(userInfo["eventID"] ?? "unknown")")
```

### Step 5: Mask notification tap payload in log (line 148)

Change:
```swift
AppLogger.notifications.info("User tapped notification: \(userInfo)")
```
To:
```swift
AppLogger.notifications.info("User tapped notification for event: \(userInfo["eventID"] ?? "unknown")")
```

## Verification

- Build succeeds
- Trigger a test crash or error in debug -- verify in Sentry dashboard that breadcrumbs don't contain full tokens
- Check Sentry transaction volume after deploying -- should drop to ~1/6 of previous volume
