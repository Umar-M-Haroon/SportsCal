//
//  ModernDayPage.swift
//  SportsCal — Design System v1.0 (Phase D.1)
//
//  Adaptive Today/Day screen — replaces EFRemixDayPage under the .efRemix
//  ("Modern") theme. Auto-switches between:
//    - Light Day (≤3 live games): hero card + later list
//    - Heavy Day (8+ live games): top "For You" list + 2-col grid grouped by sport
//    - Empty state: configurable EmptyStateView
//
//  Reads from `viewModel.filteredGames` directly — bypasses the stale
//  `gamesDict` path that broke EFRemixDayPage. Same data path Browse and
//  Calendar already use successfully.
//
//  Built entirely from Phase B primitives: LiveGameRow, PreGameRow,
//  FinalGameRow, CompactGameTile, EmptyStateView, .appCard, .appEyebrow.
//

import SwiftUI
import SportsCalModel

struct ModernDayPage: View {
    /// Days addressable by left/right swipe, expressed as offsets from today
    /// (0 = today, -1 = yesterday). Wide enough for postseason/series context
    /// without instantiating dozens of subviews.
    private static let dayRange: ClosedRange<Int> = -7...14

    @State private var dayOffset: Int = 0

    private static let calendar = Calendar.current

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                weekStrip
                    .padding(.top, .appSpace1)
                    .padding(.bottom, .appSpace2)
                Divider().background(Color.appDivider)
                #if os(macOS)
                // Paged `TabView(.page)` is iOS-only. On Mac the week-strip
                // chips already drive day selection, so just render the
                // selected day's content directly. `.id(dayOffset)` makes
                // SwiftUI swap subviews on day change instead of animating
                // a missing TabView transition.
                ModernDayContent(date: Self.date(forOffset: dayOffset))
                    .id(dayOffset)
                #else
                TabView(selection: $dayOffset) {
                    ForEach(Array(Self.dayRange), id: \.self) { offset in
                        ModernDayContent(date: Self.date(forOffset: offset))
                            .tag(offset)
                    }
                }
                // `.never` hides the dot row — ranges of 20+ make it unreadable.
                // The strip above already shows position.
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
            }
        }
        #if !os(macOS)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .appSpace2) {
                    ForEach(Array(Self.dayRange), id: \.self) { offset in
                        dayChip(offset: offset)
                            .id(offset)
                    }
                }
                .padding(.horizontal, .appSpace4)
            }
            .onAppear {
                proxy.scrollTo(dayOffset, anchor: .center)
            }
            .onChange(of: dayOffset) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func dayChip(offset: Int) -> some View {
        let date = Self.date(forOffset: offset)
        let selected = offset == dayOffset
        let isTodayChip = offset == 0

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                dayOffset = offset
            }
        } label: {
            VStack(spacing: 2) {
                Text(Self.weekdayAbbr(date))
                    .font(.appFootnote)
                    .tracking(1)
                    .foregroundStyle(selected ? Color.appBackground : Color.appInkSoft)
                Text(Self.dayNumber(date))
                    .font(.appHeadline)
                    .fontWeight(selected ? .bold : .semibold)
                    .foregroundStyle(selected ? Color.appBackground : Color.appInk)
            }
            .frame(minWidth: 38)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.appInk : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isTodayChip && !selected ? Color.appInk : Color.appDivider,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Self.accessibilityLabelFormatter.string(from: date)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Helpers

    private static func date(forOffset offset: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private static func weekdayAbbr(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private static func dayNumber(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private static let accessibilityLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()
}

/// One day's content. Extracted so the parent `ModernDayPage` can host a paged
/// `TabView` of these. Reads filtering directly from the supplied `date` so
/// each page is independent — no shared selection state between pages.
private struct ModernDayContent: View {
    let date: Date

    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites
    @Environment(EngagementTracker.self) private var engagementTracker
    @Environment(SubscriptionManager.self) private var subscriptionManager
    #if os(iOS)
    @Environment(NativeAdManager.self) private var adManager
    #endif

    /// Per-sport sections collapse state. Mirrors classic's
    /// `collapsedSportSections`. View-local — resets on view rebuild,
    /// which is fine for swipe-between-days use.
    @State private var collapsedSports: Set<SportType> = []
    @State private var showHidden: Bool = false

    private var selectedDate: Date { date }

    private let calendar = Calendar.current
    private static let eyebrowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f
    }()

    // MARK: - Data

    private var isToday: Bool { calendar.isDateInToday(selectedDate) }

    /// All games on the selected date — read from `totalGames` (NOT
    /// `filteredGames`) so past games of today still appear as Finals.
    /// `filteredGames` would silently drop them via `hidePastEvents`.
    /// Sport / hidden-competition prefs are applied inline.
    private var dayGames: [Game] {
        // Touch the tracked preferenceVersion so this view re-evaluates when
        // hiddenCompetitions / favoritesOnlyCompetitions change — those AppStorage
        // properties are @ObservationIgnored and don't drive Observation on their own.
        _ = storage.preferenceVersion
        let start = calendar.startOfDay(for: selectedDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let perCompetitionFavorites = Set(storage.favoritesOnlyCompetitions)
        return (viewModel.totalGames ?? [])
            .filter { game in
                // Date filter
                guard let d = game.standardDate, d >= start, d < end else { return false }
                // Sport pref filter
                guard let sport = game.sportType, isSportEnabled(sport) else { return false }
                // Resolve league once for the hidden / per-competition checks.
                let league: Leagues? = {
                    guard let id = game.idLeague, let intID = Int(id) else { return nil }
                    return Leagues(rawValue: intID)
                }()
                // Hidden competition filter (mirrors filterAndSortGamesFromUserPreferences)
                if let leagueName = league?.leagueName,
                   storage.hiddenCompetitions.contains(leagueName) {
                    return false
                }
                // Per-sport favorites-only: when toggled in SportPickerSheet,
                // hide non-favorite games for that sport so only the user's
                // favorite teams surface in this sport's section.
                if storage.favoritesOnly(for: sport), !favorites.matches(game) {
                    return false
                }
                // Per-competition favorites-only: when toggled in CompetitionView
                // (e.g. "favorites only for La Liga"), only show games in that
                // competition that match a favorite team. Other competitions in
                // the same sport are unaffected.
                if let leagueName = league?.leagueName,
                   perCompetitionFavorites.contains(leagueName),
                   !favorites.matches(game) {
                    return false
                }
                return true
            }
            .sorted { ($0.standardDate ?? .distantPast) < ($1.standardDate ?? .distantPast) }
    }

    private func isSportEnabled(_ sport: SportType) -> Bool {
        switch sport {
        case .basketball: return storage.shouldShowNBA || storage.shouldShowWNBA
        case .soccer:     return storage.shouldShowSoccer
        case .hockey:     return storage.shouldShowNHL
        case .mlb:        return storage.shouldShowMLB
        case .nfl:        return storage.shouldShowNFL
        case .golf:       return storage.shouldShowGolf
        case .tennis:     return storage.shouldShowTennis
        case .racing:     return storage.shouldShowRacing
        }
    }

    /// Three-way classifier for a game on `selectedDate`. Used everywhere
    /// state is consumed so live/upcoming/final stay consistent.
    ///
    /// Priorities, in order:
    ///   1. Status code is `pre` / `NS` / `not started` → `.pre`. **Must
    ///      match before `hasDoneStatus`** — that helper's "is not in
    ///      progress" semantics include `pre`/`NS`, which would otherwise
    ///      misclassify upcoming games as final and surface
    ///      `FinalGameRow` rendering "FINAL · TIE" for a 0-0 score.
    ///   2. ID is in `viewModel.liveEvents` → `.live`
    ///   3. `game.hasDoneStatus` is true → `.final`
    ///   4. Start date is in the future → `.pre`
    ///   5. Start date is in the past, within last 6h → `.live` (in-progress
    ///      heuristic for cases where we don't have a live event yet)
    ///   6. Start date is in the past, more than 6h ago → `.final` (assumed
    ///      finished even if `hasDoneStatus` hasn't flipped — server-side
    ///      flag lag should not surface as "SOON" hours after kickoff)
    private enum GameState { case live, final, pre }

    private func gameState(_ game: Game) -> GameState {
        let s = (game.strStatus ?? "").lowercased()
        let p = (game.strProgress ?? "").lowercased()
        if s == "pre" || s == "ns" || s == "not started" || p == "pre" {
            return .pre
        }
        let liveIDs = Set(viewModel.liveEvents.map(\.id))
        if liveIDs.contains(game.id) { return .live }
        if game.hasDoneStatus { return .final }
        guard let d = game.standardDate else { return .pre }
        let now = Date()
        if d > now { return .pre }
        let elapsed = now.timeIntervalSince(d)
        if elapsed < 6 * 60 * 60 { return .live }
        return .final
    }

    /// Live games on the selected date. Today only — past/future days
    /// don't have live state.
    private var liveGames: [Game] {
        guard isToday else { return [] }
        return dayGames.filter { gameState($0) == .live }
    }

    private var upcomingGames: [Game] {
        dayGames
            .filter { gameState($0) == .pre }
            .sorted { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
    }

    private var finalGames: [Game] {
        dayGames
            .filter { gameState($0) == .final }
            .sorted { ($0.standardDate ?? .distantPast) > ($1.standardDate ?? .distantPast) }
    }

    private var favoriteGames: [Game] {
        dayGames.filter { favorites.contains($0) }
    }

    // MARK: - Headlines

    private var eyebrowText: String {
        let datePart = Self.eyebrowFormatter.string(from: selectedDate).uppercased()
        if isToday {
            if liveGames.count >= 8 { return "\(datePart) · BUSY DAY" }
            return "\(datePart) · TODAY"
        }
        let dir = calendar.compare(selectedDate, to: Date(), toGranularity: .day)
        return "\(datePart) · \(dir == .orderedAscending ? "PAST" : "UPCOMING")"
    }

    private var headlineText: String {
        if isToday {
            switch liveGames.count {
            case 0:
                if dayGames.isEmpty { return "nothing on today" }
                return upcomingGames.isEmpty ? "all wrapped up" : "quiet night"
            case 1: return "1 live"
            case let n where n < 4: return "\(n) live"
            case let n where n < 8: return "\(n) live, busy"
            default: return "\(liveGames.count) live, all yours"
            }
        }
        let count = dayGames.count
        if count == 0 { return "nothing scheduled" }
        let dir = calendar.compare(selectedDate, to: Date(), toGranularity: .day)
        if dir == .orderedAscending {
            return count == 1 ? "1 game · final" : "\(count) games · final"
        }
        return count == 1 ? "1 on tap" : "\(count) on tap"
    }

    // MARK: - Body

    var body: some View {
        // No background fill here — the parent `ModernDayPage` owns the
        // background so swipes between days don't flash through to white.
        VStack(spacing: 0) {
            header
                .padding(.horizontal, .appSpace4)
                .padding(.top, .appSpace2)
                .padding(.bottom, .appSpace3)

            ScrollView {
                VStack(alignment: .leading, spacing: .appSpace4) {
                    switch dayState {
                    case .loading:       loadingBody
                    case .failed:        failedBody
                    case .allSportsOff:  allSportsOffBody
                    case .empty:         emptyBody
                    case .hasGames:
                        structuredBody
                    }
                }
                .padding(.bottom, .appSpace6)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrowText).appEyebrow()
                Text(headlineText)
                    .font(.appDisplay)
                    .lineLimit(2)
            }
            Spacer()
            if !liveGames.isEmpty {
                LiveCountPill(count: liveGames.count)
            }
        }
    }

    // MARK: - Structured day body
    //
    // Replaces the prior Light Day / Heavy Day adaptive split. Same data,
    // but always organized into the same section ordering inspired by
    // classic's `DayPage`: Live → Your Teams → For You → per-sport →
    // hidden footer. Each section renders only when populated.
    //
    // Section computation runs once per body re-eval into `sectionData`,
    // with downstream sections excluding IDs already shown upstream so
    // games never duplicate.

    @ViewBuilder
    private var structuredBody: some View {
        let data = sectionData
        liveSection(games: data.live)
        yourTeamsSection(games: data.yourTeams)
        forYouSection(games: data.forYou)
        bySportWithAds(data.bySport)
        hiddenFooter(games: data.hidden)
    }

    /// Per-sport sections with ads sprinkled between them, mirroring legacy
    /// `DayPage.swift:533` behavior. Slots come from
    /// `AdInsertionHelper.sectionAdSlots` so distribution scales with section
    /// count and respects `AdConfiguration.maxAdsPerScreen`. Pro users / kill
    /// switch / non-iOS get the plain section stream.
    @ViewBuilder
    private func bySportWithAds(_ sections: [(SportType, [Game])]) -> some View {
        #if os(iOS)
        let adsActive = !subscriptionManager.isPro && AdConfiguration.isEnabled
        let adSlots: Set<Int> = adsActive
            ? AdInsertionHelper.sectionAdSlots(
                sectionCount: sections.count,
                maxAds: AdConfiguration.maxAdsPerScreen)
            : []
        ForEach(Array(sections.enumerated()), id: \.element.0) { index, pair in
            sportSection(sport: pair.0, games: pair.1)
            if adSlots.contains(index), let ad = adManager.adForSlot(index) {
                NativeAdCardView(nativeAd: ad)
                    .padding(.horizontal, .appSpace4)
            }
        }
        #else
        ForEach(sections, id: \.0) { (sport, games) in
            sportSection(sport: sport, games: games)
        }
        #endif
    }

    /// Pre-computed section buckets. Iteration order matters: each bucket
    /// excludes IDs already claimed by an earlier bucket.
    private struct SectionData {
        let live: [Game]
        let yourTeams: [Game]
        let forYou: [Game]
        let bySport: [(SportType, [Game])]
        let hidden: [Game]
    }

    private var sectionData: SectionData {
        var seen: Set<String> = []

        // Live — favorites first within, then by start time.
        let live = liveGames.sorted { a, b in
            let af = favorites.contains(a)
            let bf = favorites.contains(b)
            if af != bf { return af }
            return (a.standardDate ?? .distantPast) < (b.standardDate ?? .distantPast)
        }
        seen.formUnion(live.map(\.id))

        // Your Teams — favorited team games not already in Live.
        // Order: live > upcoming > final, then start time.
        let yourTeams = dayGames
            .filter { favorites.contains($0) && !seen.contains($0.id) }
            .sorted { a, b in
                let oa = stateRank(a)
                let ob = stateRank(b)
                if oa != ob { return oa < ob }
                return (a.standardDate ?? .distantPast) < (b.standardDate ?? .distantPast)
            }
        seen.formUnion(yourTeams.map(\.id))

        // For You — engagement-suggested teams (excludes anything above).
        let suggestedNames = engagementTracker.suggestedTeamNames(excluding: favorites.teams)
        let forYou: [Game]
        if suggestedNames.isEmpty {
            forYou = []
        } else {
            forYou = dayGames.filter { game in
                guard !seen.contains(game.id) else { return false }
                return suggestedNames.contains(game.strHomeTeam) ||
                       suggestedNames.contains(game.strAwayTeam)
            }
        }
        seen.formUnion(forYou.map(\.id))

        // Per-sport — everything else, grouped, ordered by user's sport order.
        let remaining = dayGames.filter { !seen.contains($0.id) }
        var grouped: [SportType: [Game]] = [:]
        for game in remaining {
            guard let sport = game.sportType else { continue }
            grouped[sport, default: []].append(game)
        }
        let bySport: [(SportType, [Game])] = storage.orderedSports.compactMap { sport in
            guard let games = grouped[sport], !games.isEmpty else { return nil }
            // Sort: live > upcoming > final, then by start time.
            let sorted = games.sorted { a, b in
                let oa = stateRank(a)
                let ob = stateRank(b)
                if oa != ob { return oa < ob }
                return (a.standardDate ?? .distantPast) < (b.standardDate ?? .distantPast)
            }
            return (sport, sorted)
        }

        // Hidden — games on this date dropped by sport-pref or hidden-
        // competition filters. Diff against the visible `dayGames` set.
        let visibleIDs = Set(dayGames.map(\.id))
        let hidden = allDayGamesIgnoringPrefs.filter { !visibleIDs.contains($0.id) }

        return SectionData(live: live, yourTeams: yourTeams, forYou: forYou, bySport: bySport, hidden: hidden)
    }

    /// `live` ranks before `pre` ranks before `final` for sort stability.
    private func stateRank(_ game: Game) -> Int {
        switch gameState(game) {
        case .live:  return 0
        case .pre:   return 1
        case .final: return 2
        }
    }

    /// Heuristic — close score in the last quarter / period, or playoff
    /// context if known. Conservative so the "CLOSE" tag means something.
    /// Used by `LiveGameRow.leverageLabel` inside `rowFor(_:)`.
    private func isLeverage(_ game: Game) -> Bool {
        if game.playoff != nil { return true }
        let home = Int(game.intHomeScore ?? "") ?? 0
        let away = Int(game.intAwayScore ?? "") ?? 0
        return abs(home - away) <= 5 && (game.strProgress?.contains("4") ?? false)
    }

    /// All games on the selected date, ignoring sport prefs and hidden
    /// competitions. Used to diff against `dayGames` for the hidden footer.
    private var allDayGamesIgnoringPrefs: [Game] {
        let start = calendar.startOfDay(for: selectedDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return (viewModel.totalGames ?? [])
            .filter { game in
                guard let d = game.standardDate, d >= start, d < end else { return false }
                return true
            }
            .sorted { ($0.standardDate ?? .distantPast) < ($1.standardDate ?? .distantPast) }
    }

    // MARK: - Section view builders

    @ViewBuilder
    private func liveSection(games: [Game]) -> some View {
        if !games.isEmpty {
            sectionEyebrowRow(text: "LIVE · \(games.count)", icon: nil)
            LazyVStack(spacing: .appSpace2) {
                gameRowsWithAds(games, slotOffset: 0)
            }
        }
    }

    @ViewBuilder
    private func yourTeamsSection(games: [Game]) -> some View {
        if !games.isEmpty {
            sectionEyebrowRow(text: "★ YOUR TEAMS · \(games.count)", icon: nil)
                .foregroundStyle(Color.appStar)
            LazyVStack(spacing: .appSpace2) {
                gameRowsWithAds(games, slotOffset: 100)
            }
        }
    }

    @ViewBuilder
    private func forYouSection(games: [Game]) -> some View {
        if !games.isEmpty {
            sectionEyebrowRow(text: "FOR YOU · \(games.count)", icon: nil)
            LazyVStack(spacing: .appSpace2) {
                gameRowsWithAds(games, slotOffset: 200)
            }
        }
    }

    /// Renders a flat list of games and interleaves a `NativeAdCardView`
    /// every `AdConfiguration.adaptiveInterval` rows when the list is at least
    /// 5 games long. `slotOffset` shifts the `adForSlot` index so Live /
    /// Your Teams / For You don't all start with the same cached ad in view.
    @ViewBuilder
    private func gameRowsWithAds(_ games: [Game], slotOffset: Int) -> some View {
        #if os(iOS)
        let adsActive = !subscriptionManager.isPro
            && AdConfiguration.isEnabled
            && games.count >= 5
        let adIndexSet: Set<Int> = adsActive
            ? Set(AdInsertionHelper.gameAdIndices(
                totalGames: games.count,
                every: AdConfiguration.adaptiveInterval(forGameCount: games.count),
                maxAds: AdConfiguration.maxAdsPerScreen))
            : []
        ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
            rowLink(game)
            if adIndexSet.contains(index),
               let ad = adManager.adForSlot(slotOffset + index) {
                NativeAdCardView(nativeAd: ad)
                    .padding(.horizontal, .appSpace4)
            }
        }
        #else
        ForEach(games, id: \.id) { game in
            rowLink(game)
        }
        #endif
    }

    /// Per-sport section with chevron toggle. Compact 2-col grid when the
    /// section has ≥5 games; full rows otherwise. Mirrors classic's
    /// collapsible behavior via a per-view `Set<SportType>`.
    @ViewBuilder
    private func sportSection(sport: SportType, games: [Game]) -> some View {
        let isCollapsed = collapsedSports.contains(sport)
        VStack(alignment: .leading, spacing: .appSpace2) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isCollapsed { collapsedSports.remove(sport) }
                    else { collapsedSports.insert(sport) }
                }
            } label: {
                HStack(spacing: .appSpace2) {
                    Image(systemName: sport.systemImage)
                        .imageScale(.small)
                        .foregroundStyle(Color.app(sport))
                    Text("\(sport.displayName.uppercased()) · \(games.count)")
                        .appEyebrow()
                    Spacer()
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .foregroundStyle(Color.appInkFaint)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, .appSpace4)
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                if games.count >= 5 {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: .appSpace2),
                        GridItem(.flexible(), spacing: .appSpace2),
                    ], spacing: .appSpace2) {
                        ForEach(games, id: \.id) { game in
                            tileLink(game)
                        }
                    }
                    .padding(.horizontal, .appSpace4)
                } else {
                    LazyVStack(spacing: .appSpace2) {
                        ForEach(games, id: \.id) { game in
                            rowLink(game)
                        }
                    }
                }
            }
        }
    }

    /// Footer revealing games that sport-pref / hidden-competition filters
    /// dropped from this day's view. Matches classic's "Peek at hidden" UX.
    @ViewBuilder
    private func hiddenFooter(games: [Game]) -> some View {
        if !games.isEmpty {
            VStack(alignment: .leading, spacing: .appSpace2) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showHidden.toggle()
                    }
                } label: {
                    HStack(spacing: .appSpace2) {
                        Image(systemName: "eye.slash")
                            .imageScale(.small)
                            .foregroundStyle(Color.appInkFaint)
                        Text("\(games.count) HIDDEN")
                            .appEyebrow()
                            .foregroundStyle(Color.appInkFaint)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                            .rotationEffect(.degrees(showHidden ? 0 : -90))
                            .foregroundStyle(Color.appInkFaint)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, .appSpace4)
                }
                .buttonStyle(.plain)

                if showHidden {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: .appSpace2),
                        GridItem(.flexible(), spacing: .appSpace2),
                    ], spacing: .appSpace2) {
                        ForEach(games, id: \.id) { game in
                            tileLink(game)
                        }
                    }
                    .padding(.horizontal, .appSpace4)
                }
            }
        }
    }

    // MARK: - Section helpers

    /// Eyebrow header used by Live, Your Teams, For You. Optional leading icon.
    private func sectionEyebrowRow(text: String, icon: String?) -> some View {
        HStack(spacing: .appSpace2) {
            if let icon {
                Image(systemName: icon)
                    .imageScale(.small)
            }
            Text(text).appEyebrow()
            Spacer()
        }
        .padding(.horizontal, .appSpace4)
    }

    /// Wraps `rowFor(_:)` in a NavigationLink with the standard horizontal
    /// padding. Centralizes the link plumbing so each section helper stays
    /// focused on its layout.
    private func rowLink(_ game: Game) -> some View {
        NavigationLink {
            adaptiveDestination(for: game)
        } label: {
            rowFor(game)
                .padding(.horizontal, .appSpace4)
        }
        .buttonStyle(.plain)
    }

    /// `compactTileFor(_:)` wrapped in a NavigationLink. Used inside
    /// per-sport grids and the hidden footer's grid.
    private func tileLink(_ game: Game) -> some View {
        NavigationLink {
            adaptiveDestination(for: game)
        } label: {
            compactTileFor(game)
        }
        .buttonStyle(.plain)
    }

    /// Pushes the user-selected theme's game-detail screen via the
    /// `AdaptiveGameDetail` router. Synthesizes Team objects when the lookup
    /// returns nil — same fallback `AdaptiveGameDetail.init(gwt:)` uses.
    @ViewBuilder
    private func adaptiveDestination(for game: Game) -> some View {
        let teams = viewModel.getTeams(for: game)
        AdaptiveGameDetail(
            game: game,
            homeTeam: teams?.home ?? Team(strTeam: game.strHomeTeam),
            awayTeam: teams?.away ?? Team(strTeam: game.strAwayTeam)
        )
    }

    // MARK: - Row builders

    @ViewBuilder
    private func rowFor(_ game: Game) -> some View {
        let sport = game.sportType ?? .basketball
        let matchup = "\(game.strAwayTeam) · \(game.strHomeTeam)"
        let awayURL = badgeURL(for: game.strAwayTeamBadge)
        let homeURL = badgeURL(for: game.strHomeTeamBadge)
        switch gameState(game) {
        case .live:
            LiveGameRow(
                sport: sport,
                matchup: matchup,
                scoreLine: scoreLine(for: game),
                period: game.strProgress ?? "Live",
                clock: nil,
                subtext: nil,
                leverageLabel: isLeverage(game) ? "CLOSE" : nil,
                awayBadgeURL: awayURL,
                homeBadgeURL: homeURL
            )
        case .final:
            FinalGameRow(
                sport: sport,
                homeAbbr: game.strHomeTeam,
                awayAbbr: game.strAwayTeam,
                homeScore: Int(game.intHomeScore ?? "") ?? 0,
                awayScore: Int(game.intAwayScore ?? "") ?? 0,
                awayBadgeURL: awayURL,
                homeBadgeURL: homeURL
            )
        case .pre:
            PreGameRow(
                sport: sport,
                matchup: "\(game.strAwayTeam) vs \(game.strHomeTeam)",
                kickoffLabel: kickoffLabel(for: game),
                countdown: countdownFor(game),
                contextLine: nil,
                awayBadgeURL: awayURL,
                homeBadgeURL: homeURL
            )
        }
    }

    @ViewBuilder
    private func compactTileFor(_ game: Game) -> some View {
        let sport = game.sportType ?? .basketball
        // Grid tiles use shortened names — `getTeams(for:)` falls back to the
        // long name when no short is available, so worst case we still get
        // something readable.
        let teams = viewModel.getTeams(for: game)
        let awayShort = teams?.away.strTeamShort ?? teams?.away.strTeam ?? game.strAwayTeam
        let homeShort = teams?.home.strTeamShort ?? teams?.home.strTeam ?? game.strHomeTeam
        let compactMatchup = "\(awayShort) · \(homeShort)"
        let awayURL = badgeURL(for: game.strAwayTeamBadge)
        let homeURL = badgeURL(for: game.strHomeTeamBadge)
        switch gameState(game) {
        case .live:
            CompactGameTile(
                sport: sport,
                state: .live,
                shortStatus: game.strProgress ?? "LIVE",
                matchup: compactMatchup,
                scoreLine: scoreLine(for: game),
                awayBadgeURL: awayURL,
                homeBadgeURL: homeURL
            )
        case .final:
            CompactGameTile(
                sport: sport,
                state: .final,
                shortStatus: "FINAL",
                matchup: compactMatchup,
                scoreLine: scoreLine(for: game),
                awayBadgeURL: awayURL,
                homeBadgeURL: homeURL
            )
        case .pre:
            CompactGameTile(
                sport: sport,
                state: .pre,
                shortStatus: kickoffLabel(for: game),
                matchup: compactMatchup,
                scoreLine: nil,
                awayBadgeURL: awayURL,
                homeBadgeURL: homeURL
            )
        }
    }

    /// Resolves a TheSportsDB / ESPN badge URL string to a URL, applying the
    /// `/preview` rewrite TheSportsDB uses to serve a smaller variant —
    /// matches the same helper in `ModernGameDetailView`.
    private func badgeURL(for raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.contains("thesportsdb.com") {
            return URL(string: raw + "/preview")
        }
        return URL(string: raw)
    }

    // MARK: - Hero card (deprecated)
    //
    // Kept for reference / cheap re-introduction. Not called from
    // `structuredBody`; the Live section now foregrounds in-progress games
    // as rows. If we want a marquee card again we can call this from a
    // "marqueeSection" gated on solo-live-game / solo-live-favorite cases.

    @ViewBuilder
    private func heroCard(for game: Game) -> some View {
        let sport = game.sportType ?? .basketball
        let state = gameState(game)
        let stateLabel: String = {
            switch state {
            case .live:  return "LIVE"
            case .final: return "FINAL"
            case .pre:   return "SOON"
            }
        }()
        VStack(alignment: .leading, spacing: .appSpace3) {
            HStack(spacing: .appSpace2) {
                Circle().fill(Color.app(sport)).frame(width: 7, height: 7)
                Text("\(leagueLabel(for: game)) · \(stateLabel)")
                    .appEyebrow()
                    .foregroundStyle(Color.app(sport))
                Spacer()
                if favorites.contains(game) {
                    Text("★ FAV")
                        .font(.appFootnote)
                        .tracking(1.5)
                        .foregroundStyle(Color.appStar)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.strAwayTeam)
                        .font(.appHeadline)
                    Text(game.strHomeTeam)
                        .font(.appHeadline)
                }
                Spacer()
                if state == .pre {
                    Text(kickoffLabel(for: game))
                        .font(.appHeadline)
                        .foregroundStyle(Color.appInkSoft)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(game.intAwayScore ?? "—")
                            .font(.appScore)
                        Text(game.intHomeScore ?? "—")
                            .font(.appScore)
                    }
                }
            }

            if state == .live, let progress = game.strProgress, !progress.isEmpty {
                Text(progress.uppercased())
                    .font(.appCaption)
                    .tracking(1.5)
                    .foregroundStyle(Color.app(sport))
            }
        }
        .appCard(fill: Color.appTint(sport))
    }

    // MARK: - Empty / loading / error states

    private enum DayState { case loading, failed, allSportsOff, empty, hasGames }

    private var dayState: DayState {
        let total = viewModel.totalGames ?? []
        if viewModel.networkState == .loading && total.isEmpty { return .loading }
        if viewModel.networkState == .failed && total.isEmpty { return .failed }

        let anySportOn = storage.shouldShowNBA || storage.shouldShowWNBA ||
            storage.shouldShowNFL || storage.shouldShowNHL ||
            storage.shouldShowSoccer || storage.shouldShowMLB ||
            storage.shouldShowGolf || storage.shouldShowTennis ||
            storage.shouldShowRacing
        if !anySportOn { return .allSportsOff }

        if dayGames.isEmpty { return .empty }
        return .hasGames
    }

    @ViewBuilder
    private var loadingBody: some View {
        VStack(spacing: .appSpace2) {
            SkeletonRow()
            SkeletonRow()
            SkeletonRow()
        }
        .padding(.horizontal, .appSpace4)
    }

    private var failedBody: some View {
        EmptyStateView.connectionLost(onRetry: { viewModel.getInfo() })
            .frame(minHeight: 320)
    }

    private var allSportsOffBody: some View {
        let allSports: [SportType] = [
            .basketball, .soccer, .hockey, .mlb,
            .nfl, .golf, .tennis, .racing,
        ]
        return EmptyStateView.filterEmpty(
            disabledSports: allSports,
            onReenable: { /* navigate to Settings via toolbar gear */ }
        )
        .frame(minHeight: 320)
    }

    @ViewBuilder
    private var emptyBody: some View {
        if isToday {
            EmptyStateView.quietDay().frame(minHeight: 320)
        } else if calendar.compare(selectedDate, to: Date(), toGranularity: .day) == .orderedAscending {
            EmptyStateView(
                symbol: "trophy",
                headline: "All wrapped up",
                message: "No games scheduled for \(Self.eyebrowFormatter.string(from: selectedDate))."
            )
            .frame(minHeight: 320)
        } else {
            EmptyStateView(
                symbol: "clock.arrow.circlepath",
                headline: "Nothing scheduled",
                message: "Try a different date — Browse shows the full schedule."
            )
            .frame(minHeight: 320)
        }
    }

    // MARK: - Helpers

    private func scoreLine(for game: Game) -> String {
        let h = game.intHomeScore ?? "—"
        let a = game.intAwayScore ?? "—"
        return "\(a) — \(h)"
    }

    private func kickoffLabel(for game: Game) -> String {
        guard let d = game.standardDate else { return "TBD" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    private func countdownFor(_ game: Game) -> String? {
        guard let d = game.standardDate else { return nil }
        let interval = d.timeIntervalSinceNow
        guard interval > 0 else { return nil }
        let hrs = Int(interval) / 3600
        let mins = (Int(interval) % 3600) / 60
        if hrs > 0 { return "in \(hrs)h \(mins)m" }
        return "in \(mins)m"
    }

    private func leagueLabel(for game: Game) -> String {
        if let id = game.idLeague, let intID = Int(id),
           let league = Leagues(rawValue: intID) {
            return league.leagueName.uppercased()
        }
        return (game.sportType ?? .basketball).displayName.uppercased()
    }
}

// MARK: - Live count pill

private struct LiveCountPill: View {
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.appLive).frame(width: 6, height: 6)
            Text("\(count) LIVE")
                .font(.appFootnote)
                .tracking(1.5)
        }
        .foregroundStyle(Color.appLive)
        .padding(.horizontal, .appSpace2)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.appLive.opacity(0.12))
        )
        .accessibilityLabel(Text("\(count) games live"))
    }
}
