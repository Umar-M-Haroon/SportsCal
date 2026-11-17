# Scoreline for macOS — pre-submission QA checklist

Run this on a signed build (Xcode GUI run or exported archive) before every
Mac App Store submission. Automated gates come first; the manual matrix is
ordered by App-Review risk.

## Automated gates (all must be green)

```bash
# Mac / iOS / watch compile gates (DEVELOPER_DIR is required — xcode-select
# points at CommandLineTools; a bare xcodebuild "succeeds" via tail otherwise)
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app
xcodebuild build -scheme "SportsCal (iOS)" -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme "SportsCal (iOS)" -destination 'generic/platform=iOS'   CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme "SportsCalWatch Watch App" -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO

# Mac test suite (hosted snapshot + widget data-path tests).
# Unsigned run: the App Group round-trip test self-skips.
# Signed run (Xcode GUI / CI): nothing may skip except test_mac_contentView.
xcodebuild test -scheme "Tests macOS" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# Re-record snapshot references after intentional UI changes:
#   TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test -scheme "Tests macOS" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
#   then copy from $TMPDIR/MacSnapshots (unsigned) or
#   ~/Library/Containers/com.KomodoLLC.SportsCal/Data/tmp/MacSnapshots (signed)
#   into "Tests macOS/Snapshots/__Snapshots__/" and commit.
```

## Signing / packaging (exported archive)

- [ ] `codesign --verify --deep --strict Scoreline.app` and `spctl -a -vv Scoreline.app`
- [ ] `Contents/PlugIns/SportsWidgetExtension.appex` present; `codesign -d --entitlements - <appex>` shows app-sandbox + `group.Komodo.SportsCal`
- [ ] App icon renders in Finder/Dock (mac idiom set, rounded rect with margins — not full-bleed)
- [ ] Organizer → Validate App passes (icon, profiles, entitlements surface here)

## First-run experience (clean user account or deleted container)

- [ ] Launch: NO permission prompts before onboarding (notification ask is contextual, fires on onboarding finish / notify button only — never cold)
- [ ] No "access data from other apps" App Group prompt (requires Mac profiles carrying the group — portal action)
- [ ] Onboarding sheet is 640×560, buttons clickable, Esc/⌘W behave
- [ ] Complete onboarding → exactly ONE notification permission ask

## Menus & keyboard (test in BOTH Classic and Ambient themes)

- [ ] Games → Refresh ⌘R, Jump to Today ⌘T, Go to Date… ⇧⌘D (opens calendar popover), Find Game… ⌘F (focuses board search), Previous/Next Day ⌘[ ⌘], Toggle Inspector ⌥⌘I, Show Only Favorites ⇧⌘F
- [ ] Toggle Agenda/Sections (⌘L) is DISABLED outside the efRemix theme
- [ ] File → Print Schedule… ⌘P prints the visible day (Classic board included)
- [ ] ⌘, opens Settings (520×500, four tabs, forms scroll); About window from app menu
- [ ] Board: ←/→ day nav, ⌥↑/⌥↓ cell selection, Return opens game in new window
- [ ] Search: query narrows board columns; empty columns disappear; clearing restores

## Windows & navigation

- [ ] "Open in New Window" (context menu / Return) opens game-detail window
- [ ] Notification tap routes to the game (opens game-detail window)
- [ ] Deep links: sportscal.app game URL → detail; /wc/bracket → World Cup
- [ ] Inspector visibility + width persist across relaunch
- [ ] Window resize to minimum, full screen, multiple main windows (⌘N)
- [ ] Drag a game out of the board → drops matchup text + link

## Widgets (signed build)

- [ ] Widget gallery offers Scoreline (small/medium/large)
- [ ] Widget renders real data (App Group snapshot path) with team badges
- [ ] Widget updates after app refresh; day-offset arrows work
- [ ] Widget tap opens the app

## Menu bar extra

- [ ] Free tier: label is plain icon; popover shows Subscribe prompt → opens paywall in app
- [ ] Pro: label rotates live scores; popover LIVE/FAVORITES/TODAY sections; row click activates app

## Monetization

- [ ] Paywall sheet 480×600+, close button works, Esc dismisses
- [ ] Purchase against sandbox Apple ID (MAS receipt through RevenueCat); Restore works
- [ ] Pro flips: menu bar extra unlocks live scores without relaunch

## Visual

- [ ] Dark mode: board, settings, menu-bar popover, game-detail window
- [ ] Notifications: score alert banner arrives with app quit (push enabled on Mac App ID)

## Known portal prerequisites (one-time, USER)

1. Enable **Push Notifications** on the macOS App ID `com.KomodoLLC.SportsCal`.
2. Enable **App Groups** (`group.Komodo.SportsCal`) on the macOS App IDs for the app AND `com.KomodoLLC.SportsCal.SportsWidget` (kills the Sequoia "access data from other apps" prompt).
3. Confirm regenerated Mac profiles carry push + app group + iCloud KVS + calendars.
