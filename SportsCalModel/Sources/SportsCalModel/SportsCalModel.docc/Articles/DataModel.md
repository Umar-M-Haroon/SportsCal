# Data Model

How the core types fit together: ``LiveScore`` is the container, ``LiveEvent`` groups games for a single sport, and ``Game`` is one match.

## Overview

The shape of a typical schedule response from the server:

```
LiveScore
├── nba: LiveEvent? — { events: [Game, Game, ...] }
├── mlb: LiveEvent?
├── soccer: LiveEvent?
├── nfl: LiveEvent?
├── nhl: LiveEvent?
├── golf: LiveEvent?
├── tennis: LiveEvent?
└── racing: LiveEvent?
```

Each ``Game`` carries enough state to render a row, a detail view, or a Live Activity:

- Identity — `idEvent`, `idLeague`, `idHomeTeam`, `idAwayTeam`
- Display — `strHomeTeam`, `strAwayTeam`, `strHomeTeamBadge`, `strAwayTeamBadge`
- Score — `intHomeScore`, `intAwayScore`, `strStatus`, `strProgress`
- Schedule — `isoDate`, `strTimestamp`
- Live commentary — `lastPlay` (also used to encode tournament leaderboards)
- Lifecycle — `isCompleted`, computed `hasDoneStatus`

The full class diagram:

![Models](models)

## Sport derivation

`Game` does not carry a redundant `strSport` or `strLeague` field on the wire — both are computed from `idLeague` via the ``Leagues`` enum. The server saves ~20% on response size by omitting them; the client recomputes via `game.strSport` / `game.strLeague`.

## Live data flow

Every minute the server polls ESPN and TheSportsDB, transforms responses to the shapes above, and writes to Redis. Clients pull via REST and subscribe to a WebSocket for ~5-second updates.

![Data flow](data-flow)

## Why one model package

A common alternative is to define the wire types separately on each side and translate. We don't, because:

- The server is the only producer; clients are pure consumers.
- The package has no platform-specific code (no UIKit, no Foundation-Network, no Vapor) — it builds for iOS, macOS, watchOS, and Linux.
- Compile-time breakage on field renames is a feature, not a bug.

## See Also

- ``LiveScore``
- ``LiveEvent``
- ``Game``
- <doc:ApiVersioning>
