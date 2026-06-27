//
//  WorldCupHubView.swift
//  SportsCal
//
//  The featured "FIFA World Cup 2026" destination: live/upcoming matches, group
//  standings (12 groups), the knockout bracket, and the Golden Boot race. Reuses
//  existing game-detail navigation and the shared standings table.
//

import SwiftUI
import SportsCalModel
#if os(iOS)
import EventKit
#endif

struct WorldCupHubView: View {
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @Environment(UserDefaultStorage.self) private var storage

    @State private var model = WorldCupHubViewModel()
    @State private var sheetType: SheetType? = nil
    @State private var shouldShowProAlert: Bool = false
    @State private var timeFilter: WCTimeFilter = .upcoming

    /// Upcoming / Past toggle, mirroring `BrowseSportView`'s time filter.
    private enum WCTimeFilter: String, CaseIterable {
        case upcoming = "Upcoming"
        case past = "Past"
    }

    @AppStorage("shouldShowWorldCup") private var shouldShowWorldCup: Bool = false
    @AppStorage("shouldShowSoccer") private var shouldShowSoccer: Bool = false

    private var accent: Color { .app(.soccer) }
    private var isEnabled: Bool { shouldShowWorldCup || shouldShowSoccer }

    /// Everything the list needs, derived in one pass over the resolved fixtures.
    private struct Buckets {
        var live: [GameWithTeams]
        var upcomingByDay: [(date: Date, games: [GameWithTeams])]
        var recentByGroup: [(label: String, games: [GameWithTeams])]
        var allEmpty: Bool
    }

    /// Resolve the World Cup fixtures once and bucket them for both filters.
    /// `worldCupGamesWithTeams` filters + sorts + resolves teams over the whole
    /// feed; reading it once per render here — rather than through four separate
    /// computed properties — keeps that work off the scroll/update hitch path.
    private func buckets() -> Buckets {
        let all = viewModel.worldCupGamesWithTeams
        let now = Date()
        var live: [GameWithTeams] = []
        var upcoming: [GameWithTeams] = []
        var recent: [GameWithTeams] = []
        for gwt in all {
            let game = gwt.game
            if game.strStatus == "in" { live.append(gwt); continue }
            if isGameCompleted(game) { recent.append(gwt); continue }
            if (game.standardDate ?? .distantFuture) >= now { upcoming.append(gwt) }
        }
        return Buckets(
            live: live,
            upcomingByDay: groupedByDay(upcoming, ascending: true),
            recentByGroup: groupedByGroup(recent),
            allEmpty: all.isEmpty
        )
    }

    /// Completed matches sectioned by their World Cup group (Group A, B, …) with
    /// knockout fixtures last — so the Past filter reads as the tournament's
    /// structure, not a flat chronological wall. Falls back to day-by-day
    /// sections until the standings (the source of the team→group map) load.
    private func groupedByGroup(_ games: [GameWithTeams]) -> [(label: String, games: [GameWithTeams])] {
        let teamGroup = teamGroupMap()
        guard !teamGroup.isEmpty else {
            return groupedByDay(games, ascending: false).map { (Self.dayLabel($0.date), $0.games) }
        }
        let knockoutLabel = "Knockout Stage"
        var byGroup: [String: [GameWithTeams]] = [:]
        for gwt in games {
            let label = groupLabel(for: gwt.game, teamGroup: teamGroup) ?? knockoutLabel
            byGroup[label, default: []].append(gwt)
        }
        return byGroup.keys.sorted { a, b in
            if a == knockoutLabel { return false }
            if b == knockoutLabel { return true }
            return a < b
        }.map { label in
            (label, (byGroup[label] ?? []).sorted {
                ($0.game.standardDate ?? .distantPast) > ($1.game.standardDate ?? .distantPast)
            })
        }
    }

    /// Normalized nation name → group label, built from the loaded standings.
    private func teamGroupMap() -> [String: String] {
        var map: [String: String] = [:]
        for child in model.groups {
            guard let name = child.name, let entries = child.standings?.entries else { continue }
            for entry in entries {
                for key in [entry.team?.displayName, entry.team?.shortDisplayName, entry.team?.name] {
                    if let key, !key.isEmpty { map[Self.normalize(key)] = name }
                }
            }
        }
        return map
    }

    /// A fixture is a group-stage match only when both nations sit in the *same*
    /// group; a knockout tie pairs teams from different groups, so it returns nil
    /// and lands under "Knockout Stage".
    private func groupLabel(for game: Game, teamGroup: [String: String]) -> String? {
        let home = teamGroup[Self.normalize(game.strHomeTeam)]
        let away = teamGroup[Self.normalize(game.strAwayTeam)]
        return (home != nil && home == away) ? home : nil
    }

    private static func normalize(_ name: String) -> String {
        name.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }

    /// Buckets games by calendar day, capped to the next/previous 8 matchdays —
    /// mirrors `BrowseSportView.groupedByDay`.
    private func groupedByDay(_ games: [GameWithTeams], ascending: Bool) -> [(date: Date, games: [GameWithTeams])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: games) {
            cal.startOfDay(for: $0.game.standardDate ?? (ascending ? .distantFuture : .distantPast))
        }
        return grouped.keys.sorted(by: ascending ? (<) : (>)).prefix(8).map { day in
            (day, (grouped[day] ?? []).sorted {
                let a = $0.game.standardDate ?? .distantPast
                let b = $1.game.standardDate ?? .distantPast
                return ascending ? a < b : a > b
            })
        }
    }

    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    /// Day-header label matching Browse: Today / Tomorrow / Yesterday / weekday + date.
    private static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return dayLabelFormatter.string(from: date)
    }

    var body: some View {
        let data = buckets()
        return List {
            if !isEnabled {
                Section {
                    enableCTA
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            groupsRail

            Section {
                Picker("Time", selection: $timeFilter) {
                    ForEach(WCTimeFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            switch timeFilter {
            case .upcoming:
                if !data.live.isEmpty {
                    Section {
                        ForEach(data.live) { wcRow($0, isLive: true) }
                    } header: {
                        LiveAnimatedView()
                    }
                }
                ForEach(data.upcomingByDay, id: \.date) { day in
                    Section {
                        ForEach(day.games) { wcRow($0, isLive: false) }
                    } header: {
                        Text(Self.dayLabel(day.date))
                    }
                }
                bracketSection
                scorersSection
                if isEnabled && data.allEmpty && model.groups.isEmpty && !model.hasBracket {
                    Section {
                        emptyMessage("No World Cup matches scheduled right now. Check back closer to kickoff on June 11, 2026.")
                    }
                    .listRowBackground(Color.clear)
                }
            case .past:
                ForEach(data.recentByGroup, id: \.label) { bucket in
                    Section {
                        ForEach(bucket.games) { wcRow($0, isLive: false) }
                    } header: {
                        Text(bucket.label)
                    }
                }
                if data.recentByGroup.isEmpty {
                    Section {
                        emptyMessage("No completed matches yet.")
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("World Cup 2026")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .task { await model.load(from: viewModel) }
        .refreshable { await model.load(from: viewModel) }
        .alert("Scoreline Pro", isPresented: $shouldShowProAlert) {
            Button("Subscribe") { sheetType = .paywall }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This feature requires Scoreline Pro")
        }
        .sheet(item: $sheetType) { sheet in
            switch sheet {
            case .paywall:
                SubscriptionSheet(subscriptionPresented: .constant(true))
            #if os(iOS)
            case .calendar(let game):
                if let game { makeCalendarEvent(game: game) }
            #endif
            default:
                EmptyView()
            }
        }
    }

    #if os(iOS)
    private func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        event.title = "\(game.strAwayTeam) @ \(game.strHomeTeam)"
        if let gameDate = game.standardDate {
            event.startDate = gameDate
            event.endDate = gameDate.afterHoursFromNow(hours: 2)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif

    // MARK: - Sections

    /// Horizontal rail of compact group tables, mirroring the Games-tab hero, so
    /// the groups read at a glance above the Upcoming/Past schedule.
    @ViewBuilder
    private var groupsRail: some View {
        if !model.groups.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: .appSpace3) {
                        ForEach(Array(model.groups.enumerated()), id: \.offset) { _, group in
                            WCGroupCard(group: group)
                        }
                    }
                    .padding(.horizontal, .appSpace4)
                    .padding(.vertical, .appSpace2)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text("Groups")
            }
        } else if model.standingsLoading {
            Section {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } header: {
                Text("Groups")
            }
        }
    }

    private var enableCTA: some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            Text("Follow every match, group table, and the road to the final — without turning on all of soccer.")
                .font(.appCaption)
                .foregroundStyle(Color.appInkSoft)
            Button {
                shouldShowWorldCup = true
                viewModel.filterSports(force: true)
            } label: {
                Label("Enable World Cup", systemImage: "plus.circle.fill")
                    .font(.appHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .appSpace2)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .appCard(fill: Color.appAlt)
    }

    /// Browse-style dense match row (time/score on the right, self-navigating).
    @ViewBuilder
    private func wcRow(_ gwt: GameWithTeams, isLive: Bool) -> some View {
        CompactGameRowView(
            homeTeam: gwt.homeTeam ?? Team(strTeam: gwt.game.strHomeTeam),
            awayTeam: gwt.awayTeam ?? Team(strTeam: gwt.game.strAwayTeam),
            game: gwt.game,
            shouldShowSportsCalProAlert: $shouldShowProAlert,
            sheetType: $sheetType,
            isLive: isLive
        )
        .environment(viewModel)
        .environment(favorites)
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.appCaption)
            .foregroundStyle(Color.appInkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, .appSpace5)
    }

    @ViewBuilder
    private var bracketSection: some View {
        if model.hasBracket, let bracket = model.bracket {
            Section("Knockout Bracket") {
                NavigationLink {
                    bracketScreen(bracket)
                } label: {
                    Label("View full bracket", systemImage: "trophy")
                        .foregroundStyle(accent)
                }
            }
        }
    }

    @ViewBuilder
    private var scorersSection: some View {
        if !model.scorers.isEmpty {
            Section("Golden Boot") {
                WorldCupScorersView(scorers: Array(model.scorers.prefix(5)))
                if model.scorers.count > 5 {
                    NavigationLink {
                        WorldCupScorersScreen(scorers: model.scorers)
                    } label: {
                        Text("See all scorers").foregroundStyle(accent)
                    }
                }
            }
        }
    }

    private func bracketScreen(_ bracket: WorldCupBracket) -> some View {
        WorldCupBracketView(bracket: bracket, groups: model.groups)
            .environment(viewModel)
            .environment(favorites)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Bracket")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
    }

}
