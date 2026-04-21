# Issue 11: Gate Tailscale IP Behind DEBUG

**Severity:** MEDIUM | **Release Blocker:** No | **Effort:** 15 min

## Problem

`NetworkHandler.swift` line 76 hardcodes the Tailscale IP `100.68.255.93:8080` which ships in the production binary. `Info.plist` also has an ATS exception allowing insecure HTTP to this IP. While production code uses `api.sportscal.app`, the IP and local server discovery code are still visible to anyone who decompiles the app.

## Files to Change

| File | Lines | Action |
|------|-------|--------|
| `SportsCal/Shared/NetworkHandler.swift` | 76, 82-108 | Gate Tailscale/local paths behind `#if DEBUG` |
| `SportsCal/SportsCal--iOS--Info.plist` | 22-27 | Optionally remove ATS exception for production |

## Current Code

**NetworkHandler.swift lines 76-108:**
```swift
private static let tailscaleHost = "100.68.255.93:8080"

static func baseURL(debug: Bool) -> String {
    if useLocalServer {
        if let local = localServerHost {
            return "http://\(local)/v2025"
        }
        return "http://\(tailscaleHost)/v2025"
    }
    if debug {
        return "http://\(tailscaleHost)/v2025"
    }
    return "https://api.sportscal.app/v2025"
}
```

## Fix

### Step 1: Wrap development paths in `#if DEBUG` (NetworkHandler.swift)

```swift
#if DEBUG
private static let tailscaleHost = "100.68.255.93:8080"
#endif

static func baseURL(debug: Bool) -> String {
    #if DEBUG
    if useLocalServer {
        if let local = localServerHost {
            return "http://\(local)/v2025"
        }
        return "http://\(tailscaleHost)/v2025"
    }
    if debug {
        return "http://\(tailscaleHost)/v2025"
    }
    #endif
    return "https://api.sportscal.app/v2025"
}
```

Apply the same pattern to `rootURL(debug:)` (lines 97-108):
```swift
private static func rootURL(debug: Bool) -> (http: String, ws: String) {
    #if DEBUG
    if useLocalServer {
        if let local = localServerHost {
            return ("http://\(local)", "ws://\(local)")
        }
        return ("http://\(tailscaleHost)", "ws://\(tailscaleHost)")
    }
    if debug {
        return ("http://\(tailscaleHost)", "ws://\(tailscaleHost)")
    }
    #endif
    return ("https://api.sportscal.app", "wss://api.sportscal.app")
}
```

### Step 2: Consider `useLocalServer` and `localServerHost` properties

These are also only meaningful in debug. Consider wrapping:
```swift
#if DEBUG
static var localServerHost: String?
static var useLocalServer: Bool = true
#else
static let localServerHost: String? = nil
static let useLocalServer: Bool = false
#endif
```

### Step 3 (Optional): Info.plist ATS exception

The ATS exception for `100.68.255.93` in `SportsCal--iOS--Info.plist` (lines 22-27) is harmless in production since the IP is never called, but you could remove it for cleanliness. `NSAllowsLocalNetworking = true` on line 18 is needed for Bonjour discovery in dev.

If you use separate Info.plist for Debug/Release, move the exception to Debug only.

## Verification

- Build succeeds in both Debug and Release
- Debug builds still connect to local/Tailscale server
- Release builds always use `https://api.sportscal.app`
- Run `strings` on the Release .app binary and verify `100.68.255.93` does not appear
