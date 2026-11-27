# Fantasy scoring — plan (Nov 2026)

Branch `fantasy` (worktrees/fantasy). NFL first, then NBA / NHL / MLB (weight tables + test pass each).

## What we already have
- `ESPNFetchJob` fetches each live game's ESPN summary every tick and writes `LivePlayerFeed`
  (`LivePlayers-{espnEventID}`, 6h TTL) with `PlayerLiveStatLine.stats` per player —
  `passing.passingYards`, `receiving.receptions`, `fumbles.fumblesLost`, `kicking.fieldGoalsMade`…
- `/plays/:id?players=1` serves a display `PlayerBoxScore` to game detail.
- `Favorites.followedPlayers` (ESPN athlete IDs) + custom alert pipeline (`AlertMilestone`, `CustomAlertJob`).

Gaps: no history (finals drop after 6h), NFL box has **no positions**, box has no FG distances / 2-pt
conversions, no D/ST line.

## Model (SportsCalModel)
- `FantasyScoring` — `weights: [statKey: pts]` + `rules` (threshold/tier: 300-yd bonus, points-allowed
  tiers). Presets: NFL Standard / Half-PPR / PPR (+ NBA/NHL/MLB later). Custom = edited copy. Imported =
  mapped from Sleeper `scoring_settings` / ESPN fantasy `scoringItems`.
- Derived NFL keys from the summary: `kicking.fg0_39/fg40_49/fg50plus` + `twoPointConversions` (from
  scoring plays), `kicking.fieldGoalsMissed`, and a synthetic **D/ST** line per team (`dst.*`, points allowed).
- `FantasySlate` / `FantasyPlayerLine` wire types: stats + season-average stats + game state/progress.
- `FantasyVerdict`: **Studs** = top points; **Stinkers** = pace-adjusted actual vs season average
  (expected ≥ floor, ≤ 50% of expected, game ≥ half done). Raw fallback when no history.
- `PlayerBoxScore.Group.keys` (ESPN keys, optional) so the client can score any box score.

## Server
- SQLite `fantasy_lines` table (PBP archive DB): one row per player per game, upserted live, durable.
  Season averages = mean stats over the season's finals.
- **Backfill job**: this season's NFL finals from ESPN week scoreboards, rate-limited (≈1 summary / 5s).
- **Positions**: ESPN team rosters, cached daily (athleteID → position, jersey).
- `GET /fantasy/nfl/slate?week=` → `FantasySlate` (week for NFL, day for the others).
- **Sleeper import** (server-side because the 14MB players DB is needed for ID mapping; Sleeper's
  `espn_id` covers only ~25% of active skill players, so match on team + jersey + name):
  `GET /fantasy/import/sleeper/:username` → leagues; `GET /fantasy/import/sleeper/league/:id` →
  `FantasyLeague` (scoring + rosters in ESPN athlete IDs).
- Custom alerts: `AlertMilestone.stat = "fantasyPoints"` + rule-carried scoring.

## App
- `FantasySettings`: active scoring per sport (preset / custom / league), imported leagues + my roster.
- **Fantasy hub** (Studs / Stinkers / My Team) with scoring chip, delta-vs-average pills, tap → breakdown.
- **Game detail**: FPTS column in the box score + "Fantasy: studs & stinkers" strip.
- **My players**: followed players + imported roster, live.
- **ESPN league import** runs on device (private leagues need `espn_s2`/`SWID` cookies — they never
  leave the phone). ESPN fantasy player IDs == ESPN athlete IDs, so no mapping.
- **Alerts**: "X passes 20 fantasy points".
- Proposed gating: presets + Studs/Stinkers + FPTS free; custom scoring, league import, fantasy alerts Pro.

## Not in v1
- Yahoo import (OAuth app registration required).
- IDP (individual defensive players) scoring, beyond what the weights allow.
