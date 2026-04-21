# Issue 13: Clean Up Ngrok URL in XCScheme

**Severity:** LOW | **Release Blocker:** No | **Effort:** 2 min

## Problem

`SportsCal (iOS).xcscheme` contains an old ngrok URL as a disabled environment variable (line 87-97). While disabled (`isEnabled="NO"`), it's in version control in `xcshareddata` and reveals development practices. The URL itself is expired/invalid but should be cleaned up.

## Files to Change

| File | Action |
|------|--------|
| `SportsCal/SportsCal.xcodeproj/xcshareddata/xcschemes/SportsCal (iOS).xcscheme` | Remove ngrok environment variable |

## Current Code (around lines 87-97)

```xml
<EnvironmentVariable
    key = "host"
    value = "https://83f4-2601-280-c781-8ec0-8d6f-9240-bbf1-8e4b.ngrok.io"
    isEnabled = "NO">
</EnvironmentVariable>
```

## Fix

### Option A: Via Xcode (recommended)

1. Open `SportsCal.xcodeproj` in Xcode
2. Product > Scheme > Edit Scheme...
3. Select "Run" on the left
4. Go to the "Arguments" tab
5. Under "Environment Variables", find the `host` entry with the ngrok URL
6. Delete it (click the `-` button)
7. Close the scheme editor

### Option B: Edit XML directly

Open `SportsCal/SportsCal.xcodeproj/xcshareddata/xcschemes/SportsCal (iOS).xcscheme` and remove the entire `<EnvironmentVariable>` block for the `host` key with the ngrok URL.

## Verification

- Scheme still works (build and run in Xcode)
- `grep -r "ngrok" SportsCal/SportsCal.xcodeproj/` returns no results
