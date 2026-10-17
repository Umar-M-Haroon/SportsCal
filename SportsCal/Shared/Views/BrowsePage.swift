//
//  BrowsePage.swift
//  SportsCal (iOS)
//

import SwiftUI
import SportsCalModel

/// Value-based destinations on the Browse stack (registered in ContentView). Links that
/// lead to a `Team` push must be value-based too, or the team gets pushed twice.
enum BrowseRoute: Hashable {
    case teams
    /// One sport's browse page — pushed from the Mac's sport sidebar, which shows Home's
    /// board rather than the Browse grid.
    case sport(SportType)
}

struct BrowsePage: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites

    /// Two columns on a phone, more as the width allows (iPad, a wide Mac window).
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        let summaries = sportSummaries()
        ScrollView {
            if WorldCupSeason.isActive {
                NavigationLink {
                    WorldCupHubView()
                        .environment(viewModel)
                        .environment(storage)
                        .environment(favorites)
                } label: {
                    BrowseBanner(systemImage: "soccerball", title: "FIFA World Cup 2026",
                                 subtitle: "Groups · Bracket · Golden Boot", tint: Color.app(.soccer))
                }
                .buttonStyle(.plain)
                .padding([.horizontal, .top])

                if let bracket = viewModel.worldCup?.bracket, !bracket.isEmpty {
                    NavigationLink {
                        WorldCupBracketScreen(bracket: bracket)
                            .environment(viewModel)
                            .environment(favorites)
                    } label: {
                        BrowseBanner(systemImage: "trophy.fill", title: "Knockout Bracket",
                                     subtitle: "Round of 32 → Final", tint: Color.app(.soccer))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }

            let events = BigEvent.upcoming(in: viewModel.totalGames ?? [],
                                           liveIDs: Set(viewModel.allLiveEvents.compactMap(\.idEvent)))
            if !events.isEmpty {
                bigEventsRail(events)
            }

            NavigationLink(value: BrowseRoute.teams) {
                BrowseBanner(systemImage: "person.3.fill", title: "Teams",
                             subtitle: "Browse & follow any team", tint: .secondary,
                             background: Color.secondaryGroupedBackground)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 8)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(storage.orderedSports, id: \.self) { sport in
                    NavigationLink {
                        sportPage(sport)
                    } label: {
                        SportCard(sport: sport, liveCount: viewModel.liveGameCountsBySport[sport] ?? 0,
                                  summary: summaries[sport])
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private func sportPage(_ sport: SportType) -> some View {
        BrowseSportView(sport: sport)
            .environment(viewModel)
            .environment(storage)
            .environment(favorites)
    }

    // MARK: - Big events

    /// Majors, finals and playoff series in the next fortnight, across the sports on the
    /// schedule. Each opens its sport's browse page.
    private func bigEventsRail(_ events: [BigEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BIG EVENTS")
                .appEyebrow()
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(events) { event in
                        NavigationLink {
                            sportPage(event.sport)
                        } label: {
                            bigEventCard(event)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 12)
    }

    private func bigEventCard(_ event: BigEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: event.sport.systemImage)
                    .foregroundStyle(event.sport.color)
                if event.isLive {
                    Text("LIVE")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                }
            }
            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Text(event.dateText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 168, height: 104, alignment: .topLeading)
        .background(event.sport.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(event.sport.color.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Sport card summaries

    /// One line per sport card — what's live, how much is on today, or when it's next on.
    /// One pass over the schedule rather than a filter per sport: this runs on every live tick.
    private func sportSummaries() -> [SportType: String] {
        let now = Date()
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        var todayCounts: [SportType: Int] = [:]
        var next: [SportType: Game] = [:]
        // Golf and tennis cards summarize what their pages list — every tour — not the
        // coverage-filtered schedule, which on the default Big Events tier leaves golf blank
        // for months between majors.
        let eventGames = (viewModel.gamesDict[.golf] ?? []) + (viewModel.gamesDict[.tennis] ?? [])
        let teamGames = (viewModel.filteredGames ?? []).filter { $0.sportType != .golf && $0.sportType != .tennis }
        var laterTodayCounts: [SportType: Int] = [:]
        for game in teamGames + eventGames {
            guard let date = game.standardDate, date < endOfToday, let sport = game.sportType else { continue }
            if calendar.isDateInToday(date) { todayCounts[sport, default: 0] += 1 }
            guard date > now else { continue }
            laterTodayCounts[sport, default: 0] += 1
        }
        for game in teamGames + eventGames {
            guard let date = game.standardDate, date >= endOfToday, let sport = game.sportType else { continue }
            if let best = next[sport]?.standardDate, best <= date { continue }
            next[sport] = game
        }
        var result: [SportType: String] = [:]
        for sport in SportType.allCases {
            let live = viewModel.liveGameCountsBySport[sport] ?? 0
            // Every game dated today, finished ones included — what the sport's page lists.
            let today = todayCounts[sport] ?? 0
            let laterToday = laterTodayCounts[sport] ?? 0
            let noun = sport.isEventSport ? "event" : "game"
            if live > 0 {
                // Tennis counts matches and golf events while their pages list tournaments, so name the unit.
                let unit = sport == .tennis ? (live == 1 ? " match" : " matches") : sport == .golf ? (live == 1 ? " event" : " events") : ""
                result[sport] = "\(live) live\(unit)" + (laterToday > 0 ? " · \(laterToday) more today" : "")
            } else if today > 0 {
                result[sport] = "\(today) \(noun)\(today == 1 ? "" : "s") today"
            } else if let game = next[sport], let start = game.standardDate {
                // Golf's day markers shifted onto the real day, as the golf page shows them.
                let date = sport == .golf ? (game.eventDaySpan?.first ?? start) : start
                let when = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                result[sport] = sport.isEventSport ? "\(game.strHomeTeam) · \(when)" : "Next: \(when)"
            }
        }
        return result
    }
}

private extension SportType {
    /// Sports whose rows are whole events (a tournament, a race weekend) rather than games.
    var isEventSport: Bool { self == .golf || self == .tennis || self == .racing }
}

/// A full-width link card at the top of Browse.
private struct BrowseBanner: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let tint: Color
    var background: Color?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(background ?? tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A major, a final or a playoff series coming up soon.
struct BigEvent: Identifiable {
    let id: String
    let title: String
    let sport: SportType
    let start: Date
    let end: Date
    let isLive: Bool

    var dateText: String {
        let calendar = Calendar.current
        if isLive { return "On now" }
        if calendar.isDateInToday(start) { return "Today" }
        if calendar.isDateInTomorrow(start) { return "Tomorrow" }
        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// How far ahead the rail looks.
    static let window: TimeInterval = 14 * 86_400

    /// Tennis and golf majors (one card per tournament) and team-sport playoff series
    /// (one per series title, e.g. "NBA Finals") that are on now or start within `window`.
    /// A tournament is live across its whole span; a series only while one of its games is in
    /// `liveIDs` (the live feed) — between games it shows its dates, not LIVE.
    static func upcoming(in games: [Game], liveIDs: Set<String>, now: Date = Date()) -> [BigEvent] {
        let horizon = now.addingTimeInterval(window)
        var spans: [String: (title: String, sport: SportType, start: Date, end: Date, live: Bool)] = [:]
        for game in games {
            guard let start = game.standardDate, let sport = game.sportType else { continue }
            let title: String
            switch sport {
            case .tennis, .golf:
                guard game.eventTier == .major else { continue }
                title = sport == .tennis ? (game.tournamentName ?? game.strLeague ?? "Grand Slam") : game.strHomeTeam
            case .racing:
                continue
            default:
                guard let series = game.playoff?.seriesTitle.map(seriesName), !series.isEmpty,
                      game.playoff?.seriesCompleted != true else { continue }
                title = series
            }
            let end = game.effectiveEndDate ?? start
            guard end >= now.addingTimeInterval(-6 * 3600), start <= horizon else { continue }
            let key = "\(sport.rawValue)|\(title)"
            let live = game.idEvent.map(liveIDs.contains) ?? false
            if let span = spans[key] {
                spans[key] = (title, sport, min(span.start, start), max(span.end, end), span.live || live)
            } else {
                spans[key] = (title, sport, start, end, live)
            }
        }
        return spans
            .map { span in
                let isTournament = span.value.sport == .tennis || span.value.sport == .golf
                let inWindow = span.value.start <= now && now <= span.value.end
                return BigEvent(id: span.key, title: span.value.title, sport: span.value.sport,
                                start: span.value.start, end: span.value.end,
                                isLive: span.value.live || (isTournament && inWindow))
            }
            .sorted { $0.isLive != $1.isLive ? $0.isLive : $0.start < $1.start }
    }

    /// ESPN titles the extra games of a series "ALCS - Game 5 If Necessary"; fold them into "ALCS".
    private static func seriesName(_ title: String) -> String {
        guard let range = title.range(of: #"\s+-\s+Game \d+.*$"#, options: .regularExpression) else { return title }
        return String(title[..<range.lowerBound])
    }
}

private struct SportCard: View {
    let sport: SportType
    let liveCount: Int
    var summary: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: sport.systemImage)
                .font(.system(size: 32))
                .foregroundColor(sport.color)

            Text(sport.displayName)
                .font(.headline)
                .foregroundColor(.primary)

            // Two lines reserved on every card — "US Grand Prix · Sun Oct 19" needs both — so
            // icons stay aligned whether or not a card has anything to say.
            Text(summary ?? " ")
                .font(.caption)
                .foregroundStyle(liveCount > 0 ? Color.red : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .padding(.horizontal, 8)
                .accessibilityHidden(summary == nil)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 132)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(sport.color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(sport.color.opacity(0.3), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if liveCount > 0 {
                Text("\(liveCount)")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .padding(8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BrowseSportView: View {
    let sport: SportType
    @Environment(GameViewModel.self) private var viewModel
    @Environment(UserDefaultStorage.self) private var storage
    @Environment(Favorites.self) private var favorites
    @Environment(SubscriptionManager.self) private var subscriptionManager
    #if os(iOS)
    @Environment(NativeAdManager.self) private var adManager
    #endif

    @State private var browseVM: SportBrowseViewModel?
    @State private var shouldShowSportsCalProAlert = false
    @State private var sheetType: SheetType?
    /// Golf only: the tour being browsed. Nil until picked — see `golfBrowseList`.
    @State private var selectedGolfTour: Leagues?
    /// Tennis only: ATP or WTA, nil for both.
    @State private var tennisTour: Leagues?
    /// Racing only: the series shown. All share the racing bucket.
    @State private var racingSeries: Leagues = .formula1
    /// Team sports: the day being browsed. Set to `initialDay()` once data arrives.
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    /// Team sports: the league chip picked, nil for all leagues.
    @State private var selectedLeague: Leagues?
    /// League sections the user expanded or collapsed by hand; the rest use `defaultExpanded`.
    @State private var leagueExpansion: [Leagues: Bool] = [:]
    /// Event groups (coming up, results, a season) opened past their preview.
    @State private var expandedGroups: Set<String> = []
    /// Racing: the picked series' standings, nil until loaded (F1 reads the view model's).
    @State private var seriesStandings: NetworkHandler.SeriesStandings?

    /// Tennis, golf and racing browse whole events (tournaments, weekends) rather than days.
    private var browsesEvents: Bool {
        sport == .tennis || sport == .golf || sport == .racing
    }

    var body: some View {
        Group {
            if let browseVM, !browseVM.isLoading {
                if let error = browseVM.errorMessage,
                   browseVM.liveGames.isEmpty && browseVM.todayGames.isEmpty &&
                   browseVM.upcomingGames.isEmpty && browseVM.recentGames.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await browseVM.fetch() }
                        }
                    }
                } else {
                    gamesList(browseVM)
                }
            } else {
                ScrollView {
                    VStack(spacing: .appSpace2) {
                        ForEach(0..<5, id: \.self) { _ in
                            SkeletonRow()
                        }
                    }
                    .padding(.horizontal, .appSpace4)
                    .padding(.top, .appSpace4)
                }
            }
        }
        .navigationTitle(sport.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !browsesEvents, let browseVM, !browseVM.isLoading {
                ToolbarItem(placement: .automatic) {
                    seasonMenu(browseVM)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if !storage.enabledSports.contains(sport) {
                    Button {
                        storage.toggleSport(sport, enabled: true)
                        // Merge already-fetched browse data into the main game state
                        // so we don't trigger a full network re-fetch
                        if let games = browseVM?.fetchedGames, !games.isEmpty {
                            viewModel.totalGames = (viewModel.totalGames ?? []) + games
                        }
                        viewModel.filterSports(force: true)
                    } label: {
                        Label("Add to My Sports", systemImage: "plus.circle.fill")
                    }
                }
            }
        }
        .task {
            // Coming back from a pushed detail keeps the page as it was left, with fresh scores.
            if let browseVM {
                browseVM.refreshIfStale()
                return
            }
            restoreChip()
            let vm = SportBrowseViewModel(sport: sport, viewModel: viewModel)
            browseVM = vm
            await vm.fetch()
            selectedDay = vm.initialDay()
        }
        #if os(iOS)
        .onAppear {
            if !subscriptionManager.isPro && AdConfiguration.isEnabled {
                adManager.refreshOnAppear()
            }
        }
        #endif
    }

    // MARK: - Chips

    /// Reopens on the chip last picked for this sport. Racing with nothing remembered and F1
    /// hidden opens on a series the user follows.
    private func restoreChip() {
        let remembered = BrowseChipMemory.league(for: sport)
        switch sport {
        case .racing:
            if let remembered, remembered.isRacing {
                racingSeries = remembered
            } else if storage.hiddenCompetitions.contains(Leagues.formula1.leagueName),
                      let followed = Leagues.allCases.first(where: { $0.isMotorsportSeries && !storage.hiddenCompetitions.contains($0.leagueName) }) {
                racingSeries = followed
            }
        case .golf:
            selectedGolfTour = remembered
        case .tennis:
            tennisTour = remembered.flatMap { $0 == .atp || $0 == .wta ? $0 : nil }
        default:
            selectedLeague = remembered
        }
    }

    /// The chip strip in its own unstyled list section.
    private func chipSection(_ items: [BrowseChipItem], selected: Leagues?,
                             onSelect: @escaping (Leagues?) -> Void) -> some View {
        Section {
            chipStrip(items, selected: selected, onSelect: onSelect)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Picking a chip also remembers it for next time.
    private func chipStrip(_ items: [BrowseChipItem], selected: Leagues?,
                           onSelect: @escaping (Leagues?) -> Void) -> some View {
        BrowseChipStrip(items: items,
                        selectedID: selected.map { String($0.rawValue) } ?? BrowseChipItem.all.id,
                        sport: sport) { item in
            onSelect(item.league)
            BrowseChipMemory.remember(item.league.map { String($0.rawValue) }, for: sport)
        }
    }

    /// A competition hidden from the schedule, with the switch to bring it back.
    private func hiddenNotice(_ league: Leagues) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(league.leagueName) is hidden from your schedule.")
                    .font(.subheadline)
                Button("Show in My Schedule") {
                    WhatsNewAction.showCompetition(league, sport: sport)
                        .apply(storage: storage, viewModel: viewModel)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    /// Whether an event group was opened past its preview. Keys include the chip, so each
    /// series or tour keeps its own.
    private func groupExpansion(_ key: String) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(key) },
            set: { if $0 { expandedGroups.insert(key) } else { expandedGroups.remove(key) } }
        )
    }

    // MARK: - Games List

    /// Just the picked racing series.
    private func inSelectedSeries(_ games: [GameWithTeams]) -> [GameWithTeams] {
        games.filter { $0.game.knownLeague == racingSeries }
    }

    @ViewBuilder
    private func gamesList(_ browseVM: SportBrowseViewModel) -> some View {
        switch sport {
        case .racing: racingBrowseList(browseVM)
        case .tennis: tennisBrowseList(browseVM)
        case .golf: golfBrowseList(browseVM)
        default: dayBrowseList(browseVM)
        }
    }

    #if os(iOS)
    @ViewBuilder
    private func adSection(slot: Int) -> some View {
        if !subscriptionManager.isPro && AdConfiguration.isEnabled, let ad = adManager.adForSlot(slot) {
            Section {
                NativeAdCardView(nativeAd: ad)
            }
        }
    }
    #endif

    // MARK: - Tennis

    private struct TennisTournament: Identifiable {
        var id: String { name }
        let name: String
        let games: [Game]
        let startDate: Date?
        let endDate: Date?
        let isLive: Bool
        /// Tours represented in this tournament. Combined events (Grand Slams, Indian Wells…)
        /// contain both ATP + WTA; single-tour events contain one. Drives the card badge and the
        /// Men's/Women's split inside `TournamentHubView`.
        let tours: Set<Leagues>

        /// Short tour badge: "ATP", "WTA", or "ATP · WTA" for combined events. Nil if unknown.
        var tourBadge: String? {
            let parts = [Leagues.atp, Leagues.wta].filter { tours.contains($0) }
            guard !parts.isEmpty else { return nil }
            return parts.map { $0 == .atp ? "ATP" : "WTA" }.joined(separator: " · ")
        }
    }

    /// Groups tennis match games into tournaments (by tournamentName), preserving order. A
    /// tournament is live when the live feed has one of its matches — schedule copies keep
    /// TheSportsDB's statuses.
    private func tennisTournaments(from games: [Game], liveIDs: Set<String>) -> [TennisTournament] {
        var buckets: [String: [Game]] = [:]
        var order: [String] = []
        for game in games {
            guard let lg = game.idLeague, let i = Int(lg),
                  let league = Leagues(rawValue: i), league.isTennis else { continue }
            let name = game.tournamentName ?? game.strLeague ?? "Tennis"
            if buckets[name] == nil { order.append(name) }
            buckets[name, default: []].append(game)
        }
        return order.map { name in
            let all = buckets[name] ?? []
            // A tournament whose draw isn't out yet arrives as one entry (not a match) carrying
            // the event's dates; its hub lists matches only.
            let gs = all.filter(\.isTennisMatch)
            // Match times set the dates once there are matches; before that, the entry's own span.
            let dates = gs.isEmpty
                ? all.compactMap(\.standardDate) + all.compactMap(\.endDateParsed)
                : gs.compactMap(\.standardDate)
            // From the draw, not `idLeague` — a row cached before draws existed carries a
            // stale league, and mixed doubles counts toward both tours.
            let tours = Set(gs.flatMap { $0.tennisTours })
            return TennisTournament(
                name: name, games: gs,
                startDate: dates.min(), endDate: dates.max(),
                isLive: gs.contains { $0.strStatus?.lowercased() == "in" || liveIDs.contains($0.idEvent ?? "") },
                tours: tours
            )
        }
    }

    /// Tennis browse: ATP/WTA chips, then tournaments live now, coming up and finished —
    /// each a drill-in to the tournament's hub.
    private func tennisBrowseList(_ browseVM: SportBrowseViewModel) -> some View {
        let _ = storage.preferenceVersion
        let liveIDs = Set(browseVM.liveGames.compactMap { $0.game.idEvent })
        let all = tennisTournaments(from: browseVM.fetchedGames, liveIDs: liveIDs)
        // Tournaments with no draw data yet can't be told apart, so they show under both tours.
        let tournaments = tennisTour.map { tour in all.filter { $0.tours.isEmpty || $0.tours.contains(tour) } } ?? all
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let live = tournaments.filter(\.isLive)
        let now = Date()
        let notLive = tournaments
            .filter { !$0.isLive && ($0.endDate ?? .distantFuture) >= startOfToday }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        // Started but nothing in play right now (overnight, between sessions).
        let underWay = notLive.filter { ($0.startDate ?? .distantFuture) <= now }
        let ahead = notLive.filter { ($0.startDate ?? .distantFuture) > now }
        let results = tournaments
            .filter { !$0.isLive && ($0.endDate ?? .distantPast) < startOfToday }
            .sorted { ($0.endDate ?? .distantPast) > ($1.endDate ?? .distantPast) }
        let chipKey = tennisTour.map { String($0.rawValue) } ?? "all"

        return List {
            chipSection([.all, BrowseChipItem(league: .atp, title: "ATP"), BrowseChipItem(league: .wta, title: "WTA")],
                        selected: tennisTour) { tennisTour = $0 }

            if let tennisTour, storage.hiddenCompetitions.contains(tennisTour.leagueName) {
                hiddenNotice(tennisTour)
            }

            if !live.isEmpty {
                Section {
                    ForEach(live) { tennisTournamentLink($0) }
                } header: {
                    LiveAnimatedView()
                }
            }

            if !underWay.isEmpty {
                Section("Under Way") {
                    ForEach(underWay) { tennisTournamentLink($0) }
                }
            }

            if !ahead.isEmpty {
                PreviewGroupSection(items: ahead, preview: 5, noun: "tournaments",
                                    isExpanded: groupExpansion("tennis-\(chipKey)-ahead")) {
                    Text("Coming Up (\(ahead.count))")
                } row: {
                    tennisTournamentLink($0)
                }
            }

            #if os(iOS)
            adSection(slot: 0)
            #endif

            if !results.isEmpty {
                PreviewGroupSection(items: results, preview: 3, noun: "tournaments",
                                    isExpanded: groupExpansion("tennis-\(chipKey)-results")) {
                    Text("Results (\(results.count))")
                } row: {
                    tennisTournamentLink($0)
                }
            }

            if tournaments.isEmpty {
                Section { emptyState }
                    .listRowBackground(Color.clear)
            }
        }
        #if os(iOS)
        .listSectionSpacing(.compact)
        #endif
    }

    private func tennisTournamentLink(_ tournament: TennisTournament) -> some View {
        NavigationLink {
            TournamentHubView(
                tournamentName: tournament.name, games: tournament.games,
                shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                sheetType: $sheetType
            )
            .environment(viewModel)
            .environment(favorites)
        } label: {
            tournamentCard(
                systemImage: "tennisball.fill",
                name: tournament.name,
                badge: tournament.tourBadge,
                dateText: tennisDateText(tournament),
                isLive: tournament.isLive
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day browse (team sports)

    /// Team sports browse like the home page, scoped to one sport: league chips, a day
    /// strip, then that day's games grouped into collapsible league sections. One day at a
    /// time keeps the page short however busy the sport is, and any date stays reachable.
    private func dayBrowseList(_ browseVM: SportBrowseViewModel) -> some View {
        let leagues = browseVM.leagues
        let league = selectedLeague.flatMap { leagues.contains($0) ? $0 : nil }
        let isToday = Calendar.current.isDateInToday(selectedDay)
        let live = isToday ? browseVM.liveGames.filter { league == nil || $0.game.knownLeague == league } : []
        let dayGames = browseVM.games(on: selectedDay).filter { league == nil || $0.game.knownLeague == league }
        let favoriteGames = dayGames.filter { favorites.contains($0.game) }
        let sections = leagueSections(dayGames.filter { !favorites.contains($0.game) }, order: leagues)
        // One league in view — picked, or the only one the sport has — gets its hub.
        let hubLeague = league ?? (leagues.count == 1 ? leagues.first : nil)

        return List {
            Section {
                if leagues.count > 1 {
                    chipStrip([.all] + leagues.map { BrowseChipItem(league: $0) },
                              selected: league) { selectedLeague = $0 }
                }
                DayChipStrip(
                    selectedDate: $selectedDay,
                    datesWithGames: browseVM.datesWithGames(league: league)
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if let hubLeague {
                Section {
                    LeagueHubLink(league: hubLeague, sport: sport, games: browseVM.games(in: hubLeague))
                }
            }

            LiveGamesSection(games: live) { gameRow($0, isLive: true) }
            YourTeamsSection(games: favoriteGames) { dayGroupedRow($0) }

            ForEach(Array(sections.enumerated()), id: \.element.league) { index, section in
                if hubLeague != nil, sections.count == 1 {
                    // One league in view: the hub card above already names it, so no header.
                    Section {
                        ForEach(section.games) { gwt in
                            dayGroupedRow(gwt)
                        }
                    }
                } else {
                    let isExpanded = leagueExpansion[section.league]
                        ?? defaultExpanded(section.league, index: index, in: sections, filtered: league != nil)
                    Section {
                        if isExpanded {
                            ForEach(section.games) { gwt in
                                dayGroupedRow(gwt)
                            }
                        }
                    } header: {
                        CollapsibleSectionHeader(title: section.league.leagueName, count: section.games.count,
                                                 isExpanded: isExpanded) {
                            leagueExpansion[section.league] = !isExpanded
                        }
                    }
                }
                #if os(iOS)
                // After the first section, so the day's first games stay above the fold, and
                // only once a day has enough games to sit between — a one-game final shouldn't
                // be sandwiched by an ad.
                if index == 0, dayGames.count >= 4 {
                    adSection(slot: 0)
                }
                if index == 1, dayGames.count >= 8 {
                    adSection(slot: 1)
                }
                #endif
            }

            if live.isEmpty && dayGames.isEmpty {
                Section {
                    emptyDay(browseVM, league: league)
                }
                .listRowBackground(Color.clear)
            }
        }
        #if os(iOS)
        .listSectionSpacing(.compact)
        .gesture(daySwipeGesture)
        #endif
    }

    /// Jumps the day strip between seasons: the current one opens where the page would,
    /// a past one on its final matchday (the final, the last round). Only for one league —
    /// leagues label seasons differently ("2025-2026" vs MLS's "2026") — and hidden with one season.
    @ViewBuilder
    private func seasonMenu(_ browseVM: SportBrowseViewModel) -> some View {
        let league = selectedLeague.flatMap { browseVM.leagues.contains($0) ? $0 : nil }
            ?? (browseVM.leagues.count == 1 ? browseVM.leagues.first : nil)
        let seasons = league.map { browseVM.seasons(league: $0) } ?? []
        if seasons.count > 1 {
            let showing = seasons.first { $0.firstDay <= selectedDay && selectedDay <= $0.lastDay }
            Menu {
                // The server keeps the current and previous season, so say why the list stops.
                Section("This season and last") {
                    ForEach(seasons, id: \.self) { span in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDay = span == seasons.first ? browseVM.initialDay() : span.lastDay
                            }
                        } label: {
                            if span == showing {
                                Label(Game.seasonDisplayName(span.season), systemImage: "checkmark")
                            } else {
                                Text(Game.seasonDisplayName(span.season))
                            }
                        }
                    }
                }
            } label: {
                Label(showing.map { Game.seasonDisplayName($0.season) } ?? "Season",
                      systemImage: "calendar.badge.clock")
            }
            .accessibilityLabel("Season")
        }
    }

    /// Groups a day's games by league: leagues the user follows first, then the feed's order
    /// (busiest first).
    private func leagueSections(_ games: [GameWithTeams], order: [Leagues]) -> [(league: Leagues, games: [GameWithTeams])] {
        let grouped = Dictionary(grouping: games.filter { $0.game.knownLeague != nil }) { $0.game.knownLeague! }
        return order
            .filter { grouped[$0] != nil }
            .sorted { isFollowed($0) && !isFollowed($1) }
            .map { (league: $0, games: grouped[$0] ?? []) }
    }

    /// The sport is on the user's schedule and the league isn't hidden from it.
    private func isFollowed(_ league: Leagues) -> Bool {
        storage.enabledSports.contains(sport) && !storage.hiddenCompetitions.contains(league.leagueName)
    }

    /// Followed leagues open; others start collapsed so a busy day stays scannable. With one
    /// league picked, or when nothing is followed, the first section opens.
    private func defaultExpanded(_ league: Leagues, index: Int,
                                 in sections: [(league: Leagues, games: [GameWithTeams])],
                                 filtered: Bool) -> Bool {
        if filtered || sections.count == 1 { return true }
        if isFollowed(league) { return true }
        return index == 0 && !sections.contains { isFollowed($0.league) }
    }

    /// No games on the picked day: say so and offer the nearest matchdays either side.
    private func emptyDay(_ browseVM: SportBrowseViewModel, league: Leagues?) -> some View {
        let previous = browseVM.adjacentDayWithGames(from: selectedDay, league: league, forward: false)
        let next = browseVM.adjacentDayWithGames(from: selectedDay, league: league, forward: true)
        return VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No \(league?.leagueName ?? sport.displayName) games \(relativeDayPhrase(selectedDay))")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                if let previous {
                    Button {
                        withAnimation { selectedDay = previous }
                    } label: {
                        Label(previous.formatted(.dateTime.month(.abbreviated).day()), systemImage: "chevron.left")
                    }
                }
                if let next {
                    Button {
                        withAnimation { selectedDay = next }
                    } label: {
                        HStack(spacing: 4) {
                            Text(next.formatted(.dateTime.month(.abbreviated).day()))
                            Image(systemName: "chevron.right")
                        }
                    }
                }
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    #if os(iOS)
    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      let day = Calendar.current.date(byAdding: .day,
                                                      value: value.translation.width < 0 ? 1 : -1,
                                                      to: selectedDay) else { return }
                withAnimation(.easeInOut(duration: 0.2)) { selectedDay = day }
            }
    }
    #endif

    /// One row per tournament in the tennis and golf lists: sport icon, name, an optional tint
    /// badge (tour for tennis, "Major" for golf), date range and an optional detail line.
    @ViewBuilder
    private func tournamentCard(systemImage: String, name: String, badge: String?, dateText: String,
                                detail: String? = nil, isLive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.app(sport))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.app(sport))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.app(sport).opacity(0.15), in: Capsule())
                    }
                    Text(dateText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isLive {
                Text("LIVE")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// "Jun 1 – 14" / "Jun 28 – Jul 5" / single day fallback.
    /// A tennis tournament's end is only known once its final is scheduled — mid-event the
    /// last match on the board is tomorrow's — so one in progress says when it started.
    private func tennisDateText(_ tournament: TennisTournament) -> String {
        let now = Date()
        if let start = tournament.startDate, start <= now, !tournament.games.isEmpty,
           (tournament.endDate ?? .distantFuture) >= Calendar.current.startOfDay(for: now) {
            return "Started \(start.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return dateRangeText(tournament.startDate, tournament.endDate)
    }

    private func dateRangeText(_ start: Date?, _ end: Date?) -> String {
        guard let start else { return "" }
        guard let end, !Calendar.current.isDate(start, inSameDayAs: end) else {
            return start.formatted(.dateTime.month(.abbreviated).day())
        }
        let cal = Calendar.current
        if cal.component(.month, from: start) == cal.component(.month, from: end) {
            return "\(start.formatted(.dateTime.month(.abbreviated).day()))–\(cal.component(.day, from: end))"
        }
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    // MARK: - Golf

    /// Golf browse: tour chips (only tours with events), then the tour's tournaments live
    /// now, coming up and finished. This is the unfiltered catalog — a tour hidden from the
    /// schedule is still browsable (so you can find it again), but it isn't opened on by
    /// default and says it's hidden; the coverage preference isn't applied either, and
    /// majors are badged instead.
    private func golfBrowseList(_ browseVM: SportBrowseViewModel) -> some View {
        let _ = storage.preferenceVersion
        let games = browseVM.fetchedGames
        let tours = GolfTourBoard.tours(in: games)
        let hidden = Set(storage.hiddenCompetitions)
        let tour = selectedGolfTour.flatMap { tours.contains($0) ? $0 : nil }
            ?? GolfTourBoard.defaultTour(in: tours, hidden: hidden)
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let events = tour.map { GolfTourBoard.events(for: $0, in: games) } ?? []
        let upcoming = GolfTourBoard.upcoming(events, startOfToday: startOfToday)
        let live = upcoming.filter(GolfTourBoard.isLive)
        let now = Date()
        let notLive = upcoming.filter { !GolfTourBoard.isLive($0) }
        // Started but not in play right now (between rounds).
        let underWay = notLive.filter { ($0.eventDaySpan?.first ?? .distantFuture) <= now }
        let ahead = notLive.filter { ($0.eventDaySpan?.first ?? .distantFuture) > now }
        let results = GolfTourBoard.past(events, startOfToday: startOfToday)
        let chipKey = tour.map { String($0.rawValue) } ?? "none"

        return List {
            if tours.count > 1 {
                chipSection(tours.map { BrowseChipItem(league: $0) }, selected: tour) { selectedGolfTour = $0 }
            }

            if let tour, hidden.contains(tour.leagueName) {
                hiddenNotice(tour)
            }

            if !live.isEmpty {
                Section {
                    ForEach(live) { golfTournamentLink($0) }
                } header: {
                    LiveAnimatedView()
                }
            }

            if !underWay.isEmpty {
                Section("Under Way") {
                    ForEach(underWay) { golfTournamentLink($0) }
                }
            }

            if !ahead.isEmpty {
                PreviewGroupSection(items: ahead, preview: 5, noun: "tournaments",
                                    isExpanded: groupExpansion("golf-\(chipKey)-ahead")) {
                    Text("Coming Up (\(ahead.count))")
                } row: {
                    golfTournamentLink($0)
                }
            }

            #if os(iOS)
            adSection(slot: 0)
            #endif

            if !results.isEmpty {
                PreviewGroupSection(items: results, preview: 3, noun: "tournaments",
                                    isExpanded: groupExpansion("golf-\(chipKey)-results")) {
                    Text("Results (\(results.count))")
                } row: {
                    golfTournamentLink($0)
                }
            }

            if events.isEmpty {
                Section { emptyState }
                    .listRowBackground(Color.clear)
            }
        }
        #if os(iOS)
        .listSectionSpacing(.compact)
        #endif
    }

    private func golfTournamentLink(_ game: Game) -> some View {
        NavigationLink {
            TournamentDetailView(game: game)
                .environment(viewModel)
                .environment(favorites)
        } label: {
            golfTournamentCard(game)
        }
        .buttonStyle(.plain)
    }

    private func golfTournamentCard(_ game: Game) -> some View {
        let span = game.eventDaySpan
        return tournamentCard(
            systemImage: "figure.golf",
            name: game.strHomeTeam,
            badge: game.eventTier == .major ? "Major" : nil,
            dateText: dateRangeText(span?.first, span?.last),
            detail: golfDetail(game),
            isLive: GolfTourBoard.isLive(game)
        )
    }

    /// Leader while live, winner once finished, else the venue.
    private func golfDetail(_ game: Game) -> String? {
        let leader: String? = {
            let name = game.leaderboardEntries?.first?.name ?? game.strAwayTeam
            // TheSportsDB rows fall back to the event name when there are no players.
            guard !name.isEmpty, name != "TBD", name != game.strHomeTeam else { return nil }
            return name
        }()
        if GolfTourBoard.isLive(game), let leader {
            if let score = game.intAwayScore, !score.isEmpty { return "Leader: \(leader) (\(score))" }
            return "Leader: \(leader)"
        }
        if game.hasDoneStatus, let leader { return "Winner: \(leader)" }
        return game.venueName
    }

    // MARK: - Day rows

    /// Row for a day-grouped section. Team sports use the dense `CompactGameRowView`
    /// (time/score on the right). Individual sports fall back to the full row plus a
    /// time caption.
    @ViewBuilder
    private func dayGroupedRow(_ gwt: GameWithTeams) -> some View {
        let game = gwt.game
        if !game.isIndividualSport, !game.isRace,
           let home = gwt.homeTeam, let away = gwt.awayTeam {
            CompactGameRowView(
                homeTeam: home, awayTeam: away, game: game,
                shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                sheetType: $sheetType, isLive: false
            )
            .environment(viewModel)
            .environment(favorites)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if let date = game.standardDate {
                    GameTimeLabel(date: date, includeDate: false)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                gameRow(gwt, isLive: false)
            }
        }
    }

    /// "today" / "tomorrow" / "yesterday" / "on Saturday, Oct 11", to finish a sentence.
    private func relativeDayPhrase(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) || cal.isDateInTomorrow(day) || cal.isDateInYesterday(day) {
            return dayLabel(day).lowercased()
        }
        return "on \(dayLabel(day))"
    }

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = cal.component(.year, from: day) == cal.component(.year, from: Date())
        if sameYear {
            return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        } else {
            return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        }
    }

    // MARK: - Racing

    /// Racing reads as one series' season: series chips, what's live, the next weekend in
    /// full, the championship's top three, then the rest of the calendar and each season's
    /// results — long groups preview a few rows behind "Show all".
    private func racingBrowseList(_ browseVM: SportBrowseViewModel) -> some View {
        let _ = storage.preferenceVersion
        let live = inSelectedSeries(browseVM.liveGames)
        let ahead = inSelectedSeries(browseVM.todayGames + browseVM.upcomingGames)
        let seasons = groupedBySeason(inSelectedSeries(browseVM.recentGames))
        let hidden = Set(storage.hiddenCompetitions)
        let seriesName = racingSeries.racingShortName ?? racingSeries.leagueName
        let chipKey = String(racingSeries.rawValue)

        return List {
            chipSection(Leagues.allCases.filter(\.isRacing).map { BrowseChipItem(league: $0) },
                        selected: racingSeries) { racingSeries = $0 ?? racingSeries }

            if racingSeries == .formula1 {
                // One-time pointer to the other series for F1 fans (dismissed for good once acted on).
                NASCARPromoSection()
            } else if hidden.contains(racingSeries.leagueName) {
                Section {
                    RacingSeriesHiddenNotice(series: racingSeries)
                }
            }

            LiveGamesSection(games: live) { gameRow($0, isLive: true) }

            if let next = ahead.first {
                Section("Next Up") {
                    NavigationLink {
                        RaceDetailView(game: next.game)
                            .environment(viewModel)
                            .environment(favorites)
                    } label: {
                        RaceWeekendCard(game: next.game)
                    }
                }
            }

            if hasStandings {
                Section {
                    if !standingsRows.isEmpty {
                        RacingStandingsPreview(title: "\(seriesName) Standings", rows: standingsRows)
                    }
                    NavigationLink {
                        RacingStandingsScreen(series: racingSeries, f1: viewModel.f1Standings,
                                              standings: seriesStandings)
                    } label: {
                        Text(standingsRows.isEmpty ? "\(seriesName) Standings" : "Full Standings")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Championship")
                }
            }

            #if os(iOS)
            adSection(slot: 0)
            #endif

            let remaining = Array(ahead.dropFirst())
            if !remaining.isEmpty {
                PreviewGroupSection(items: remaining, preview: 4, noun: "races",
                                    isExpanded: groupExpansion("racing-\(chipKey)-remaining")) {
                    Text("Coming Up (\(remaining.count))")
                } row: {
                    raceRow($0)
                }
            }

            ForEach(Array(seasons.enumerated()), id: \.element.year) { index, season in
                PreviewGroupSection(items: season.games, preview: index == 0 ? 3 : 0, noun: "races",
                                    isExpanded: groupExpansion("racing-\(chipKey)-season-\(season.year)")) {
                    Label("\(String(season.year)) Results (\(season.games.count))",
                          systemImage: "flag.checkered.2.crossed")
                } row: {
                    raceRow($0)
                }
            }

            if live.isEmpty && ahead.isEmpty && seasons.isEmpty {
                Section {
                    emptyState
                }
                .listRowBackground(Color.clear)
            }
        }
        #if os(iOS)
        .listSectionSpacing(.compact)
        #endif
        .task(id: racingSeries) {
            seriesStandings = nil
            guard racingSeries != .formula1 else { return }
            seriesStandings = try? await NetworkHandler.fetchSeriesStandings(racingSeries)
        }
    }

    /// F1's standings come with the schedule; the other series' are fetched per pick.
    private var hasStandings: Bool {
        racingSeries == .formula1 ? viewModel.f1Standings != nil : seriesStandings != nil
    }

    /// The picked series' drivers' table, for the inline top three.
    private var standingsRows: [RacingStandingRow] {
        if racingSeries == .formula1 {
            return viewModel.f1Standings.map(RacingStandingsPreview.rows(f1:)) ?? []
        }
        return seriesStandings.map(RacingStandingsPreview.rows(series:)) ?? []
    }

    // MARK: - Racing rows

    @ViewBuilder
    private func raceRow(_ gwt: GameWithTeams) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let range = raceWeekendRangeLabel(gwt.game) {
                Text(range)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            gameRow(gwt, isLive: false)
        }
    }

    /// Weekend date range from session dates, e.g. "Jun 5–7" or "Jun 28 – Jul 1".
    private func raceWeekendRangeLabel(_ game: Game) -> String? {
        let dates = game.sessionDates.sorted()
        guard let first = dates.first, let last = dates.last else {
            return game.standardDate.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
        }
        return dateRangeText(first, last)
    }

    /// Groups games by their race-day year, descending; rows within a season newest-first.
    private func groupedBySeason(_ games: [GameWithTeams]) -> [(year: Int, games: [GameWithTeams])] {
        var buckets: [Int: [GameWithTeams]] = [:]
        for gwt in games {
            let date = gwt.game.effectiveEndDate ?? gwt.game.standardDate
            let year = date.map { Calendar.current.component(.year, from: $0) } ?? 0
            buckets[year, default: []].append(gwt)
        }
        return buckets
            .sorted { $0.key > $1.key }
            .map { year, games in
                let sorted = games.sorted {
                    ($0.game.effectiveEndDate ?? $0.game.standardDate ?? .distantPast) >
                    ($1.game.effectiveEndDate ?? $1.game.standardDate ?? .distantPast)
                }
                return (year: year, games: sorted)
            }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: sport.systemImage)
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No events found for \(sport.displayName)")
                .foregroundColor(.secondary)
            if storage.hidePastEvents {
                Text("Past events are hidden in Settings. Turn off \"Hide past events\" to see recent results.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Game Row

    @ViewBuilder
    private func gameRow(_ gwt: GameWithTeams, isLive: Bool) -> some View {
        let game = gwt.game
        if game.isRace {
            NavigationLink {
                RaceDetailView(game: game)
                    .environment(viewModel)
                    .environment(favorites)
            } label: {
                RaceScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: isLive)
                    .environment(viewModel)
                    .environment(favorites)
            }
            .buttonStyle(.plain)
        } else if game.isTennisMatch {
            NavigationLink {
                TennisMatchDetailView(game: game)
                    .environment(viewModel)
                    .environment(favorites)
            } label: {
                TennisMatchScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: isLive)
                    .environment(viewModel)
                    .environment(favorites)
            }
            .buttonStyle(.plain)
        } else if game.isIndividualSport {
            NavigationLink {
                TournamentDetailView(game: game)
                    .environment(viewModel)
                    .environment(favorites)
            } label: {
                TournamentScoreView(game: game, shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, isLive: isLive)
                    .environment(viewModel)
            }
            .buttonStyle(.plain)
        } else if let homeTeam = gwt.homeTeam, let awayTeam = gwt.awayTeam {
            if let homeScore = Int(game.intHomeScore ?? ""),
               let awayScore = Int(game.intAwayScore ?? "") {
                GameScoreView(
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    homeScore: homeScore,
                    awayScore: awayScore,
                    game: game,
                    shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                    sheetType: $sheetType,
                    isLive: isLive
                )
                .environment(favorites)
                .environment(viewModel)
            } else {
                UpcomingGameView(
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    game: game,
                    showCountdown: .constant(storage.showStartTime),
                    shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert,
                    sheetType: $sheetType,
                    dateFormat: storage.dateFormat
                )
                .environment(favorites)
            }
        }
    }
}

/// A racing series' championship, pushed from racing browse.
private struct RacingStandingsScreen: View {
    let series: Leagues
    let f1: F1Standings?
    let standings: NetworkHandler.SeriesStandings?
    @State private var showAll = false

    var body: some View {
        ScrollView {
            Group {
                if series == .formula1, let f1 {
                    F1TitleFightCard(standings: f1)
                } else {
                    switch standings {
                    case .drivers(let table):
                        NASCARStandingsCard(standings: table, showAll: $showAll)
                    case .classes(let tables):
                        ClassStandingsCard(standings: tables)
                    case nil:
                        ContentUnavailableView("No Standings", systemImage: "list.number")
                    }
                }
            }
            .padding()
        }
        .navigationTitle("\(series.racingShortName ?? series.leagueName) Standings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
