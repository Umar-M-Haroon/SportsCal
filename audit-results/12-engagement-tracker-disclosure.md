# Issue 12: Disclose Engagement Tracker in Privacy Policy

**Severity:** LOW | **Release Blocker:** No | **Effort:** 30 min (policy update)

## Problem

`EngagementTracker.swift` tracks which teams users view (team name, view count, last viewed date, sport type) and stores this in app group UserDefaults under key `TeamEngagement`. Up to 20 teams are tracked with exponential decay scoring. This data stays on-device but is not disclosed to users anywhere.

## Files Involved (Read-Only Context)

| File | Notes |
|------|-------|
| `SportsCal/Shared/EngagementTracker.swift` | Tracks team views, lines 43-56 |
| `SportsCal/Shared/UserDefaultStorage.swift` | App group UserDefaults usage |

## What's Tracked

```swift
struct TeamEngagement: Codable {
    var teamName: String      // e.g., "Lakers"
    var viewCount: Int        // number of times viewed
    var lastViewedDate: Date  // last view timestamp
    var sportRawValue: String // e.g., "basketball"
}
```

- Stored in `UserDefaults(suiteName: "group.Komodo.SportsCal")` with key `"TeamEngagement"`
- Up to 20 teams tracked
- Used to suggest teams for favorites (engagement score with exponential decay)
- Data never leaves the device (no server sync)

## Fix

### Step 1: App Store Connect Privacy Responses

In App Store Connect > App Privacy, declare:
- **Data Type:** "Product Interaction"
- **Collection:** Yes
- **Linked to Identity:** No
- **Tracking:** No
- **Purpose:** "App Functionality" (used to suggest favorite teams)

### Step 2: Privacy Manifest (if completing Issue 3)

Ensure `PrivacyInfo.xcprivacy` includes `NSPrivacyCollectedDataTypeProductInteraction` (already included in Issue 3's template).

### Step 3: Privacy Policy

Update your privacy policy to mention:
- The app tracks which teams you view to personalize suggestions
- This data stays on-device and is never sent to servers
- Users can reset this by deleting and reinstalling the app

### Step 4 (Optional): Add reset in Settings

Consider adding a "Reset Suggestions" button in SettingsView that calls:
```swift
engagementTracker.engagements = [:]
// save empty state
```

## Verification

- App Store Connect privacy responses match actual data collection
- Privacy policy mentions on-device usage analytics
- If adding reset button: verify it clears the UserDefaults key
