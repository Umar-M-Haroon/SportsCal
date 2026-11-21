# Pro: Custom Live Alerts + Themes — build plan

_2026-10-04 · scope decided: custom live alerts + themes as Pro. **No betting framing** (no lines, props, over/unders, spreads) and **no social system**._

## What exists today

| Piece | State | Where |
|---|---|---|
| Server push for followed teams | ✅ Soccer only: minutely job, Redis device registry, per-game seen-state + per-device SETNX dedupe | `App/SoccerMatch/SoccerAlertJob.swift`, `SoccerAlerts.swift` |
| Score / clutch alerts | ✅ Only for devices with a running Live Activity; capped at 4 clutch alerts per game | `ScheduleJobs/APNSJob.swift:362-422`, `ClutchMoment.swift` |
| Play-by-play | ✅ ESPN `summary` fetched each minute for all team sports (CFB budget 12/tick) | `ESPNFetchJob.enrichWithPlays` |
| **Who made the play** | ❌ `Play` has no athlete ids or participants; soccer events carry names only | `API2/Scoreboard/Play.swift:12` |
| **Live player stats** | ❌ ESPN `boxscore.players` isn't decoded, except in soccer lineups | `TeamStatComparison.swift:195` |
| Following players | ⚠️ `Favorites.players` stores **names**, and only golf/tennis can add to it | `Favorites.swift:20-46` |
| Accent color | ❌ No central accent: empty `AccentColor`, no root `.tint`, ~30 `accentColor` + ~41 hardcoded colors | — |
| Widget / Live Activity colors | ⚠️ A hand-kept copy of the tokens | `SportsWidget/WidgetDesignTokens.swift` |

### Gating gaps found along the way (fix in phase 0)

- `ProFeature.goalAlerts` is **never referenced**. Score and clutch Live Activity alerts are free today, which contradicts the monetization plan.
- `ProFeature.proSettings` is defined but unused. The Pro Options section gates itself with `.disabled(!isPro)`.
- Soccer alert kinds (`SoccerAlertSettingsSection`) aren't Pro-gated. The team count *is* gated: 1 free team.

**Status 2026-11-16 (branch `pro-alerts`):** 3.3 (c154533) already closed the first two. `goalAlerts` gates Live Activity score/clutch alerts (`GameViewModel.activityAlertsAllowed` → `alerts` on `POST /liveActivity`), and Pro Options uses `canUse(.proSettings)`. `customAlerts` and `themes` are now in `ProFeature` (not wired yet). Soccer alert kinds stay ungated on purpose for now. A free user gets every kind for their 1 alert team, the same shape as golf's 1 free golfer, and 3.3 deliberately kept a free user's soccer goal push firing. Whether goal/red-card kinds should move behind `goalAlerts` is an open product call (open question 4).

Also stale above: `boxscore.players` *is* decoded, into the display-ready `PlayerBoxScore` (opt-in on `/plays`). A2.2 adds the numeric `PlayerLiveStatLine` beside it, server-only.

## Feature A — Custom live alerts ("Player Alerts" + "Game Alerts")

Wording rule: **"Notify me when …"**. Use milestone words like "reaches 30 points" or "hits 100 rushing yards". Never "over/under", "line", "prop" or "total" in the betting sense.

### A1. Alert types (v1)

| Kind | Example | Sports v1 | Data needed |
|---|---|---|---|
| **Player play** | "Every 3-pointer by Steph Curry", "Every sack by Myles Garrett", "Every goal by Haaland", "Every HR by Judge" | NBA, NFL, MLB, NHL, soccer | play type + athlete id per play |
| **Player milestone** | "Jokić reaches a triple-double", "Mahomes hits 300 passing yds", "Skubal reaches 10 Ks" | NBA, NFL, MLB, NHL | live per-player box stats |
| **Game situation** | "Any game tied or within 3 in the final 2 min", "Overtime starts", "No-hitter through 6", "Upset brewing (win prob flip)" | all team sports | already computed by `ClutchMoment` / win prob, but needs to fire **without** a Live Activity |

Filters (Real-parity, cheap): "only in the 4th quarter / final 5 min", "only when the game is close". Start with *period* and *close game*; skip shot distance and exit velocity.

### A2. Server work

1. **Decode athletes on plays.** Add `participants: [PlayParticipant]?` (athlete id, name, role) to `Play`, from ESPN `plays[].participants[].athlete.id`. The field is optional, so old clients aren't affected and the payload stays small. Soccer: decode the `athleteID` on `SoccerMatchEvent` from the commentary/keyEvents participants.
2. **Decode player box stats.** Parse `boxscore.players[]` into a `PlayerLiveStatLine {athleteID, name, teamID, stats: [key: Double]}`, server-side only: store it in Redis per event and **don't** ship it in `/schedules` (bloat lesson, see the payload-bloat memory). The fetch is already happening; this is decode-only.
3. **`CustomAlertJob`** (copy of the `SoccerAlertJob` pattern):
   - Registration: `POST /notifications/custom` with `{token, rules:[AlertRule]}`. Stored at `CustomAlertDevice-{install}` with a 30d TTL; index set; `debug-` prefix for sandbox.
   - Index rules by athleteID / teamID → devices, so a tick only touches games that have subscribers.
   - Each tick, for live games with subscribers: diff new plays since `CustomAlertState-{event}.lastPlayID` → match player-play rules; compare stat lines with the last-seen ones → fire a milestone when crossed (once per rule per game); situations come from `ClutchMoment`, reused without the Live Activity requirement.
   - Dedupe: per-device `SETNX CustomAlertSent-{install}-{ruleID}-{event}-{playID|milestone}` with a 24h TTL; on the first look at a game, mark everything seen (as soccer does).
   - Caps: at most N pushes per device per game (default 15), with collapse/thread-id = eventID so a run of 3s stacks.
   - **Server-side Pro check:** registrations carry an App Store receipt / RevenueCat app-user-id; verify via the RevenueCat REST API (cached 6h). Without it, any client could flip a flag and get free Pro alerts.
   - **Status 2026-11-20 (phase 3 built, branch `worktree-agent-a878a45eb3279bd81`):** `CustomAlertJob` (minutely :45), `POST/DELETE /notifications/custom`, `POST /notifications/custom/mute`. Shared types in `SportsCalModel/.../CustomAlerts.swift` (`AlertRule`, `CustomAlertRegistration[Response]`, `CustomAlertLimits`, `CustomAlertNotification` category/action/payload keys). Rule `teamID` is the app's `Game.idHomeTeam/idAwayTeam`. Redis: `CustomAlertDevice-{install}`, `CustomAlertScopes` + `CustomAlertScope-{team:sport:id|sport:sport}`, `CustomAlertState-{event}`, `CustomAlertSent-…`, `CustomAlertCount-{install}-{event}`, `CustomAlertMute-…`, `RevenueCatPro-{hash}`. Prod needs `REVENUECAT_SECRET_KEY` (without it everyone is capped as free).
4. **Latency:** alerts are evaluated once a minute today. v1 accepts about 60s ("within a minute"). Later, hook into the 15s `LiveTicker` for subscribed games only.
5. **Merge soccer alerts into this pipeline** in a later phase, so there's one registry, one dedupe and one cap.

### A3. Client work

1. **Follow a player.** Add `Favorites.followedPlayers: [PlayerRef {athleteID, name, sport, teamID}]`, migrating from the name-only `players` (keep it for golf/tennis). Entry points: soccer player page (exists), box score / game leaders rows, and the team roster (team pages exist).
2. **Alert builder sheet** (`PlayerAlertSheet`): pick play types per sport (chips), pick milestones (stat + number stepper with sensible presets: 20/30/40 pts, 100/150 yds, 10 Ks), and an optional filter (final period only / close game only).
3. **Game Alerts** settings section: toggles per situation, with sports and teams scoped to favorites or all.
4. **`CustomAlertRegistrar`** (clone of `SoccerAlertRegistrar`): sync rules when they change or weekly; include the RevenueCat app-user-id.
5. **Gating:** new `ProFeature.customAlerts`. Free users get **1 player with 1 rule** (taste) plus all situation previews locked; Pro is unlimited. Hitting the limit → `UpsellCoordinator` with trigger `custom_alert_cap`.
6. Notification categories: "Mute this player for this game" / "Turn off this alert" actions.

## Feature B — Themes (Pro)

1. **Central accent first (no UI yet).** Add an `AppAccent` value stored in app-group UserDefaults; apply a root `.tint(appAccent)` in `SportsCalApp`; fill the `AccentColor` asset with the current blue so nothing changes visually. Sweep the ~41 hardcoded `Color.blue`-style UI accents and the 11 `.tint(` literals onto the accent token. **Leave semantic colors alone**: live red, sport colors, team colors, win/loss.
2. **Theme set:** about 12 curated accents (system blue default, plus e.g. Pitch Green, Gridiron Orange, Ice, Crimson, Gold, Purple, Teal, Pink, Graphite, Mint, "Team colors" = your #1 favorite team's primary color), plus a custom color picker (`ColorPicker`), Pro only.
3. **Widgets / Live Activities / Watch** read the accent from app-group defaults in `WidgetDesignTokens` (it's already a hand-copied file, so add one shared reader). Live Activities keep team colors; only chrome and progress use the accent.
4. **Alternate app icons** (cheap and highly visible): 4–6 icons matching the themes, using `setAlternateIconName`.
5. **Gating:** picker visible to everyone with live preview; applying it requires Pro (preview → paywall with trigger `theme`). Fold the existing Pro Options section under `canUse(.proSettings)` while we're here.

## Phasing

| Phase | Contents | Size | Ships in |
|---|---|---|---|
| **0** | Fix gating gaps (goalAlerts / proSettings wiring), add `customAlerts` + `themes` to `ProFeature` | S | 3.3 |
| **1** | Themes: central accent + sweep + curated picker + custom color + alt icons + widget read | M | 3.3 or 3.4 |
| **2** | Server data: `Play.participants`, player box stats in Redis (decode-only, no payload growth), tests on recorded ESPN JSON | M | server deploy first |
| **3** | `CustomAlertJob` + registration + RevenueCat entitlement check + caps/dedupe | M–L | server |
| **4** | Client: follow player, alert builder, Game Alerts settings, registrar, gating/upsell | M–L | 3.4 headline |
| **5** | Fold soccer alerts in; 15s ticker for subscribed games; screenshots/listing ("Know the moment your player scores") | M | 3.4/3.5 |

Themes ship first: they're client-only, fast, and give the paywall a visible perk while the alert pipeline is built. Alerts need server phases 2–3 deployed before the 3.4 app, following the "server deploys before app" rule.

## Open questions

1. **Free taste for custom alerts:** 1 player / 1 rule free (recommended), or Pro-only?
2. **Should score/clutch Live Activity alerts become Pro** once `goalAlerts` is wired? That's a behavior change for current free users. Alternative: keep them free and make custom alerts the Pro line.
3. **CFB player alerts:** DECIDED 2026-11-17: off for v1 (no college player alerts).
4. **Soccer alert kinds:** (a) keep as is: every kind for the 1 free team, Pro = all teams (current); (b) goals, red cards, missed pens and VAR need `goalAlerts`, while lineups and HT/FT stay free for the 1 team (this changes things for current free users); (c) all soccer match alerts are Pro.
5. **NFL player alerts:** DECIDED 2026-11-17: off for v1, plays and milestones both. ESPN's site summary gives drive plays no `participants`, so revisit later. v1 = NBA, MLB, NHL, soccer.
