# App Store Screenshots (fastlane snapshot)

## Why this exists
The screenshots under `fastlane/screenshots/en-US/` are **stale**: they show the
old **"SportsCal"** in-app title, but the app rebranded to **"Scoreline"**
(`ContentView` uses `.navigationTitle("Scoreline")`). They also only cover
6.5"/6.7" (no 6.9", the now-required size) and only `en-US`. They need
regenerating against the current UI before the next submission.

`Snapfile` is configured for automated capture. Three one-time setup steps
remain (they need Xcode, so they're documented here rather than scripted):

## 1. Add SnapshotHelper to the UITest target
`fastlane/SnapshotHelper.swift` is in the project but **not compiled into the
test target**. In Xcode: select `SnapshotHelper.swift` → File Inspector (right
panel) → **Target Membership** → check **SportsCalUITests**. (Also confirm the
`SportsCal (iOS)` scheme's **Test** action includes the `SportsCalUITests`
target, and that the scheme is shared.)

## 2. Add the screenshot UITest
Add this method to `SportsCalUITests/SportsCalUITests.swift` (compiles once
step 1 is done):

```swift
func testSnapshots() throws {
    let app = XCUIApplication()
    setupSnapshot(app)
    app.launchArguments += ["-uiTestSeedDemo", "YES"] // see step 3
    app.launch()
    sleep(8) // let the games feed load

    snapshot("01_Games")

    // Best-effort tab navigation — a renamed/missing control never fails the run.
    func go(_ label: String, _ shot: String) {
        let btn = app.buttons[label].firstMatch
        if btn.waitForExistence(timeout: 4) { btn.tap(); sleep(3); snapshot(shot) }
    }
    go("Calendar", "02_Calendar")
    go("Browse", "03_Browse")

    // A game-detail shot: tap the first cell on the Games tab.
    app.buttons["Games"].firstMatch.tap(); sleep(2)
    let firstCell = app.cells.firstMatch
    if firstCell.waitForExistence(timeout: 4) { firstCell.tap(); sleep(3); snapshot("04_GameDetail") }
}
```

## 3. Seed demo state (so screenshots aren't empty) — THE IMPORTANT ONE
A fresh launch has **no favorites**, so the "Favorites" section is empty and the
shots look worse than the current ones. Add a launch-arg guarded seed early in
app startup (e.g. in `SportsCalApp.init()` or `ContentView.onAppear`), seeding a
few well-known teams + enabling all sports:

```swift
#if DEBUG
if ProcessInfo.processInfo.arguments.contains("-uiTestSeedDemo") {
    // Seed a handful of marquee favorites (use real TheSportsDB team IDs that
    // exist in the fetched teams payload) + ensure sports are enabled so the
    // feed is full. Keep this DEBUG-only so it never ships.
    Favorites.shared.seedForScreenshots(["134860" /* Bulls */, ...])
}
#endif
```

Pick teams with games in the current window so the feed is populated. (Implement
`seedForScreenshots` on `Favorites`, or set `teamIDs` directly.)

## 4. Run
```bash
cd SportsCal
bundle exec fastlane snapshot      # captures to fastlane/screenshots/<lang>/
fastlane frameit                   # frames + captions (reuse the green template)
bundle exec fastlane upload_screenshots   # existing retry lane -> ASC
```

## Caption text (reuse for frameit Framefile / .strings)
01 Games — "Every game, one place" · 02 Calendar — "Your teams on your calendar"
· 03 Browse — "All leagues, live scores" · 04 Detail — "Live box scores & alerts"
Add a World Cup 2026 shot while the tournament is on.

## Copy en-US shots to en-GB
After capture, mirror `fastlane/screenshots/en-US/` into `en-GB/` (same images)
so the new en-GB localization isn't missing screenshots, or let `snapshot`
capture both (Snapfile lists both languages).
