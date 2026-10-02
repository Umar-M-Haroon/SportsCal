//
//  TeamDetailView.swift
//  SportsCal
//
//  A team profile screen: badge + name header with recent form, a follow toggle, the
//  next (or live) game, the team's schedule and results derived from the games already
//  loaded into GameViewModel, its league table, team alerts, and profile/roster.
//
//  Reached via `.navigationDestination(for: Team.self)` or a view-destination link.
//  Everything this screen pushes (games, opponents) goes through item-based
//  destinations, so it can sit on any stack without mixing value and view links.
//

import SwiftUI
import SportsCalModel
import NukeUI
#if os(iOS)
import EventKit
import EventKitUI
#endif

struct TeamDetailView: View {
    let team: Team

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @Environment(SubscriptionManager.self) private var subscriptionManager

    /// Extended profile + roster, loaded lazily from the server. Nil until the fetch
    /// resolves; an empty/failed fetch leaves it nil so the section shows "unavailable".
    @State private var detail: TeamDetail?
    @State private var didLoadDetail = false

    @State private var standing: Standing?
    @State private var standingsLeague: Leagues?
    @State private var didLoadStandings = false
    @State private var showFullTable = false

    @State private var showAllUpcoming = false
    @State private var teamAlertsOn = false
    /// Set by NotifyButton's per-game reminder gate and by the team-alert gate.
    @State private var shouldShowSportsCalProAlert = false
    /// True when the team-alert gate raised the alert, for its specific message.
    @State private var proAlertIsForTeamAlerts = false
    @State private var sheetType: SheetType?
    @State private var selectedGameID: String?
    @State private var selectedOpponent: Team?

    private static let upcomingPreviewCount = 10

    private var isFavorited: Bool { favorites.contains(team: team) }

    // MARK: - Body

    var body: some View {
        // Derived once per render: one pass over the loaded games instead of one per
        // section. `totalGames` runs to thousands of rows.
        let schedule = TeamSchedule(
            team: team,
            games: viewModel.totalGames ?? [],
            liveEvents: viewModel.liveEvents
        )

        List {
            Section {
                header(schedule)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if let featured = schedule.live.first ?? schedule.upcoming.first {
                Section(schedule.live.isEmpty ? "Next Game" : "Live Now") {
                    nextGameCard(featured, isLive: !schedule.live.isEmpty)
                }
            }

            if schedule.live.count > 1 {
                Section("Also Live") {
                    ForEach(schedule.live.dropFirst()) { gameRow($0) }
                }
            }

            // The first upcoming game is already the "Next Game" card unless a live
            // game took that slot.
            let remainingUpcoming = schedule.live.isEmpty ? Array(schedule.upcoming.dropFirst()) : schedule.upcoming
            if !remainingUpcoming.isEmpty {
                Section("Upcoming") {
                    let shown = showAllUpcoming ? remainingUpcoming : Array(remainingUpcoming.prefix(Self.upcomingPreviewCount))
                    ForEach(shown) { gameRow($0) }
                    if remainingUpcoming.count > Self.upcomingPreviewCount {
                        Button(showAllUpcoming ? "Show Less" : "Show All \(remainingUpcoming.count)") {
                            withAnimation { showAllUpcoming.toggle() }
                        }
                        .font(.subheadline)
                    }
                }
            }

            if !schedule.results.isEmpty {
                Section("Recent Results") {
                    ForEach(schedule.results.prefix(20)) { gameRow($0) }
                }
            }

            if schedule.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Games Scheduled",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("There are no loaded games for this team right now.")
                    )
                }
            }

            standingsSection

            alertsSection

            rosterAndInfoSections(record: schedule.record)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .task(id: team.idTeam) { await loadDetail() }
        .task(id: schedule.primaryLeague?.rawValue) { await loadStandings(league: schedule.primaryLeague) }
        .onAppear { teamAlertsOn = alertableTeamID.map { viewModel.appStorage.teamAlertTeamIDs.contains($0) } ?? false }
        .navigationTitle(team.strTeam ?? "Team")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorited ? "star.fill" : "star")
                        .foregroundStyle(isFavorited ? .yellow : .secondary)
                }
                .accessibilityLabel(isFavorited ? "Remove favorite" : "Add favorite")
            }
        }
        .navigationDestination(item: $selectedOpponent) { opponent in
            TeamDetailView(team: opponent)
                .environment(viewModel)
                .environment(favorites)
        }
        .navigationDestination(item: $selectedGameID) { gameID in
            gameDestination(gameID)
        }
        .alert("Scoreline Pro", isPresented: $shouldShowSportsCalProAlert) {
            Button("Subscribe") { sheetType = .paywall }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(proAlertIsForTeamAlerts
                 ? "Alerts for more than one team require Scoreline Pro"
                 : "This feature requires Scoreline Pro")
        }
        .onChange(of: shouldShowSportsCalProAlert) { _, showing in
            if !showing { proAlertIsForTeamAlerts = false }
        }
        .sheet(item: $sheetType) { sheet in
            switch sheet {
            case .calendar(let eventGame):
                #if os(iOS)
                if let game = eventGame {
                    makeCalendarEvent(game: game)
                }
                #else
                EmptyView()
                #endif
            case .paywall:
                SubscriptionSheet(subscriptionPresented: Binding(
                    get: { sheetType != nil },
                    set: { if !$0 { sheetType = nil } }
                ))
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Header

    private func header(_ schedule: TeamSchedule) -> some View {
        VStack(spacing: 12) {
            badge(team.strTeamBadge, size: 96)

            VStack(spacing: 4) {
                Text(team.strTeam ?? "Team")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    if let sport = schedule.sport ?? profileSport {
                        Label(sport.displayName, systemImage: sport.systemImage)
                            .foregroundStyle(sport.color)
                    }
                    Text(team.shortCode)
                        .foregroundStyle(.secondary)
                    if let record = schedule.record {
                        Text("·").foregroundStyle(.tertiary)
                        Text(record)
                            .fontWeight(.semibold)
                    }
                }
                .font(.subheadline)

                if !schedule.form.isEmpty {
                    FormStrip(results: schedule.form)
                        .padding(.top, 4)
                }
            }

            Button(action: toggleFavorite) {
                Label(isFavorited ? "Following" : "Follow",
                      systemImage: isFavorited ? "star.fill" : "star")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isFavorited ? .yellow : .accentColor)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    /// Sport from the server profile's league name, for teams with no loaded games.
    private var profileSport: SportType? {
        guard let leagueName = detail?.profile?.league else { return nil }
        return Leagues.allCases.first { $0.leagueName == leagueName }.map { SportType(league: $0) }
    }

    // MARK: - Next game

    @ViewBuilder
    private func nextGameCard(_ game: Game, isLive: Bool) -> some View {
        if let teams = viewModel.getTeams(for: game) {
            let isHome = TeamSchedule.isHome(team, in: game, home: teams.home)
            let opponent = isHome ? teams.away : teams.home
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button { selectedOpponent = opponent } label: {
                        HStack(spacing: 10) {
                            badge(opponent.strTeamBadge, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(isHome ? "vs" : "@") \(opponent.strTeam ?? (isHome ? game.strAwayTeam : game.strHomeTeam))")
                                    .font(.headline)
                                    .lineLimit(1)
                                if let league = game.strLeague {
                                    Text(league)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .tint(.primary)

                    Spacer(minLength: 8)

                    if isLive {
                        liveScore(game, isHome: isHome)
                    }
                }

                if isLive {
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text(game.displayStatus ?? "Live")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let date = game.standardDate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                            .font(.subheadline)
                        if date.timeIntervalSinceNow > 0, date.timeIntervalSinceNow < 7 * 24 * 60 * 60 {
                            (Text("Starts in ") + Text(date, style: .relative))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button { selectedGameID = game.id } label: {
                        Label("Details", systemImage: "info.circle")
                            .frame(maxWidth: .infinity)
                    }
                    if !isLive {
                        NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                            .frame(maxWidth: .infinity)
                        #if os(iOS)
                        Button {
                            EKEventStore().requestAccess(to: .event) { _, _ in
                                DispatchQueue.main.async { sheetType = .calendar(game: game) }
                            }
                        } label: {
                            Label("Calendar", systemImage: "calendar")
                                .frame(maxWidth: .infinity)
                        }
                        #endif
                    }
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
                .labelStyle(.titleAndIcon)
            }
            .padding(.vertical, 4)
        }
    }

    /// "54 – 50" from this team's side, the leader emphasised.
    private func liveScore(_ game: Game, isHome: Bool) -> some View {
        let ours = Int((isHome ? game.intHomeScore : game.intAwayScore) ?? "")
        let theirs = Int((isHome ? game.intAwayScore : game.intHomeScore) ?? "")
        return HStack(spacing: 6) {
            Text(ours.map(String.init) ?? "-")
                .fontWeight((ours ?? 0) >= (theirs ?? 0) ? .bold : .regular)
            Text("–").foregroundStyle(.secondary)
            Text(theirs.map(String.init) ?? "-")
                .fontWeight((theirs ?? 0) > (ours ?? 0) ? .bold : .regular)
        }
        .font(.title2.monospacedDigit())
    }

    // MARK: - Rows

    @ViewBuilder
    private func gameRow(_ game: Game) -> some View {
        if let teams = viewModel.getTeams(for: game) {
            let isHome = TeamSchedule.isHome(team, in: game, home: teams.home)
            let opponent = isHome ? teams.away : teams.home
            TeamScheduleRow(
                game: game,
                isHome: isHome,
                opponent: opponent,
                onOpponentTap: { selectedOpponent = opponent }
            )
            .contentShape(Rectangle())
            .onTapGesture { selectedGameID = game.id }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { selectedGameID = game.id }
            .contextMenu {
                Button {
                    selectedGameID = game.id
                } label: {
                    Label("Game Details", systemImage: "info.circle")
                }
                Button {
                    selectedOpponent = opponent
                } label: {
                    Label("View \(opponent.strTeam ?? "Opponent")", systemImage: "person.3")
                }
            }
        }
    }

    @ViewBuilder
    private func gameDestination(_ gameID: String) -> some View {
        let game = viewModel.liveEvents.first { $0.id == gameID }
            ?? viewModel.totalGames?.first { $0.id == gameID }
        if let game, let teams = viewModel.getTeams(for: game) {
            AdaptiveGameDetail(game: game, homeTeam: teams.home, awayTeam: teams.away)
                .environment(viewModel)
                .environment(favorites)
        } else {
            ContentUnavailableView("Game Unavailable", systemImage: "sportscourt")
        }
    }

    // MARK: - Standings

    @ViewBuilder
    private var standingsSection: some View {
        if let league = standingsLeague {
            Section {
                if !didLoadStandings {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                } else if let groups = standingGroups, !groups.isEmpty {
                    // Just the team's own group (conference / division / table) by
                    // default; the whole league on request.
                    let own = groups.filter { $0.entries.contains(where: isThisTeam) }
                    let shown = (showFullTable || own.isEmpty) ? groups : own
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, group in
                        LeagueStandingsTable(
                            name: group.name,
                            entries: group.entries,
                            isSoccer: league.isSoccer,
                            isHighlighted: isThisTeam
                        )
                    }
                    if !own.isEmpty, groups.count > own.count {
                        Button(showFullTable ? "Show \(own.first?.name ?? "Group") Only" : "Show Full Standings") {
                            withAnimation { showFullTable.toggle() }
                        }
                        .font(.subheadline)
                    }
                } else {
                    Label("Standings not available", systemImage: "list.number")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } header: {
                Text("Standings · \(league.leagueName)")
            }
        }
    }

    private var standingGroups: [(name: String?, entries: [Entry])]? {
        standing?.standings.children?.compactMap { child in
            guard let entries = child.standings?.entries, !entries.isEmpty else { return nil }
            return (child.name, entries)
        }
    }

    /// Whether a standings row (ESPN naming) is this team (TheSportsDB naming).
    private func isThisTeam(_ entry: Entry) -> Bool {
        guard let espn = entry.team else { return false }
        let names = [team.strTeam, team.strAlternate].compactMap { $0.map(Self.normalize) }
        let espnNames = [espn.displayName, espn.shortDisplayName, espn.name]
            .compactMap { $0.map(Self.normalize) }
        if espnNames.contains(where: names.contains) { return true }
        if let abbreviation = espn.abbreviation?.uppercased(), abbreviation == team.shortCode.uppercased() {
            return true
        }
        return false
    }

    private static func normalize(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    // MARK: - Alerts

    /// The team's id when it's a real TheSportsDB team — opponents opened from a game
    /// row can be stand-ins whose `idTeam` is an event id, which can't drive alerts.
    private var alertableTeamID: String? {
        guard let id = team.idTeam, !id.isEmpty, TeamsManager.shared.team(byID: id) != nil else { return nil }
        return id
    }

    @ViewBuilder
    private var alertsSection: some View {
        if alertableTeamID != nil {
            Section {
                Toggle(isOn: Binding(get: { teamAlertsOn }, set: setTeamAlerts)) {
                    Label("Alert When Every Game Starts", systemImage: "bell.badge")
                }
                #if os(iOS)
                if isFavorited, viewModel.appStorage.autoFollowFavorites {
                    Label("Live Activities start automatically for this team's games.", systemImage: "livephoto")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                #endif
            } header: {
                Text("Alerts")
            } footer: {
                if !subscriptionManager.isPro {
                    Text("Free for one team. Scoreline Pro unlocks alerts for every team.")
                }
            }
        }
    }

    private func setTeamAlerts(_ enabled: Bool) {
        guard let id = alertableTeamID else { return }
        let storage = viewModel.appStorage
        var ids = storage.teamAlertTeamIDs
        if enabled {
            let decision = NotificationGate.teamAlertDecision(
                isPro: subscriptionManager.isPro,
                enabledTeamCount: ids.count,
                teamAlreadyEnabled: ids.contains(id)
            )
            guard decision.isAllowed else {
                if let feature = decision.blockedFeature {
                    MonetizationTelemetry.gateHit(feature)
                }
                // Flip the switch back: the binding's getter is unchanged, so without a
                // state change the UISwitch would stay showing "on".
                teamAlertsOn = true
                DispatchQueue.main.async { teamAlertsOn = false }
                // An explicit tap always gets an answer, so this skips UpsellCoordinator's
                // throttle (which is for prompts the user didn't ask for).
                proAlertIsForTeamAlerts = true
                shouldShowSportsCalProAlert = true
                return
            }
            NotificationManager.requestNotificationAccessIfNeeded()
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        storage.teamAlertTeamIDs = ids
        teamAlertsOn = enabled
        TeamAlertScheduler.reconcile(
            games: viewModel.totalGames ?? [],
            teamIDs: ids,
            isPro: subscriptionManager.isPro
        )
    }

    // MARK: - Roster & info

    private var hasProfileInfo: Bool {
        guard let p = detail?.profile else { return false }
        return [p.formedYear, p.stadium, p.stadiumLocation, p.stadiumCapacity, p.descriptionText]
            .contains { ($0?.isEmpty == false) }
    }

    @ViewBuilder
    private func rosterAndInfoSections(record: String?) -> some View {
        if record != nil || hasProfileInfo {
            Section("Info") {
                // Record comes from local ESPN game data — shows immediately, even
                // before the server profile (stadium/founded/…) resolves.
                if let record { infoRow("Record", record) }
                if let profile = detail?.profile {
                    if let founded = profile.formedYear, !founded.isEmpty { infoRow("Founded", founded) }
                    if let stadium = profile.stadium, !stadium.isEmpty { infoRow("Stadium", stadium) }
                    if let location = profile.stadiumLocation, !location.isEmpty { infoRow("Location", location) }
                    if let capacity = profile.stadiumCapacity, !capacity.isEmpty { infoRow("Capacity", capacity) }
                    if let desc = profile.descriptionText, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                    }
                }
            }
        }

        if let players = detail?.players, !players.isEmpty {
            Section("Roster") {
                ForEach(players) { PlayerRow(player: $0) }
            }
        } else {
            Section("Roster & Stats") {
                if !didLoadDetail {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                } else {
                    Label("Not available for this team", systemImage: "person.3")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    // MARK: - Load

    private func loadDetail() async {
        guard !didLoadDetail, let id = team.idTeam, !id.isEmpty else { return }
        let loaded = try? await NetworkHandler.getTeamDetail(teamID: id)
        detail = loaded
        didLoadDetail = true
    }

    private func loadStandings(league: Leagues?) async {
        guard let league, league != standingsLeague || standing == nil else { return }
        standingsLeague = league
        didLoadStandings = false
        let loaded = try? await NetworkHandler.getStandings(for: String(league.rawValue))
        guard !Task.isCancelled, standingsLeague == league else { return }
        standing = loaded
        didLoadStandings = true
    }

    // MARK: - Actions

    private func toggleFavorite() {
        if favorites.contains(team: team) {
            favorites.remove(team: team)
        } else {
            favorites.add(team: team)
        }
    }

    #if os(iOS)
    private func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        let separator = (game.playoff?.isNeutralSite == true) ? " vs " : " @ "
        event.title = "\(game.strAwayTeam)\(separator)\(game.strHomeTeam)"
        if let gameDate = game.standardDate {
            event.startDate = gameDate
            event.endDate = gameDate.afterHoursFromNow(hours: 2)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif

    // MARK: - Badge

    @ViewBuilder
    private func badge(_ urlString: String?, size: CGFloat) -> some View {
        TeamBadgeImage(urlString: urlString, size: size, placeholderText: size > 60 ? team.shortCode : nil)
    }
}

// MARK: - Schedule

/// A team's games split for display, derived in a single pass over the loaded games.
private struct TeamSchedule {
    var live: [Game] = []
    var upcoming: [Game] = []
    /// Newest first.
    var results: [Game] = []
    var sport: SportType?
    /// Current season record, e.g. "12-5".
    var record: String?
    /// Last five results, oldest first — the form guide.
    var form: [FormStrip.Result] = []
    /// The competition this team plays most in — the table its standings come from.
    var primaryLeague: Leagues?

    var isEmpty: Bool { live.isEmpty && upcoming.isEmpty && results.isEmpty }

    init(team: Team, games: [Game], liveEvents: [Game]) {
        let liveIDs = Set(liveEvents.map(\.id))
        // The live feed's copy carries the current score; the schedule's may not.
        live = liveEvents.filter { Self.plays(team, in: $0) }
        var leagueCounts: [String: Int] = [:]

        for game in games where Self.plays(team, in: game) {
            if let league = game.idLeague { leagueCounts[league, default: 0] += 1 }
            switch game.scheduleState(liveIDs: liveIDs) {
            case .live:
                if !liveIDs.contains(game.id) { live.append(game) }
            case .upcoming:
                upcoming.append(game)
            case .final:
                results.append(game)
            }
        }

        live.sort { ($0.standardDate ?? .distantPast) < ($1.standardDate ?? .distantPast) }
        upcoming.sort { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
        results.sort { ($0.standardDate ?? .distantPast) > ($1.standardDate ?? .distantPast) }

        sport = (live + upcoming + results).lazy.compactMap(\.sportType).first
        primaryLeague = leagueCounts.max { $0.value < $1.value }
            .flatMap { Int($0.key) }
            .flatMap(Leagues.init(rawValue:))

        // The next game carries the up-to-date record; fall back to the latest result.
        for game in live + upcoming + results {
            let isHome = Self.isHome(team, in: game, home: nil)
            if let r = isHome ? game.homeRecord : game.awayRecord, !r.isEmpty {
                record = r
                break
            }
        }

        form = results.prefix(5).reversed().compactMap { game in
            FormStrip.Result(game: game, isHome: Self.isHome(team, in: game, home: nil))
        }
    }

    /// Matched by stable TheSportsDB id first, falling back to name/alternate name for
    /// records missing ids.
    static func plays(_ team: Team, in game: Game) -> Bool {
        if let id = team.idTeam, !id.isEmpty,
           game.idHomeTeam == id || game.idAwayTeam == id {
            return true
        }
        return game.strHomeTeam == team.strTeam || game.strAwayTeam == team.strTeam
            || (team.strAlternate.map { game.strHomeTeam == $0 || game.strAwayTeam == $0 } ?? false)
    }

    static func isHome(_ team: Team, in game: Game, home: Team?) -> Bool {
        if let id = team.idTeam, !id.isEmpty {
            if game.idHomeTeam == id || home?.idTeam == id { return true }
            if game.idAwayTeam == id { return false }
        }
        return game.strHomeTeam == team.strTeam || game.strHomeTeam == team.strAlternate
    }
}

// MARK: - Form strip

/// The last few results as coloured W / D / L chips, oldest on the left.
private struct FormStrip: View {
    enum Result {
        case win, draw, loss

        /// Nil when the game has no usable score.
        init?(game: Game, isHome: Bool) {
            guard let home = game.intHomeScore.flatMap({ Int($0) }),
                  let away = game.intAwayScore.flatMap({ Int($0) }) else { return nil }
            let ours = isHome ? home : away
            let theirs = isHome ? away : home
            self = ours > theirs ? .win : (ours < theirs ? .loss : .draw)
        }

        var letter: String {
            switch self {
            case .win: return "W"
            case .draw: return "D"
            case .loss: return "L"
            }
        }

        var color: Color {
            switch self {
            case .win: return .green
            case .draw: return .gray
            case .loss: return .red
            }
        }
    }

    let results: [Result]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                Text(result.letter)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(result.color.gradient, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recent form: \(results.map(\.letter).joined(separator: " "))")
    }
}

/// A single schedule line: opponent badge + name (tappable → their team page), the
/// @/vs indicator, and either this team's result and score or the start time.
private struct TeamScheduleRow: View {
    let game: Game
    let isHome: Bool
    let opponent: Team
    var onOpponentTap: () -> Void

    private var homeScore: Int? { game.intHomeScore.flatMap { Int($0) } }
    private var awayScore: Int? { game.intAwayScore.flatMap { Int($0) } }

    /// This team's score first, so "W 102–98" always reads as a win.
    private var scoreLine: (result: FormStrip.Result, text: String)? {
        guard let h = homeScore, let a = awayScore,
              let result = FormStrip.Result(game: game, isHome: isHome) else { return nil }
        let ours = isHome ? h : a
        let theirs = isHome ? a : h
        return (result, "\(ours)–\(theirs)")
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpponentTap) {
                HStack(spacing: 10) {
                    TeamBadgeImage(urlString: opponent.strTeamBadge, size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(isHome ? "vs" : "@") \(opponent.strTeam ?? (isHome ? game.strAwayTeam : game.strHomeTeam))")
                            .font(.subheadline)
                            .lineLimit(1)
                        if let date = game.standardDate {
                            Text(date.formatted(.dateTime.month().day().year()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .accessibilityHint("Opens \(opponent.strTeam ?? "the opponent")'s team page")

            Spacer(minLength: 4)

            if let score = scoreLine {
                HStack(spacing: 6) {
                    Text(score.result.letter)
                        .font(.caption.bold())
                        .foregroundStyle(score.result.color)
                    Text(score.text)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else if let date = game.standardDate {
                GameTimeLabel(date: date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// Team badge with a grey placeholder (optionally showing the team's short code).
private struct TeamBadgeImage: View {
    let urlString: String?
    let size: CGFloat
    var placeholderText: String?

    var body: some View {
        if let urlString, let url = Self.badgeURL(urlString) {
            LazyImage(request: ImageRequest(url: url, processors: [.resize(size: CGSize(width: size, height: size))])) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.2))
            if let placeholderText {
                Text(placeholderText)
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private static func badgeURL(_ urlString: String) -> URL? {
        if urlString.contains("thesportsdb.com") {
            return URL(string: urlString + "/preview")
        }
        return URL(string: urlString)
    }
}

/// A single roster member: headshot, name, position, and jersey number.
private struct PlayerRow: View {
    let player: TeamPlayer

    var body: some View {
        HStack(spacing: 12) {
            headshot
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if let position = player.position, !position.isEmpty {
                    Text(position)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if let number = player.number, !number.isEmpty {
                Text("#\(number)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var headshot: some View {
        if let urlString = player.headshotURL, let url = URL(string: urlString) {
            LazyImage(request: ImageRequest(url: url, processors: [.resize(size: CGSize(width: 36, height: 36))])) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Circle().fill(Color.gray.opacity(0.15))
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 36, height: 36)
                .foregroundStyle(.tertiary)
        }
    }
}
