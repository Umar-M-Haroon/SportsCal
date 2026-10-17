//
//  LeagueHubView.swift
//  SportsCal (iOS)
//
//  One league's home, opened from its Browse chip: the standings (conferences,
//  divisions) and its schedule by matchday. Soccer competitions keep their richer
//  hub (zones, form, top scorers) — `LeagueHubView` hands those to
//  `SoccerCompetitionHubView`.
//

import SwiftUI
import EventKit
import SportsCalModel

struct LeagueHubView: View {
    let league: Leagues
    /// The league's games from the Browse feed, unresolved.
    let games: [Game]

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites

    var body: some View {
        if league.isSoccer {
            SoccerCompetitionHubView(league: league)
                .environment(viewModel)
                .environment(favorites)
        } else {
            TeamLeagueHub(league: league, games: games)
                .environment(viewModel)
                .environment(favorites)
        }
    }
}

/// The browse row linking a league's hub.
struct LeagueHubLink: View {
    let league: Leagues
    let sport: SportType
    let games: [Game]

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites

    var body: some View {
        NavigationLink {
            LeagueHubView(league: league, games: games)
                .environment(viewModel)
                .environment(favorites)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.number")
                    .foregroundStyle(Color.app(sport))
                VStack(alignment: .leading, spacing: 2) {
                    Text(league.leagueName).font(.headline)
                    Text(league.isSoccer ? "Table · Matches · Top Scorers" : "Standings · Schedule")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TeamLeagueHub: View {
    let league: Leagues
    let games: [Game]

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites

    @State private var tab: Tab = .standings
    @State private var standing: Standing?
    @State private var didLoadStandings = false
    @State private var showsResults = false
    @State private var resolved: [GameWithTeams] = []
    @State private var liveEventIDs: Set<String> = []
    @State private var sheetType: SheetType?
    @State private var shouldShowProAlert = false

    /// Matchdays shown per direction; the day strip in Browse reaches the rest.
    private static let matchdayLimit = 14

    private enum Tab: String, CaseIterable, Identifiable {
        case standings = "Standings"
        case schedule = "Schedule"
        var id: String { rawValue }
    }

    private var sport: SportType { SportType(league: league) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .appSpace4) {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch tab {
                case .standings: standings
                case .schedule: schedule
                }
            }
            .padding(.horizontal, .appSpace4)
            .padding(.vertical, .appSpace3)
        }
        .background(Color.appBackground.ignoresSafeArea())
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
        let leagueID = String(league.rawValue)
        let live = viewModel.liveEventsForSport(sport).filter { $0.idLeague == leagueID }
        let liveIDs = Set(live.compactMap(\.idEvent))
        liveEventIDs = liveIDs
        resolved = (live + games.filter { !liveIDs.contains($0.idEvent ?? "") })
            .sorted { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
            .compactMap { viewModel.resolveGameWithTeams($0) }

        let loaded = try? await NetworkHandler.getStandings(for: leagueID)
        guard !Task.isCancelled else { return }
        standing = loaded ?? standing
        didLoadStandings = true
    }

    // MARK: - Standings

    @ViewBuilder
    private var standings: some View {
        let groups = (standing?.standings.children ?? []).compactMap { child -> (name: String?, entries: [Entry])? in
            guard let entries = child.standings?.entries, !entries.isEmpty else { return nil }
            return (child.name, ranked(entries))
        }
        if !didLoadStandings {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, .appSpace5)
        } else if groups.isEmpty {
            ContentUnavailableView("No Standings", systemImage: "list.number",
                                   description: Text("\(league.leagueName) standings aren't available right now."))
        } else {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                LeagueStandingsTable(name: group.name, entries: group.entries, isSoccer: false,
                                     isHighlighted: isFollowed)
                    .appCard()
            }
        }
    }

    /// Best first. ESPN's league-level order isn't by record (MLB lists division seeds and
    /// then the rest), and the table numbers rows as given. Hockey ranks by points (overtime
    /// losses count), everything else by win percentage; wins break ties.
    private func ranked(_ entries: [Entry]) -> [Entry] {
        func stat(_ entry: Entry, _ name: String) -> Double {
            entry.stats?.first { $0.name == name }?.value ?? -1
        }
        let key = sport == .hockey ? "points" : "winPercent"
        // ESPN's order breaks remaining ties, so a league missing both stats keeps it.
        return entries.enumerated().sorted {
            let a = stat($0.element, key), b = stat($1.element, key)
            if a != b { return a > b }
            let winsA = stat($0.element, "wins"), winsB = stat($1.element, "wins")
            return winsA != winsB ? winsA > winsB : $0.offset < $1.offset
        }.map(\.element)
    }

    /// Bolds the rows of teams the user follows.
    private func isFollowed(_ entry: Entry) -> Bool {
        guard let team = entry.team else { return false }
        return [team.displayName, team.shortDisplayName, team.name]
            .compactMap { $0 }
            .contains(where: favorites.teams.contains)
    }

    // MARK: - Schedule

    private var schedule: some View {
        let now = Date()
        let isLive = { (gwt: GameWithTeams) in liveEventIDs.contains(gwt.game.idEvent ?? "") }
        let live = resolved.filter(isLive)
        let results = resolved.filter { !isLive($0) && isGameCompleted($0.game) }.reversed()
        let upcoming = resolved.filter {
            !isLive($0) && !isGameCompleted($0.game) && ($0.game.standardDate ?? .distantFuture) >= now
        }
        let days = Array(groupedByDay(showsResults ? Array(results) : upcoming).prefix(Self.matchdayLimit))
        return VStack(alignment: .leading, spacing: .appSpace4) {
            Picker("Games", selection: $showsResults) {
                Text("Upcoming").tag(false)
                Text("Results").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !live.isEmpty {
                dayCard(title: "Live", games: live, isLive: true)
            }
            if days.isEmpty {
                Text(showsResults ? "No results yet" : "No upcoming games")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .appSpace5)
            } else {
                LazyVStack(alignment: .leading, spacing: .appSpace4) {
                    ForEach(days, id: \.day) { group in
                        dayCard(title: dayTitle(group.day), games: group.games, isLive: false)
                    }
                }
            }
        }
    }

    private func dayCard(title: String, games: [GameWithTeams], isLive: Bool) -> some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            Text(title.uppercased()).appEyebrow().foregroundStyle(isLive ? Color.appLive : Color.app(sport))
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

    #if os(iOS)
    private func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        let separator = (game.playoff?.isNeutralSite == true) ? " vs " : " @ "
        event.title = "\(game.strAwayTeam)\(separator)\(game.strHomeTeam)"
        if let gameDate = game.standardDate {
            event.startDate = gameDate
            event.endDate = gameDate.afterHoursFromNow(hours: 3)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif
}
