# Scoreline for macOS — release TODO

Working checklist to first Mac App Store submission. QA matrix lives in
`MAC_QA_CHECKLIST.md`; port history in the session plan/memory.

## USER — developer portal (one-time, blocks push + kills the App Group prompt)
- [ ] Enable **Push Notifications** on macOS App ID `com.KomodoLLC.SportsCal`
- [ ] Enable **App Groups** (`group.Komodo.SportsCal`) on macOS App IDs for BOTH
      `com.KomodoLLC.SportsCal` and `com.KomodoLLC.SportsCal.SportsWidget`
- [ ] Let Xcode regenerate Mac profiles; confirm they carry push + app group +
      iCloud KVS + calendars

## Code / repo
- [x] Mac app icon (mac idiom set)
- [x] Notification hygiene + notification-tap routing
- [x] Mac-sized sheets (onboarding/paywall/list-detail/browse/glossary)
- [x] Classic menu commands (⌘P/⌘[/⌘]/⇧⌘F/⌥⌘I via MacCommandRelay), ⌘F search,
      ⇧⌘D Go to Date, Settings 520×500
- [x] Widgets on macOS (multiplatform extension, SportsWidget sm/med/lg)
- [x] Tests macOS overhauled (hosted unit bundle, committed snapshot refs,
      App Group round-trip test)
- [x] Phase 4: interactive widget sport tabs on Mac, StandingsWidget on Mac,
      menu-bar footer (Settings…/Quit), MacCalendarGridView month grid with
      per-sport dots (⇧⌘D popover)
- [ ] Commit the Mac work (scope to SportsCal/ — working tree also has
      unrelated server/admin changes)

## Build & submit
- [ ] Push to main → Xcode Cloud "Default" builds iOS + macOS archives
      (track with asc-build-lifecycle)
- [ ] Organizer/ASC Validate passes for the macOS archive (icon, profiles,
      entitlements surface here)
- [ ] Mac screenshots 2880×1800 — framed + captioned like the iPhone set
      (dark canvas, white SF semibold caption, rounded shot + shadow).
      Workflow per shot:
      1. Run the app with good data (favorites followed, live games, dark mode
         to match the iPhone set), stage the surface.
      2. `scripts/capture_mac_window.sh raw/board.png` (frontmost Scoreline
         window, no OS shadow; terminal needs Screen Recording permission)
      3. `swift scripts/frame_mac_screenshot.swift raw/board.png fastlane/screenshots/en-US/APP_DESKTOP_01_2880x1800.png "Live scores for every sport"`
      Shot list + captions:
      - Classic board + inspector open — "Live scores for every sport"
      - World Cup bracket/hub — "Follow the World Cup"
      - Menu bar extra popover (crop region capture) — "Scores in your menu bar"
      - Desktop widgets (small/medium/large staged) — "Widgets for your desktop"
      - Month-grid calendar popover / Go to Date — "Plan around every matchday"
      Upload via asc for both en-US and en-GB.
- [ ] Create macOS platform version on app record 1580232928 via asc
      (universal purchase — same bundle id); adapt description to lead with
      menu-bar live scores + desktop widgets
- [ ] Run MAC_QA_CHECKLIST.md on a signed archive export in a clean user account
- [ ] Submit with review notes: push = score alerts; subscription unlocks
      menu-bar live scores; no account needed to demo

## Later (post-1.0)
- [ ] Setapp flavor (SETAPP_BUILD.md recipe: Setapp config + scheme,
      ARCHS=arm64 x86_64, Setapp.framework, Developer ID + notarize)
- [ ] Icon Composer `.icon` (Tahoe glass treatment)
- [ ] `@FocusedValue` menu enablement + game-detail-window commands
- [ ] Golf/F1 widgets on Mac (files still iOS-gated, commented out of bundle)
