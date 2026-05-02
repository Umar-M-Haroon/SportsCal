# ``SportsCalModel``

Shared data types for the SportsCal iOS app, watchOS app, and Vapor server.

## Overview

`SportsCalModel` is a pure-Swift package with no external dependencies. It defines the wire format and runtime model for everything the apps render: leagues, sports, games, live events, teams, scoreboards, and the per-sport enrichment payloads (golf leaderboards, F1 standings, injury reports).

The same package is consumed by:

- The iOS and watchOS apps via Swift Package Manager.
- The Vapor server via a local package dependency.

This guarantees a single source of truth for the JSON contract — when the server changes a field, the clients break at compile time rather than at runtime.

![System overview](overview)

## Topics

### Essentials

- <doc:DataModel>
- <doc:ApiVersioning>
- <doc:IndividualSports>

### Core models

- ``LiveScore``
- ``LiveEvent``
- ``Game``
- ``Team``
- ``Teams``

### Sports & leagues

- ``SportType``
- ``Leagues``

### V2025 API wrappers

- ``V2LiveScoreResponse``
- ``V2TeamsResponse``
- ``V2ScheduleResponse``
- ``V2NoDataResponse``

### ESPN scoreboard (API2)

- ``Scoreboard``
- ``Event``
- ``Competition``
- ``Competitor``
- ``Status``
- ``StatusType``

### Golf enrichment

- ``LeaderboardEntry``
- ``GolfCourseInfo``
- ``GolfRoundDetail``
- ``GolfRoundStats``
- ``GolfHoleScore``

### Formula 1 enrichment

- ``F1CircuitInfo``
- ``F1Standings``
- ``F1DriverStanding``
- ``F1ConstructorStanding``
- ``F1RaceTiming``
- ``F1TelemetryDriver``
- ``F1Stint``
- ``F1PitStop``

### Other enrichment

- ``InjuryReport``
- ``EventSession``
- ``PlayoffContext``
- ``GameLeader``
