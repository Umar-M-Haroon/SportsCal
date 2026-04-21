# Snapshot Tests for Figma Design Review

This folder generates PNG renders of every important UI surface in the app so they can be dragged into Figma as reference material.

## What's here

- `SnapshotFixtures.swift` — fixture factories (games, view models, favorites, storage) built on `DebugGameFactory`.
- `SnapshotHelpers.swift` — `assertReviewSnapshots(...)` — one call per view, loops devices × color schemes.
- `RowViewSnapshotTests.swift` — `GameScoreView`, `RaceScoreView`, `TournamentScoreView`, `UpcomingGameView`, `IndividualTeamView`.
- `DetailViewSnapshotTests.swift` — `GameDetailView`, `RaceDetailView`, `TennisMatchDetailView`, `TournamentDetailView`, `GolfPlayerComparisonView`.
- `ScreenSnapshotTests.swift` — `ContentView`, `DayPage`, `BrowsePage`, `SettingsView`, `SportPickerSheet`, `MiniSubscriptionPage`.
- `BoardSnapshotTests.swift` — `SportColumnView`, `GameBoardLayout` (iPad).

Mirror files live in:
- `SportsCal/Tests macOS/Snapshots/` — `MacSettingsView`, `MenuBar*`, main window.
- `SportsCal/SportsCalWatch Watch AppTests/Snapshots/` — watch row + detail views.

All PNGs land in a single flat folder: `SportsCal/SportsCalTests/__Snapshots__/ReviewExport/` (gitignored).

## One-time Xcode setup

These steps cannot be scripted safely from outside Xcode — do them once:

1. **Add the SPM dependency.**
   - File → Add Package Dependencies… → `https://github.com/pointfreeco/swift-snapshot-testing`
   - Dependency Rule: Up to Next Major, starting at `1.17.0` (or current latest).
   - Add the `SnapshotTesting` product to these targets:
     - `SportsCalTests`
     - `SportsCalWatch Watch AppTests`
     - `Tests macOS` *(verify this target is a **Unit Test** bundle, not a UI Test bundle — the existing `Tests_macOS.swift` uses `XCUIApplication`, which suggests UI Test. If it's UI-only, create a new `SportsCalMacTests` unit test target and add the SPM product there instead, then move the `Snapshots/` folder into that target.)*

2. **Add the new files to each test target.**
   - Drag `SportsCal/SportsCalTests/Snapshots/` into the `SportsCalTests` group in Xcode; make sure every file has `SportsCalTests` checked under Target Membership.
   - Drag `SportsCal/Tests macOS/Snapshots/` into the Mac test target the same way.
   - Drag `SportsCal/SportsCalWatch Watch AppTests/Snapshots/` into the Watch test target the same way.

3. **First-time record run.** The first run produces the PNGs. In each snapshot file, flip the `record:` parameter to `true` for the first `assertReviewSnapshots` call *or* change the library default by setting `isRecording = true` in a test class `setUp`. Once PNGs exist, set it back to `false` — subsequent runs regenerate/compare against them.
   
   Simpler alternative: leave `record: false` in source but set the `SNAPSHOT_TESTING_RECORD=1` env var on the test plan's first run.

## Running

In Xcode, select the relevant scheme (`SportsCal (iOS)`, `SportsCalWatch Watch App`, macOS scheme) and run the test plan (⌘U). PNGs are written to:

```
SportsCal/SportsCalTests/__Snapshots__/ReviewExport/
```

Filenames follow the pattern `<View>-<variant>-<device>-<scheme>.png`, e.g.:

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

- SourceKit LSP may flag `No such module 'SportsCal'` in these files. That's a false positive (per `CLAUDE.md`); the Xcode build graph resolves it correctly.
- `GameDetailView`, `DayPage`, and `BrowsePage` pull in `NativeAdManager` / `SubscriptionManager` / `EngagementTracker`. Fixtures supply safe test instances, but if the ad SDK initializes network sockets at construction, you may see console warnings — they don't fail the test.
- Watch snapshots use a fixed 198×242 pt size (~Apple Watch Series 9 45mm). Adjust `defaultWatchSize` in `WatchSnapshotHelpers.swift` if you need a different watch size.
