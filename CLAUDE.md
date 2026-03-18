# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

SportsCal is a multi-platform sports calendar app (iOS, watchOS) with a Vapor backend and TypeScript admin dashboard. The monorepo has four main components:

| Component | Path | Tech |
|-----------|------|------|
| iOS/Watch App | `SportsCal/` | SwiftUI, Xcode project |
| Shared Model | `SportsCalModel/` | Swift Package (SPM) |
| API Server | `SportsCalAPI/SportsCalServer/` | Vapor 4, Redis |
| Admin Dashboard | `SportsCalAdmin/` | TypeScript, Vite |

## Build & Run

The iOS app and Watch app are built and run through Xcode — open `SportsCal/SportsCal.xcodeproj`. Do not attempt to build or run the project from the command line; the user will handle building and running.

### Shared Model Package
```bash
cd SportsCalModel && swift build && swift test
```

### Vapor API Server
```bash
# Requires Redis running
cd SportsCalAPI/SportsCalServer && swift run
```
After server code changes, restart with `./force-restart.sh` (kills existing process, rebuilds, starts fresh on port 8080).

### Admin Dashboard
```bash
cd SportsCalAdmin
npm install
npm run dev          # Dev server on port 3000
npm run build        # Production build → outputs to SportsCalAPI/SportsCalServer/Public/admin
```

## Architecture

### iOS App (`SportsCal/Shared/`)
- **Entry point**: `SportsCalApp.swift` → `ContentView.swift` (3-tab TabView: Games, Calendar, Browse)
- **State**: Three `@Observable` environment objects — `GameViewModel`, `UserDefaultStorage`, `Favorites`
- **GameViewModel** is the primary ViewModel: fetches games, manages WebSocket live events, filters by sport preferences. Exposes `totalGames`, `filteredGames`, `liveEvents`
- **NetworkHandler** handles all HTTP (ESPN + TheSportsDB) and WebSocket connections
- **Views/**: 56+ SwiftUI files. Sport-specific views exist for individual sports (golf/tennis use `TournamentScoreView`, F1 uses `RaceScoreView`/`RaceDetailView`)
- **AppIntents/**: Siri Shortcuts, Spotlight search, Focus Filters

### Targets
| Target | Platform | Notes |
|--------|----------|-------|
| SportsCal (iOS) | iOS 18+ | Main app |
| SportsWidgetExtension | iOS | Home screen widgets |
| SportsCalWatch Watch App | watchOS 9+ | Polling-based (no WebSocket) |
| SportsCalWatchWidgets | watchOS | Watch complications |

### Shared Model (`SportsCalModel/`)
Pure Swift package, no external dependencies. Defines `Game`, `SportType`, `Leagues`, `LiveEvent`, `Team`. Used by iOS app (SPM dependency in Xcode) and Vapor server (local package dependency).

### API Server (`SportsCalAPI/SportsCalServer/`)
Vapor 4 with Redis caching, background job queues (Queues-Redis-Driver), and APNS push notifications. Serves the admin dashboard as static files from `Public/admin/`.

### Admin Dashboard (`SportsCalAdmin/`)
Vanilla TypeScript + Vite SPA. Six views: Health Monitor, Live Games, League Explorer, Data Gaps, Redis Viewer, Teams Explorer. Uses WebSocket for real-time updates. See `SportsCalAdmin/README.md` for API endpoint details.

## Git Conventions

- Do not add a `Co-Authored-By` line to commit messages

## Key Conventions

- **SportType enum** (`.basketball`, `.soccer`, `.hockey`, `.mlb`, `.nfl`, `.golf`, `.tennis`, `.racing`) is the central type for sport identification throughout the codebase
- **Individual sports** (golf, tennis, F1) have distinct code paths — `game.isIndividualSport` / `game.isRace` control view selection and data parsing
- **`SportType+UI.swift`** extension provides `systemImage`, `color`, `displayName` for SwiftUI
- **Constants.swift** is gitignored — generated at CI time with RevenueCat API key (see `ci_scripts/ci_post_clone.sh`)
- **Platform guards**: Watch app uses `#if os(watchOS)` and shares some files with iOS via Xcode target membership (not SPM)
- SourceKit LSP may report "No such module 'SportsCalModel'" — this is a false positive; the full SPM build graph isn't visible to LSP
