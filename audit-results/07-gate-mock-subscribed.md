# Issue 7: Gate mock-subscribed Behind #if DEBUG

**Severity:** MEDIUM | **Release Blocker:** No | **Effort:** 5 min

## Problem

`SubscriptionManager.swift` checks `ProcessInfo.processInfo.environment["mock-subscribed"]` and grants Pro access unconditionally. This code runs in production builds. While setting environment variables on a real device is difficult, it's an unnecessary bypass that should be restricted to debug builds.

## Files to Change

| File | Lines | Action |
|------|-------|--------|
| `SportsCal/Shared/SubscriptionManager.swift` | 33-35 | Wrap `environmentOverridesEnabled` in `#if DEBUG` |
| `SportsCal/Shared/SubscriptionManager.swift` | 74-79 | Wrap mock override in `updateProStatus` in `#if DEBUG` |

## Current Code

**Lines 33-35:**
```swift
internal var environmentOverridesEnabled: Bool {
    ProcessInfo.processInfo.environment["mock-subscribed"] != nil
}
```

**Lines 74-79:**
```swift
if !isTestInstance, ProcessInfo.processInfo.environment["mock-subscribed"] != nil {
    isPro = true
    UserDefaults.standard.set(true, forKey: "isSubscribed")
    return
}
```

## Fix

### Step 1: Update `environmentOverridesEnabled` (lines 33-35)

```swift
internal var environmentOverridesEnabled: Bool {
    #if DEBUG
    return ProcessInfo.processInfo.environment["mock-subscribed"] != nil
    #else
    return false
    #endif
}
```

### Step 2: Update mock override in `updateProStatus` (lines 74-79)

```swift
#if DEBUG
if !isTestInstance, ProcessInfo.processInfo.environment["mock-subscribed"] != nil {
    isPro = true
    UserDefaults.standard.set(true, forKey: "isSubscribed")
    return
}
#endif
```

## Verification

- Build succeeds in both Debug and Release configurations
- In Debug: set `mock-subscribed` env var in scheme, verify Pro access is granted
- In Release: archive the app, verify the mock-subscribed code is stripped by the compiler
- Existing tests in `SportsCalTests/SubscriptionManagerTests.swift` should still pass (they use the `forTesting` init which sets `isTestInstance = true`, bypassing this code)
