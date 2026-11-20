# Cricket

Branch `cricket`. The first new `SportType` case since golf/tennis/racing.

## Data

**ESPN is the only source.** TheSportsDB has 34 cricket leagues but no live scores, patchy internationals
(the live NZ v India Test is missing) and "Australia Cricket" team names.

| Need | Endpoint |
|------|----------|
| Live + today | `site.api.espn.com/apis/site/v2/sports/cricket/scorepanel` |
| Any future/past day | `…/cricket/scorepanel?dates=YYYYMMDD` — every competition that day, incl. tours |
| Per-league calendar | `…/cricket/{espnLeagueId}/scoreboard` → `leagues[0].calendar` |
| Scorecard | `…/cricket/{espnLeagueId}/summary?event={id}` → `rosters`, `matchcards` |

International cricket is organised by ESPN as *tours* with a fresh league id each
("England tour of Australia 2026/27" = 24273), so internationals can't be keyed by ESPN
league id. Instead `competitions[0].class.internationalClassId` says what a match is:
`1` Test, `2` ODI, `3` T20I, `0` not international (others = women's / associate T20I).
Franchise leagues have stable ESPN ids (IPL 8048, BBL 8044, PSL 8679, …).

Score strings arrive pre-formatted: `"137 & 144/2 (40 ov)"`, `"392/9d"`,
`"184 (40.5/50 ov, target 246)"`. `status.summary` carries the state line
("India trail by 209 runs", "Bulls won by 7 wkts (4b rem)"), `status.session` "Day 2".

## Model

`SportType.cricket`, wire key `cricket` (own `LiveScore` bucket — old clients ignore the
unknown key; nothing is folded into an existing bucket, so no old build ever sees a cricket
game). Leagues use TheSportsDB ids where they exist, synthetic ids otherwise:

- Men's internationals by format: Tests, ODIs, T20Is (ICC events fold in by format;
  the event/tour name rides in `tournamentName`, match label "1st T20I" in `round`).
- Franchise T20: IPL, BBL, PSL, SA20, The Hundred, CPL, MLC, ILT20.
- Hidden by default: women's internationals, WBBL, The Hundred (Women), Sheffield Shield,
  County Championship.

No new `Game` field (every `Game(...)` rebuild would drop it). Cricket state maps onto
existing fields: score display → `intHomeScore/intAwayScore`, summary → `lastPlay`,
session → `strProgress`, tour → `tournamentName`, label → `round`, multi-day → `endDate`.
`CricketScore` parses innings (runs/wickets/overs/declared/target) from the display string;
the winner is read from the summary, never by comparing runs (DLS).

## Server

`ESPNCricketJob`: daily scorepanel sweep −7…+120 days → `schedule.cricket`; live poll of the
undated scorepanel while any match is in progress. Multi-day Tests use `endDate` +
`multiDayEventTail` like golf/tennis so the 8h stale-live pruner leaves them alone.
TheSportsDB schedule job skips cricket leagues.

## App

Team path (`isIndividualSport == false`). Int-only score call sites go through a
sport-aware helper so "287/6" isn't read as nil. Settings toggle + competition list,
onboarding, focus filter, intents, widgets/watch tint/icon. v1 shows score strings and the
summary line; a scorecard detail (batting/bowling cards from `summary`) is phase 2.
