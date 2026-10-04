//
//  SoccerCompetitionHubView.swift
//  SportsCal
//
//  One soccer competition, FotMob-style: its table (zones, form), its matches
//  (upcoming and results, from the app's own schedule) and its top scorers and
//  assisters, each linking to a player page. The table and leaders come from
//  `/soccer/competition/:leagueID`; a cup with no table opens on its matches.
//

import SwiftUI
import EventKit
import SportsCalModel

struct SoccerCompetitionHubView: View {
    let league: Leagues

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites

    @State private var hub: SoccerCompetitionHub?
    @State private var isLoading = true
    @State private var tab: Tab?
    @State private var showsResults = false
    @State private var leaderKind: LeaderKind = .goals
    @State private var games: [GameWithTeams] = []
    @State private var sheetType: SheetType?
    @State private var shouldShowProAlert = false

    private enum Tab: String, CaseIterable, Identifiable {
        case table = "Table"
        case matches = "Matches"
        case players = "Players"
        var id: String { rawValue }
    }

    private enum LeaderKind: String, CaseIterable, Identifiable {
        case goals = "Goals"
        case assists = "Assists"
        var id: String { rawValue }
    }

    private var availableTabs: [Tab] {
        var tabs: [Tab] = []
        if !(hub?.groups.isEmpty ?? true) { tabs.append(.table) }
        tabs.append(.matches)
        if !(hub?.scorers.isEmpty ?? true) || !(hub?.assisters.isEmpty ?? true) { tabs.append(.players) }
        return tabs
    }

    /// The chosen tab, or the first one this competition has.
    private var currentTab: Tab { tab.flatMap { availableTabs.contains($0) ? $0 : nil } ?? availableTabs[0] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .appSpace4) {
                if availableTabs.count > 1 {
                    Picker("Section", selection: Binding(get: { currentTab }, set: { tab = $0 })) {
                        ForEach(availableTabs) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                switch currentTab {
                case .table:
                    if let hub {
                        SoccerLeagueTableView(groups: hub.groups, zones: hub.zones)
                    }
                case .matches:
                    matches
                case .players:
                    players
                }
            }
            .padding(.horizontal, .appSpace4)
            .padding(.vertical, .appSpace3)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .overlay {
            if isLoading && hub == nil && games.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle(league.leagueName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        games = viewModel.gamesWithTeams(inLeague: league)
        if let fresh = try? await NetworkHandler.getSoccerCompetition(league: league) {
            hub = fresh
        }
    }

    // MARK: - Matches

    private var matches: some View {
        let now = Date()
        let live = games.filter { $0.game.strStatus == "in" }
        let results = games.filter { isGameCompleted($0.game) }.reversed()
        let upcoming = games.filter {
            $0.game.strStatus != "in" && !isGameCompleted($0.game) && ($0.game.standardDate ?? .distantFuture) >= now
        }
        let shown = showsResults ? Array(results) : upcoming
        return VStack(alignment: .leading, spacing: .appSpace4) {
            Picker("Matches", selection: $showsResults) {
                Text("Upcoming").tag(false)
                Text("Results").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !live.isEmpty {
                dayCard(title: "Live", games: live, isLive: true)
            }
            if shown.isEmpty {
                Text(showsResults ? "No results yet" : "No upcoming matches")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .appSpace5)
            } else {
                ForEach(groupedByDay(shown), id: \.day) { group in
                    dayCard(title: dayTitle(group.day), games: group.games, isLive: false)
                }
            }
        }
    }

    private func dayCard(title: String, games: [GameWithTeams], isLive: Bool) -> some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            Text(title.uppercased()).appEyebrow().foregroundStyle(isLive ? Color.appLive : Color.app(.soccer))
            ForEach(games) { gwt in
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
        }
        .appCard()
    }

    /// Games bucketed by local calendar day, in the order given.
    private func groupedByDay(_ games: [GameWithTeams]) -> [(day: Date, games: [GameWithTeams])] {
        var groups: [(day: Date, games: [GameWithTeams])] = []
        let calendar = Calendar.current
        for gwt in games {
            let day = calendar.startOfDay(for: gwt.game.standardDate ?? .distantFuture)
            if let last = groups.indices.last, groups[last].day == day {
                groups[last].games.append(gwt)
            } else {
                groups.append((day, [gwt]))
            }
        }
        return groups
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: - Players

    private var players: some View {
        let leaders = leaderKind == .goals ? (hub?.scorers ?? []) : (hub?.assisters ?? [])
        return VStack(alignment: .leading, spacing: .appSpace4) {
            Picker("Leaders", selection: $leaderKind) {
                ForEach(LeaderKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(spacing: 0) {
                ForEach(leaders) { leader in
                    SoccerPlayerLink(athleteID: leader.athleteID, name: leader.name) {
                        leaderRow(leader)
                    }
                    if leader.id != leaders.last?.id { Divider().opacity(0.5) }
                }
            }
            .appCard()
        }
    }

    private func leaderRow(_ leader: SoccerLeader) -> some View {
        HStack(spacing: 10) {
            Text("\(leader.rank)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            WCBadge(url: leader.teamBadge, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(leader.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appInk)
                Text([leader.teamName, "\(leader.appearances) apps"].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(leaderKind == .goals ? leader.goals : leader.assists)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Color.appInk)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
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
}
