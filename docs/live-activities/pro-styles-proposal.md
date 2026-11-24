# Pro Live Activity styles — proposal (options only)

Status: proposal, nothing implemented. Context: 3.5 Live Activity polish (clutch amber,
grey breaks, StandBy big scores) landed on `la-polish`. Pro today covers custom alerts
and Themes; a Live Activity style picker is a natural third visual perk that reuses
the Themes plumbing (`AppAccentReader` → app-group defaults → widget).

Constraints every option must respect:

- **No schema change.** The style is a per-device preference the widget reads from
  app-group defaults (like the Themes accent), never a field on `ContentState` /
  attributes, so server pushes and already-running activities are unaffected.
- **Every presentation keeps working**: Lock Screen, StandBy, Dynamic Island
  compact/expanded/minimal, the iPhone Duo outer island, `.small` (Watch, CarPlay).
  Styles mostly change the Lock Screen and StandBy cards; the island stays
  system-shaped, with at most a keyline/dot treatment.
- **Free stays good.** The current card remains the default for everyone; Pro adds
  alternatives, it doesn't degrade the free look.
- Clutch amber and grey breaks apply in every style (they're information, not decoration).

## Option A — "Scorebug" (broadcast style)

A TV-style score strip: two solid team-colour slabs edge to edge with white codes
and scores, the clock in a dark centre chip, the situation (down & distance, outs
and runners, power play) as a ticker line underneath.

- Looks like what fans already associate with "live", and team colours do the work.
- Cost: low–medium. A new `TeamLockScreenView` variant; colour contrast logic
  (`activityTeamColor`) already exists. Needs a contrast check for light team
  colours (e.g. VGK gold) to pick black vs white text.
- Risk: loud on the Lock Screen; needs a muted night/StandBy fallback.

## Option B — "Minimal" (typography only)

No logos, no wash: two big codes and scores in the app's monospaced ink, a hairline
in the leader's colour, the clock in small caps. Close to the new StandBy layout,
offered on the Lock Screen too.

- Reads at a glance, calm next to notifications; suits people who keep several
  activities going (World Cup group days, NFL Sundays).
- Cost: low. Mostly the StandBy view promoted to a selectable Lock Screen style.
- Risk: weakest "Pro" pull on its own; best bundled with A or C.

## Option C — "Momentum" (data-rich)

The current card plus a compact sparkline of win probability (or score margin
where there's no win probability) over the game so far, with the clutch band
shaded amber, and the last play kept to one line.

- Unique to Scoreline; leans on the win-probability and live-situation work already
  shipped, and on the Pro "insight" direction rather than cosmetics.
- Cost: medium–high. History isn't in `ContentState` (and adding it would grow every
  push), so the widget would build the series from snapshots the app writes to the
  app group on each foreground update — meaning gaps while the app is suspended and
  only server pushes arrive. Would need a server-side compact series field to be
  reliable, which is a schema change and a separate decision.
- Risk: busiest option; must collapse gracefully in StandBy and `.small`.

## Recommendation

Ship A and B together as the first "Live Activity styles" Pro perk (one picker in
Settings > Themes, previews rendered from the existing preview gallery), and keep C
as a later, data-backed upgrade once a compact history field is agreed with the
server. Gate exactly like Themes: the free default always renders; the widget falls
back to it whenever the entitlement flag in app-group defaults is absent.
