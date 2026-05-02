# Individual Sports

How golf, tennis, and Formula 1 reuse the head-to-head ``Game`` shape.

## Overview

Three sports break the "two teams playing each other" assumption:

- **Golf** — a tournament with a leaderboard.
- **Tennis** — same shape (tournament + leaderboard) for ATP/WTA majors.
- **Formula 1** — a race weekend with a starting grid, leaderboard during the race, and final classification.

Rather than minting parallel model types, ``Game`` overloads its fields so a single shape covers all of them:

| Field | Head-to-head | Tournament | Race |
|---|---|---|---|
| `strHomeTeam` | Home team | Tournament name | Race name |
| `strAwayTeam` | Away team | Current leader | Pole-sitter / leader |
| `lastPlay` | Last play description | Encoded leaderboard | Encoded race classification |

The clients branch on ``Game/isIndividualSport`` and ``Game/isRace`` to pick the right view.

## Golf and tennis

`lastPlay` is the encoded payload. Each line is `Name|Score`:

```
Scottie Scheffler|-12
Rory McIlroy|-10
Xander Schauffele|-9
Collin Morikawa|-8
Viktor Hovland|-7
```

``Game`` exposes a parsed view as `game.leaderboard: [(name: String, score: String)]` so views never need to touch the encoding directly.

The server side (`TheSportsDB`) returns null `strHomeTeam` / `strAwayTeam` for individual sports, so ``Game``'s decoder falls back to `strEvent` to populate the tournament name. When `idHomeTeam` / `idAwayTeam` are nil, the client synthesizes ``Team`` objects on demand for any UI that expects them.

The richer ``LeaderboardEntry`` and ``GolfRoundDetail`` types ride alongside `lastPlay` for the detail view, with full per-round scoring, course info, and round stats.

## Formula 1

F1 reuses the same encoding trick but with one extra field per line — `Driver|Position|Gap|Constructor`:

```
Verstappen|1|—|Red Bull
Norris|2|+8.342|McLaren
Leclerc|3|+12.106|Ferrari
```

``Game/raceLeaderboard`` parses this into a typed array. The dedicated views (`RaceScoreView`, `RaceDetailView` on the iOS side) are reached through ``Game/isRace``.

The server enriches races with ``F1CircuitInfo`` (circuit name, locality, country, layout image, lat/long) and ``F1Standings`` (driver + constructor championships) on a separate background job, cached in Redis with a 6-hour TTL. The OpenF1 API supplies live telemetry — see ``F1RaceTiming``, ``F1TelemetryDriver``, ``F1Stint``, ``F1PitStop`` for the full shape.

## Why overload `lastPlay` instead of adding new fields

- The wire format stays backward-compatible — older clients still parse the JSON, they just render `lastPlay` as a status string.
- The same Live Activity push payload works for every sport without per-sport schema branching on the server.
- New sports (e.g. NASCAR, MotoGP) drop into existing infrastructure by reusing one of the three encoding patterns above.

## See Also

- ``Game``
- ``LeaderboardEntry``
- ``GolfCourseInfo``
- ``F1CircuitInfo``
- ``F1Standings``
