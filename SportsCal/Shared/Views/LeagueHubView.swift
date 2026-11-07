//
//  LeagueHubView.swift
//  SportsCal (iOS)
//
//  One league's home, opened from its Browse chip: the standings (conferences,
//  divisions), college polls, and its schedule by matchday. Soccer competitions keep their richer
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
                    Text(league.isSoccer ? "Table · Matches · Top Scorers"
                         : league.hasPollRankings ? "Rankings · Standings · Schedule" : "Standings · Schedule")
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

    @State private var tab: Tab
    @State private var standing: Standing?
    @State private var didLoadStandings = false
    @State private var showsResults = false
    @State private var resolved: [GameWithTeams] = []
    @State private var liveEventIDs: Set<String> = []
    @State private var sheetType: SheetType?
    @State private var shouldShowProAlert = false
    /// College only: show one conference's games.
    @State private var conference: CollegeConference?

    /// Matchdays shown per direction; the day strip in Browse reaches the rest.
    private static let matchdayLimit = 14
    /// Football weeks shown per direction.
    private static let weekLimit = 4

    init(league: Leagues, games: [Game]) {
        self.league = league
        self.games = games
        _tab = State(initialValue: league.hasPollRankings ? .rankings : .standings)
    }

    private enum Tab: String, CaseIterable, Identifiable {
        case rankings = "Rankings"
        case standings = "Standings"
        case schedule = "Schedule"
        var id: String { rawValue }
    }

    private var tabs: [Tab] {
        league.hasPollRankings ? Tab.allCases : [.standings, .schedule]
    }

    private var sport: SportType { SportType(league: league) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .appSpace4) {
                Picker("Section", selection: $tab) {
                    ForEach(tabs) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch tab {
                case .rankings:
                    PollRankingsView(league: league)
                        .environment(favorites)
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
        // By fixture, not id: live games carry ESPN ids, schedule rows TheSportsDB ones.
        let liveCopies = LiveFixtureIndex(live: live, schedule: games)
        resolved = (live + games.filter { !liveCopies.contains($0) })
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
        let groups = standing?.groups ?? []
        if !didLoadStandings {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, .appSpace5)
        } else if groups.isEmpty {
            ContentUnavailableView("No Standings", systemImage: "list.number",
                                   description: Text("\(league.leagueName) standings aren't available right now."))
        } else {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                LeagueStandingsTable(name: group.name, entries: group.entries, league: league,
                                     isHighlighted: isFollowed)
                    .appCard()
            }
        }
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
        let filtered = resolved.filter { gwt in
            guard let conference else { return true }
            return gwt.game.collegeConferences.contains(conference)
        }
        let live = filtered.filter(isLive)
        let results = filtered.filter { !isLive($0) && isGameCompleted($0.game) }.reversed()
        let upcoming = filtered.filter {
            !isLive($0) && !isGameCompleted($0.game) && ($0.game.standardDate ?? .distantFuture) >= now
        }
        let shown = showsResults ? Array(results) : upcoming
        let days = Array(groupedByDay(shown).prefix(Self.matchdayLimit))
        let weeks = league.isFootball ? Array(groupedByWeek(shown).prefix(Self.weekLimit)) : []
        return VStack(alignment: .leading, spacing: .appSpace4) {
            Picker("Games", selection: $showsResults) {
                Text("Upcoming").tag(false)
                Text("Results").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if league == .ncaaf {
                conferencePicker
            }
            if !live.isEmpty {
                dayCard(title: "Live", games: live, isLive: true)
            }
            if !weeks.isEmpty {
                LazyVStack(alignment: .leading, spacing: .appSpace4) {
                    ForEach(weeks, id: \.id) { week in
                        weekCard(week)
                    }
                }
            } else if days.isEmpty {
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

    private var conferencePicker: some View {
        Menu {
            Button("All Conferences") { conference = nil }
            Divider()
            ForEach(CollegeConference.allCases, id: \.self) { option in
                Button {
                    conference = option
                } label: {
                    if conference == option {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(conference?.displayName ?? "All Conferences")
                Image(systemName: "chevron.down").imageScale(.small)
            }
            .font(.subheadline.weight(.medium))
        }
        .accessibilityLabel("Conference: \(conference?.displayName ?? "All Conferences")")
    }

    /// One football week: its games under a header per kickoff slot, so a college
    /// Saturday reads as noon / afternoon / night windows instead of one long list.
    private struct WeekGroup {
        var id: String
        var title: String
        var games: [GameWithTeams]
    }

    /// Games bucketed by football week, in the order given. Games without a week
    /// (preseason, bowls, playoffs) group by day.
    private func groupedByWeek(_ games: [GameWithTeams]) -> [WeekGroup] {
        var groups: [WeekGroup] = []
        for gwt in games {
            let id: String
            let title: String
            if let week = gwt.game.footballWeek {
                id = "\(gwt.game.resolvedSeason ?? "")-w\(week)"
                title = "Week \(week)"
            } else {
                let day = Calendar.current.startOfDay(for: gwt.game.standardDate ?? .distantFuture)
                id = "d\(day.timeIntervalSince1970)"
                title = dayTitle(day)
            }
            if let index = groups.firstIndex(where: { $0.id == id }) {
                groups[index].games.append(gwt)
            } else {
                groups.append(WeekGroup(id: id, title: title, games: [gwt]))
            }
        }
        return groups
    }

    private func weekCard(_ week: WeekGroup) -> some View {
        let slots = groupedByKickoff(week.games)
        return VStack(alignment: .leading, spacing: .appSpace2) {
            Text(week.title.uppercased()).appEyebrow().foregroundStyle(Color.app(sport))
            ForEach(slots, id: \.kickoff) { slot in
                Text(slotTitle(slot.kickoff))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(slot.games) { gwt in
                    CompactGameRowView(
                        homeTeam: gwt.homeTeam ?? Team(strTeam: gwt.game.strHomeTeam),
                        awayTeam: gwt.awayTeam ?? Team(strTeam: gwt.game.strAwayTeam),
                        game: gwt.game,
                        shouldShowSportsCalProAlert: $shouldShowProAlert,
                        sheetType: $sheetType,
                        isLive: false
                    )
                    .environment(viewModel)
                    .environment(favorites)
                }
            }
        }
        .appCard()
    }

    /// Games bucketed by kickoff: by the hour for college (whose Saturdays run a
    /// dozen games a window), by day for the NFL.
    private func groupedByKickoff(_ games: [GameWithTeams]) -> [(kickoff: Date, games: [GameWithTeams])] {
        let calendar = Calendar.current
        var groups: [(kickoff: Date, games: [GameWithTeams])] = []
        for gwt in games {
            let date = gwt.game.standardDate ?? .distantFuture
            let key: Date
            if league == .ncaaf {
                key = calendar.dateInterval(of: .hour, for: date)?.start ?? date
            } else {
                key = calendar.startOfDay(for: date)
            }
            if let index = groups.firstIndex(where: { $0.kickoff == key }) {
                groups[index].games.append(gwt)
            } else {
                groups.append((key, [gwt]))
            }
        }
        return groups
    }

    private func slotTitle(_ kickoff: Date) -> String {
        let day = dayTitle(Calendar.current.startOfDay(for: kickoff))
        guard league == .ncaaf else { return day }
        return "\(day) · \(kickoff.formatted(date: .omitted, time: .shortened))"
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
