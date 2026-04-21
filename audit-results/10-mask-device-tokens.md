# Issue 10: Mask Device Token Logging

**Severity:** MEDIUM | **Release Blocker:** No | **Effort:** 10 min

## Problem

Full APNS device tokens and push notification payloads are logged in `AppDelegate.swift`. These logs feed into Sentry breadcrumbs and could expose PII (device tokens are personally identifiable and can be used to target push notifications).

## Files to Change

| File | Lines | Action |
|------|-------|--------|
| `SportsCal/Shared/AppDelegate.swift` | 74 | Truncate device token |
| `SportsCal/Shared/AppDelegate.swift` | 92 | Strip full payload from log |
| `SportsCal/Shared/AppDelegate.swift` | 148 | Strip full payload from log |

## Current Code

**Line 74:**
```swift
AppLogger.notifications.info("Registered for remote notifications with token: \(tokenString)")
```

**Line 92:**
```swift
AppLogger.notifications.info("Received remote notification: \(userInfo)")
```

**Line 148:**
```swift
AppLogger.notifications.info("User tapped notification: \(userInfo)")
```

## Fix

### Line 74 -- Truncate device token

Change to:
```swift
AppLogger.notifications.info("Registered for remote notifications with token: \(tokenString.prefix(12))...")
```

### Line 92 -- Log only event ID from push payload

Change to:
```swift
AppLogger.notifications.info("Received remote notification for event: \(userInfo["eventID"] ?? "unknown")")
```

### Line 148 -- Log only event ID from notification tap

Change to:
```swift
AppLogger.notifications.info("User tapped notification for event: \(userInfo["eventID"] ?? "unknown")")
```

## Verification

- Build succeeds
- Trigger a push notification in debug -- check Xcode console shows truncated token and event-only log
- Full payloads no longer appear in log output
