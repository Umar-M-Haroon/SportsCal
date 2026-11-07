//
//  SoccerCompetitionHubView.swift
//  SportsCal
//
//  One soccer competition, FotMob-style: its table (zones, form), its matches
//  (upcoming and results, from the app's own schedule) and its top scorers and
//  assisters, each linking to a player page. The table and leaders come from
//  `/soccer/competition/:leagueID`; a cup with no table opens on its matches.
//  League matches group by matchday where TheSportsDB gave one; table rows open the
//  team page, and the user's teams are picked out.
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
    /// The table / leaders fetch failed (not a 404: a cup with neither is fine).
    @State private var hubLoadFailed = false
    @State private var tab: Tab?
    @State private var showsResults = false
    @State private var leaderKind: LeaderKind = .goals
    @State private var games: [GameWithTeams] = []
    @State private var liveEventIDs: Set<String> = []
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

                if hubLoadFailed && hub == nil {
                    hubErrorCard
                }

                switch currentTab {
                case .table:
                    if let hub {
                        SoccerLeagueTableView(
                            groups: hub.groups, zones: hub.zones,
                            team: { teamForTableRow($0) },
                            isFavorite: { row in
                                teamForTableRow(row).map { favorites.contains(team: $0) } ?? favorites.contains(row.teamName)
                            }
                        )
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

    /// Fixtures as Browse gets them: the soccer schedule already loaded when soccer
    /// is on (fetched otherwise), with the live feed's copies laid over it — schedule
    /// copies keep TheSportsDB's statuses, so only the live feed says what's in play.
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let fetchedHub = fetchHub()

        let leagueID = String(league.rawValue)
        var schedule = viewModel.gamesDict[.soccer] ?? []
        if schedule.isEmpty, let fetched = try? await NetworkHandler.getScheduleFor(sport: .soccer) {
            schedule = fetched.events
        }
        let live = viewModel.liveEventsForSport(.soccer).filter { $0.idLeague == leagueID }
        let liveIDs = Set(live.compactMap(\.idEvent))
        games = (live + schedule.filter { $0.idLeague == leagueID && !liveIDs.contains($0.idEvent ?? "") })
            .sorted { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
            .compactMap { viewModel.resolveGameWithTeams($0) }
        liveEventIDs = liveIDs

        switch await fetchedHub {
        case .success(let fresh):
            hub = fresh
            hubLoadFailed = false
        case .failure(let error):
            // A 404 is a competition with no table or leaders; anything else is worth a retry.
            hubLoadFailed = !(error is NetworkHandler.SoccerMatchNotAvailable)
        }
    }

    private func fetchHub() async -> Result<SoccerCompetitionHub, Error> {
        do {
            return .success(try await NetworkHandler.getSoccerCompetition(league: league))
        } catch {
            return .failure(error)
        }
    }

    private var hubErrorCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text("Couldn't load the table and top scorers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Retry") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
        }
        .appCard()
    }

    /// The app's team for a table row (ESPN names it), for the team page link.
    private func teamForTableRow(_ row: SoccerTableRow) -> Team? {
        if let team = TeamsManager.shared.team(byNameOrAlias: row.teamName) { return team }
        let key = Self.nameKey(row.teamName)
        for gwt in games {
            for team in [gwt.homeTeam, gwt.awayTeam].compactMap({ $0 })
            where [team.strTeam, team.strTeamShort, team.strAlternate].contains(where: { $0.map(Self.nameKey) == key }) {
                return team
            }
        }
        return nil
    }

    /// "Brighton & Hove Albion" and "Brighton and Hove Albion FC" match.
    private static func nameKey(_ name: String) -> String {
        let spaced = name.lowercased().replacingOccurrences(of: "&", with: " and ")
        let words = spaced.split { !$0.isLetter && !$0.isNumber }.filter { !["fc", "afc", "cf", "sc"].contains($0) }
        return words.joined(separator: " ")
    }

    // MARK: - Matches

    private var matches: some View {
        let now = Date()
        let isLive = { (gwt: GameWithTeams) in liveEventIDs.contains(gwt.game.idEvent ?? "") }
        let live = games.filter(isLive)
        let results = games.filter { !isLive($0) && isGameCompleted($0.game) }.reversed()
        let upcoming = games.filter {
            !isLive($0) && !isGameCompleted($0.game) && ($0.game.standardDate ?? .distantFuture) >= now
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
                ForEach(groupedForDisplay(shown), id: \.id) { group in
                    dayCard(title: group.title, games: group.games, isLive: false,
                            showsDays: group.id.hasPrefix("md-"))
                }
            }
        }
    }

    /// `showsDays`: a matchday spans days, so its rows get a day line where it changes.
    private func dayCard(title: String, games: [GameWithTeams], isLive: Bool, showsDays: Bool = false) -> some View {
        let calendar = Calendar.current
        return VStack(alignment: .leading, spacing: .appSpace2) {
            Text(title.uppercased()).appEyebrow().foregroundStyle(isLive ? Color.appLive : Color.app(.soccer))
            ForEach(Array(games.enumerated()), id: \.element.id) { index, gwt in
                if showsDays, let date = gwt.game.standardDate,
                   index == 0 || games[index - 1].game.standardDate.map({ !calendar.isDate($0, inSameDayAs: date) }) ?? true {
                    Text(dayTitle(calendar.startOfDay(for: date)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, index == 0 ? 0 : 4)
                }
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

    /// Matchdays when most of the list has one (a league), otherwise days (a cup, or a
    /// schedule from a server that doesn't send rounds). A game with no matchday in a
    /// matchday list gets its own day group, in order.
    private func groupedForDisplay(_ games: [GameWithTeams]) -> [(id: String, title: String, games: [GameWithTeams])] {
        let withMatchday = games.filter { $0.game.soccerMatchday != nil }.count
        guard !games.isEmpty, Double(withMatchday) / Double(games.count) >= 0.8 else {
            return groupedByDay(games).map { (id: "day-\($0.day.timeIntervalSince1970)", title: dayTitle($0.day), games: $0.games) }
        }
        var groups: [(id: String, title: String, games: [GameWithTeams])] = []
        var index: [String: Int] = [:]
        let calendar = Calendar.current
        for gwt in games {
            let id: String
            let title: String
            if let matchday = gwt.game.soccerMatchday {
                id = "md-\(matchday)"
                title = "Matchday \(matchday)"
            } else {
                let day = calendar.startOfDay(for: gwt.game.standardDate ?? .distantFuture)
                id = "day-\(day.timeIntervalSince1970)"
                title = dayTitle(day)
            }
            if let existing = index[id] {
                groups[existing].games.append(gwt)
            } else {
                index[id] = groups.count
                groups.append((id: id, title: title, games: [gwt]))
            }
        }
        return groups
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
        event.title = game.matchupTitle
        if let gameDate = game.standardDate {
            event.startDate = gameDate
            event.endDate = gameDate.afterHoursFromNow(hours: 2)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif
}
