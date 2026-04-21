# Issue 3: Create Privacy Manifest (PrivacyInfo.xcprivacy)

**Severity:** CRITICAL | **Release Blocker:** YES | **Effort:** 1-2 hours

## Problem

No `PrivacyInfo.xcprivacy` file exists in the project. Apple requires this for apps using third-party SDKs that access required-reason APIs. The app uses Sentry, Google Mobile Ads (AdMob), and RevenueCat -- all of which require privacy manifest declarations. **App Store will reject without this.**

## Files to Create

| File | Action |
|------|--------|
| `SportsCal/PrivacyInfo.xcprivacy` | Create new privacy manifest |

## SDKs Requiring Declaration

1. **Sentry** -- crash/error reporting, performance traces
2. **Google Mobile Ads (AdMob)** -- advertising, device identifiers
3. **RevenueCat** -- purchase/subscription data
4. **UserDefaults** -- accessed for app configuration and preferences (required-reason API)

## Fix

### Step 1: Create `SportsCal/PrivacyInfo.xcprivacy`

Create this file as a property list with the following structure. This is a starting point -- adjust based on your exact SDK versions and their documentation.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <!-- Crash/diagnostics data (Sentry) -->
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeCrashData</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
        <!-- Performance data (Sentry traces) -->
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypePerformanceData</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
        <!-- Purchase history (RevenueCat) -->
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypePurchaseHistory</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
        <!-- Product interaction (EngagementTracker, team views) -->
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeProductInteraction</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
        <!-- Device ID (AdMob) -->
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeDeviceID</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <!-- UserDefaults (used extensively for preferences, favorites, etc.) -->
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
        <!-- File timestamp APIs (used by cache/image caching) -->
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

### Step 2: Add to Xcode project

1. Open `SportsCal/SportsCal.xcodeproj` in Xcode
2. Right-click the SportsCal group > "Add Files to SportsCal..."
3. Select `PrivacyInfo.xcprivacy`
4. Ensure target membership is checked for "SportsCal (iOS)"
5. Also check membership for widget and watch targets if they have their own bundles

### Step 3: Verify SDK-bundled manifests

Check that your SPM/CocoaPods versions of these SDKs include their own privacy manifests:
- Sentry: v8.20+ includes its own `PrivacyInfo.xcprivacy`
- RevenueCat: v4.35+ includes its own manifest
- Google Mobile Ads: v11.2+ includes its own manifest

If your SDK versions are older, update them.

### Step 4: Update App Store Connect privacy responses

In App Store Connect > App Privacy, ensure your responses match the manifest declarations above.

## Verification

- Build succeeds with no warnings about missing privacy manifest
- In Xcode: Product > Generate Privacy Access Report -- review the output
- Submit a TestFlight build and check for any privacy-related warnings
- Cross-reference with Apple's documentation: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
