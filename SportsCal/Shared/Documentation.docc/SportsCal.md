# ``SportsCal``

iOS and watchOS sports-calendar app. SwiftUI throughout, with three `@Observable` environment objects driving every screen.

## Overview

`SportsCal` is the main iOS app target. It consumes the shared `SportsCalModel` package over Swift Package Manager and talks to the Vapor server (`SportsCalServer`) over HTTPS + WebSocket.

The app is built around a 3-tab `TabView` (Games, Calendar, Browse) with three top-level `@Observable` environment objects:

- `GameViewModel` — fetches games, manages WebSocket live events, filters by sport preferences.
- `UserDefaultStorage` — sport visibility toggles, date format preferences, focus-mode flags.
- `Favorites` — the set of team names the user has starred.

Live Activities are driven from the iOS side by `LiveActivityMatcher` (pure logic) and the corresponding server jobs (`APNSJob`, `ESPNFetchJob` push-to-start phase). For the server side of that pipeline, see the SportsCalServer documentation.

## Topics

### Architecture

- <doc:ViewModelArchitecture>
- <doc:LiveActivityClient>

### Testing

- <doc:SnapshotTesting>
