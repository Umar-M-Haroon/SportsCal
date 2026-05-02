# ViewModel Architecture

The three `@Observable` environment objects every screen depends on, and how they interact with the network layer.

## Overview

The iOS app is intentionally view-model-light: there are exactly three `@Observable` types injected at the top of `SportsCalApp`, and views read from them via `@Environment` rather than owning local copies.

| Type | Owns | Lifetime |
|---|---|---|
| `GameViewModel` | All game data, WebSocket connection, Live Activity bookkeeping | App-lifetime singleton |
| `UserDefaultStorage` | Sport visibility flags, date format, focus-mode flags | Backed by `UserDefaults` |
| `Favorites` | The set of starred team names | Backed by `UserDefaults` + iCloud sync |

## `GameViewModel`

The primary view-model. Its public surface is intentionally narrow — three computed arrays plus a small set of mutators:

- `totalGames: [Game]` — every game returned by the server, regardless of user filters.
- `filteredGames: [Game]` — `totalGames` filtered by the user's `UserDefaultStorage` sport toggles. This is what the calendar and lists actually render.
- `liveEvents: [LiveEvent]` — currently live games from the WebSocket stream, used by the live-row banners.

Internally it owns:

- A `NetworkHandler` reference for REST calls.
- A `URLSessionWebSocketTask` for the live-score stream.
- An `Activity<LiveSportActivityAttributes>` registry for in-flight Live Activities.
- A persistence path for caching the last successful schedule fetch (12-hour TTL on the cache).

Views never call `NetworkHandler` directly — they ask `GameViewModel` for data.

## `UserDefaultStorage`

A property-list-style preferences object. Each property is a `@AppStorage`-backed value; the `@Observable` wrapper republishes when any of them change.

Key fields:

- `shouldShowNBA`, `shouldShowNFL`, `shouldShowNHL`, `shouldShowSoccer`, `shouldShowMLB`, `shouldShowGolf`, `shouldShowTennis`, `shouldShowRacing` — sport toggles (drive `GameViewModel.filteredGames`).
- `dateFormat` — relative ("Tomorrow"), absolute ("April 28"), or both.
- `focusMode` — when on, `ContentView` swaps in `FocusGameDetailView` instead of `GameDetailView`.

## `Favorites`

A simple `Set<String>` of team names with two helper methods:

- `contains(_ game: Game) -> Bool` — does this game involve a favorite?
- `toggle(_ teamName: String)` — add/remove a team from favorites.

Persisted to `UserDefaults` *and* synced through CloudKit via `CloudSyncManager` so favorites travel between devices.

## How views consume them

```swift
struct ContentView: View {
    @Environment(GameViewModel.self) var games
    @Environment(UserDefaultStorage.self) var prefs
    @Environment(Favorites.self) var favorites

    var body: some View {
        // ... reads `games.filteredGames`, `prefs.dateFormat`, `favorites.contains(...)`
    }
}
```

Injection happens once at the root of `SportsCalApp.swift` via `.environment(_:)`.

## Why three rather than one

A single mega-VM was the obvious starting point. We split into three because:

- **Testability.** `LiveActivityMatcher` was extracted from `GameViewModel` so the matching logic can be unit-tested without standing up a network mock.
- **Persistence boundaries.** `UserDefaultStorage` and `Favorites` are backed by very different storage (UserDefaults + CloudKit vs. UserDefaults alone). Coupling them to live game state would mean every game-list update accidentally rewrites the favorites file.
- **Watch reuse.** The watchOS app reuses `UserDefaultStorage` and `Favorites` directly via target membership; it has its own polling-based equivalent of `GameViewModel` rather than the WebSocket version.

## Network layer

`NetworkHandler` is the only place that touches `URLSession`. It exposes:

- `fetchSchedules() async throws -> LiveScore` → `/v2025/schedules`
- `fetchTeams() async throws -> [Team]` → `/v2025/teams`
- `connectLiveScoreSocket() -> AsyncThrowingStream<LiveScore, Error>` → `/v2025/ws`
- Per-sport variants for the Browse tab.

`APIVersionChecker` reads `X-Min-App-Version` from every response and posts a notification if the user's bundle version is below the floor — `SettingsView` displays the resulting "update required" banner.

## See Also

- <doc:LiveActivityClient>
- <doc:SnapshotTesting>
