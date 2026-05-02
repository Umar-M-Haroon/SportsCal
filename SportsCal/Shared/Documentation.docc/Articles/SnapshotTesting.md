# Snapshot Testing

PNG renders of every important UI surface — generated for Figma design review, with regression detection as a bonus.

## Overview

The snapshot tests under `SportsCalTests/Snapshots/`, `Tests macOS/Snapshots/`, and `SportsCalWatch Watch AppTests/Snapshots/` produce PNGs of every important UI surface across iOS, macOS, and watchOS. They serve a dual purpose:

- **Design review.** PNGs land in a flat folder you can drag into Figma so designers can review every state without running the app.
- **Visual regression detection.** Once recorded, subsequent runs diff against the recorded baseline.

## What's where

| Test target | Files |
|---|---|
| `SportsCalTests/Snapshots/` | `RowViewSnapshotTests` (`GameScoreView`, `RaceScoreView`, `TournamentScoreView`, `UpcomingGameView`, `IndividualTeamView`), `DetailViewSnapshotTests` (`GameDetailView`, `RaceDetailView`, `TennisMatchDetailView`, `TournamentDetailView`, `GolfPlayerComparisonView`), `ScreenSnapshotTests` (`ContentView`, `DayPage`, `BrowsePage`, `SettingsView`, `SportPickerSheet`, `MiniSubscriptionPage`), `BoardSnapshotTests` (`SportColumnView`, `GameBoardLayout` for iPad) |
| `Tests macOS/Snapshots/` | `MacSettingsView`, `MenuBar*`, main window |
| `SportsCalWatch Watch AppTests/Snapshots/` | watch row + detail views |

Shared infrastructure:

- `SnapshotFixtures.swift` — fixture factories (games, view models, favorites, storage) built on `DebugGameFactory`.
- `SnapshotHelpers.swift` — `assertReviewSnapshots(...)` — one call per view, loops devices × color schemes.

All PNGs land in: `SportsCal/SportsCalTests/__Snapshots__/ReviewExport/` (gitignored).

## One-time setup (must be done in Xcode)

These steps cannot be scripted safely from outside Xcode — do them once:

### 1. Add the SPM dependency

- File → Add Package Dependencies… → `https://github.com/pointfreeco/swift-snapshot-testing`
- Dependency Rule: Up to Next Major, starting at `1.17.0` (or current latest).
- Add the `SnapshotTesting` product to these targets:
  - `SportsCalTests`
  - `SportsCalWatch Watch AppTests`
  - `Tests macOS`*

\* Verify this target is a **Unit Test** bundle, not a UI Test bundle — the existing `Tests_macOS.swift` uses `XCUIApplication`, which suggests UI Test. If it's UI-only, create a new `SportsCalMacTests` unit test target and add the SPM product there instead, then move the `Snapshots/` folder into that target.

### 2. Add the new files to each test target

- Drag `SportsCal/SportsCalTests/Snapshots/` into the `SportsCalTests` group in Xcode; make sure every file has `SportsCalTests` checked under Target Membership.
- Drag `SportsCal/Tests macOS/Snapshots/` into the Mac test target the same way.
- Drag `SportsCal/SportsCalWatch Watch AppTests/Snapshots/` into the Watch test target the same way.

### 3. First-time record run

The first run produces the PNGs. In each snapshot file, flip the `record:` parameter to `true` for the first `assertReviewSnapshots` call *or* change the library default by setting `isRecording = true` in a test class `setUp`. Once PNGs exist, set it back to `false` — subsequent runs regenerate/compare against them.

Simpler alternative: leave `record: false` in source but set the `SNAPSHOT_TESTING_RECORD=1` env var on the test plan's first run.

## Running

In Xcode, select the relevant scheme (`SportsCal (iOS)`, `SportsCalWatch Watch App`, macOS scheme) and run the test plan (⌘U). PNGs are written to:

```
SportsCal/SportsCalTests/__Snapshots__/ReviewExport/
```

Filenames follow `<View>-<variant>-<device>-<scheme>.png`:

- `GameScoreView-basketball-live-iphone-dark.png`
- `RaceScoreView-upcoming-ipad-light.png`
- `MacSettingsView-mac-light.png`
- `WatchRaceRow-live-watch.png`

Approximate output: ~185–200 PNGs across all platforms.

## Uploading to Figma

1. Open the `ReviewExport/` folder in Finder.
2. Select all PNGs, drag them into a Figma page. Each PNG becomes an image frame you can arrange, group, or annotate for design review.

## Regenerating

To refresh the PNG set before another design review pass, rerun the snapshot test plan. If views have changed visually, tests will fail (not-matching) — re-record by flipping `record: true` or using the env var above.

## Known caveats

- **SourceKit LSP "No such module 'SportsCal'".** False positive — the Xcode build graph resolves it correctly.
- **Ad SDK socket warnings.** `GameDetailView`, `DayPage`, and `BrowsePage` pull in `NativeAdManager` / `SubscriptionManager` / `EngagementTracker`. Fixtures supply safe test instances, but if the ad SDK initializes network sockets at construction, you may see console warnings — they don't fail the test.
- **Watch snapshot size.** Watch snapshots use a fixed 198×242 pt size (~Apple Watch Series 9 45mm). Adjust `defaultWatchSize` in `WatchSnapshotHelpers.swift` if you need a different watch size.

## See Also

- <doc:ViewModelArchitecture>
- <doc:LiveActivityClient>
