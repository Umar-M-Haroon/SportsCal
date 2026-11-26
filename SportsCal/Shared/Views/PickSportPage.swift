//
//  PickSportPage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/19/22.
//

import SwiftUI
import SportsCalModel
import UserNotifications
import NukeUI
/// One pickable sport or league in onboarding.
struct OnboardingSportChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let sport: SportType
    let keyPath: ReferenceWritableKeyPath<UserDefaultStorage, Bool>

    static let all: [OnboardingSportChoice] = [
        .init(id: "nfl", title: "NFL", systemImage: "football.fill", sport: .nfl, keyPath: \.shouldShowNFL),
        .init(id: "cfb", title: "College Football", systemImage: "football.fill", sport: .nfl, keyPath: \.shouldShowCFB),
        .init(id: "nba", title: "NBA", systemImage: "basketball.fill", sport: .basketball, keyPath: \.shouldShowNBA),
        .init(id: "wnba", title: "WNBA", systemImage: "basketball.fill", sport: .basketball, keyPath: \.shouldShowWNBA),
        .init(id: "cbb", title: "College Basketball", systemImage: "basketball.fill", sport: .basketball, keyPath: \.shouldShowCBB),
        .init(id: "mlb", title: "MLB", systemImage: "baseball.fill", sport: .mlb, keyPath: \.shouldShowMLB),
        .init(id: "nhl", title: "NHL", systemImage: "hockey.puck.fill", sport: .hockey, keyPath: \.shouldShowNHL),
        .init(id: "soccer", title: "Soccer", systemImage: "soccerball", sport: .soccer, keyPath: \.shouldShowSoccer),
        .init(id: "cricket", title: "Cricket", systemImage: "cricket.ball", sport: .cricket, keyPath: \.shouldShowCricket),
        .init(id: "golf", title: "Golf", systemImage: "figure.golf", sport: .golf, keyPath: \.shouldShowGolf),
        .init(id: "tennis", title: "Tennis", systemImage: "tennis.racket", sport: .tennis, keyPath: \.shouldShowTennis),
        .init(id: "racing", title: "Racing", systemImage: "flag.checkered.2.crossed", sport: .racing, keyPath: \.shouldShowRacing),
    ]

    /// A sensible first pick for where the phone is set up, so the grid never starts
    /// empty. Pure so it can be tested.
    static func suggested(forRegion region: String?) -> [String] {
        switch region?.uppercased() {
        case "US": return ["nfl", "nba"]
        case "CA": return ["nhl", "nba"]
        case "IN", "PK", "LK", "BD", "AF": return ["cricket"]
        case "AU", "NZ", "ZA": return ["cricket", "soccer"]
        default: return ["soccer"]
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Onboarding step 1: pick sports from a grid of tiles.
struct PickSportPage: View {
    @State private var teamsPresented = false
    @Environment(UserDefaultStorage.self) private var appStorage
    @Binding var sheetType: SheetType?
    @Environment(GameViewModel.self) private var viewModel
    /// Local mirror of the toggles: the storage flags are `@ObservationIgnored`
    /// `@AppStorage`, so writing them alone doesn't redraw the tiles.
    @State private var selected: Set<String> = []
    @State private var worldCup = false
    @State private var didSeed = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pick as many as you like. You can change them any time in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if WorldCupSeason.isActive {
                    tile(title: "World Cup 2026", systemImage: "soccerball", sport: .soccer, isOn: worldCup) {
                        worldCup.toggle()
                        appStorage.shouldShowWorldCup = worldCup
                    }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(OnboardingSportChoice.all) { choice in
                        tile(title: choice.title, systemImage: choice.systemImage, sport: choice.sport,
                             isOn: selected.contains(choice.id)) {
                            toggle(choice)
                        }
                    }
                }

                if selected.contains("soccer") {
                    NavigationLink {
                        CompetitionPage(competitions: Leagues.allCases.filter({ $0.isSoccer }))
                            .environment(appStorage)
                    } label: {
                        Label("Choose soccer leagues", systemImage: "list.bullet")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                appStorage.recomputeEnabledSports()
                viewModel.getInfo()
                teamsPresented = true
            } label: {
                Text(selected.isEmpty && !worldCup ? "Pick a Sport" : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty && !worldCup)
            .padding()
            .background(.bar)
        }
        .navigationTitle("Your Sports")
        .navigationDestination(isPresented: $teamsPresented) {
            PickTeamsPage(sheetType: $sheetType)
        }
        .onAppear(perform: seed)
    }

    /// Reads the current toggles; on a fresh install (nothing on) pre-picks the
    /// region's usual sports so the grid starts useful rather than empty.
    private func seed() {
        guard !didSeed else { return }
        didSeed = true
        selected = Set(OnboardingSportChoice.all.filter { appStorage[keyPath: $0.keyPath] }.map(\.id))
        worldCup = appStorage.shouldShowWorldCup
        if selected.isEmpty && !worldCup {
            for id in OnboardingSportChoice.suggested(forRegion: Locale.current.region?.identifier) {
                if let choice = OnboardingSportChoice.all.first(where: { $0.id == id }) { toggle(choice) }
            }
        }
    }

    private func toggle(_ choice: OnboardingSportChoice) {
        let on = !selected.contains(choice.id)
        if on { selected.insert(choice.id) } else { selected.remove(choice.id) }
        appStorage[keyPath: choice.keyPath] = on
    }

    private func tile(title: String, systemImage: String, sport: SportType, isOn: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(isOn ? Color.white : Color.app(sport))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(isOn ? Color.app(sport) : Color.app(sport).opacity(0.15)))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 104)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(isOn ? 0.16 : 0.07)))
            .overlay(alignment: .topTrailing) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.app(sport) : Color.secondary.opacity(0.5))
                    .padding(8)
            }
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isOn ? Color.app(sport) : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Pick teams (onboarding step 2)

/// One league's worth of pickable teams.
struct OnboardingTeamSection: Identifiable, Equatable {
    let id: String
    let title: String
    let sport: SportType
    let teams: [Team]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.teams.map(\.idTeam) == rhs.teams.map(\.idTeam)
    }

    /// Teams that appear in the schedule for the user's enabled sports, grouped by
    /// league in the order the sports were enabled. Individual sports (golf, tennis,
    /// racing) have no teams to follow and are skipped. Pure so it can be tested.
    /// `leagueAllowed` narrows a sport to the leagues actually picked: the NBA, WNBA and
    /// college basketball share `.basketball` and the NFL and college share `.nfl`, so a
    /// sport-level check alone listed NFL teams to someone who only picked College
    /// Football, and college basketball teams to someone who only picked the NBA.
    static func build(games: [Game], enabled: [SportType],
                      leagueAllowed: (String) -> Bool = { _ in true },
                      teams: (Game) -> (home: Team, away: Team)?) -> [OnboardingTeamSection] {
        var byLeague: [String: (title: String, sport: SportType, teams: [String: Team])] = [:]
        for game in games where !game.isIndividualSport {
            guard let sport = game.sportType, enabled.contains(sport),
                  let leagueID = game.idLeague, leagueAllowed(leagueID),
                  let pair = teams(game) else { continue }
            let title = Int(leagueID).flatMap(Leagues.init(rawValue:))?.leagueName ?? game.strLeague ?? sport.displayName
            var entry = byLeague[leagueID] ?? (title, sport, [:])
            for team in [pair.home, pair.away] {
                guard let name = team.strTeam, !name.isEmpty else { continue }
                entry.teams[team.idTeam ?? name] = entry.teams[team.idTeam ?? name] ?? team
            }
            byLeague[leagueID] = entry
        }
        return byLeague
            .map { id, entry in
                OnboardingTeamSection(
                    id: id, title: entry.title, sport: entry.sport,
                    teams: entry.teams.values.sorted { ($0.strTeam ?? "") < ($1.strTeam ?? "") }
                )
            }
            .sorted { lhs, rhs in
                let l = enabled.firstIndex(of: lhs.sport) ?? .max, r = enabled.firstIndex(of: rhs.sport) ?? .max
                if l != r { return l < r }
                // The pro league leads its sport: someone who picked the NBA should see
                // NBA teams first, not "College Basketball" because it sorts earlier.
                let lCollege = isCollege(lhs.id), rCollege = isCollege(rhs.id)
                if lCollege != rCollege { return !lCollege }
                return lhs.title < rhs.title
            }
    }

    private static func isCollege(_ leagueID: String) -> Bool {
        leagueID == String(Leagues.ncaaf.rawValue) || leagueID == String(Leagues.ncaaMBBTournament.rawValue)
    }
}

/// Second onboarding step: follow a few teams so the first feed, reminders and
/// widgets are personal from day one. Following a team is the habit that keeps
/// people, so this comes before the notification ask, which then has a reason.
struct PickTeamsPage: View {
    @Binding var sheetType: SheetType?
    /// Outside onboarding: narrow the list to one sport or league, and call this from
    /// the bottom button instead of moving on to the notification step.
    var onlySport: SportType? = nil
    var onlyLeague: Leagues? = nil
    var onDone: (() -> Void)? = nil
    @Environment(UserDefaultStorage.self) private var appStorage
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @State private var search = ""
    @State private var picked: Set<String> = []

    /// Teams starred on the map are favorites already, so they count as a pick too.
    private var finishTitle: String {
        if onDone != nil { return "Done" }
        if !picked.isEmpty { return "Done · \(picked.count) \(picked.count == 1 ? "Team" : "Teams")" }
        return favorites.teams.isEmpty ? "Skip for Now" : "Continue"
    }
    /// Built once per schedule/teams/sports change, not on every body pass: each
    /// keystroke and star toggle used to re-group the whole schedule.
    @State private var sections: [OnboardingTeamSection] = []
    /// Teams already starred when the list first filled (on the map, or earlier), pinned
    /// on top so they're easy to check. Captured once: starring here doesn't move rows.
    @State private var starredAtStart: [(team: Team, sport: SportType)]?
    @State private var primerPresented = false
    /// Every competition each team plays in, so starring a team follows its leagues and
    /// cups too. Nil until loaded, or on a server without the route (stars then only
    /// follow the team, as before).
    @State private var competitions: TeamCompetitionIndex?

    /// What `sections` depends on. Live ticks patch scores in place and leave it alone.
    private struct SectionsKey: Hashable {
        let games: Int
        let teams: Int
        let enabled: [SportType]
    }

    private var sectionsKey: SectionsKey {
        SectionsKey(games: viewModel.totalGames?.count ?? 0, teams: viewModel.teams.count,
                    enabled: appStorage.enabledSports)
    }

    /// Still waiting on the schedule, as opposed to a schedule with no team games in it.
    private var isLoadingSchedule: Bool {
        guard let games = viewModel.totalGames, !games.isEmpty else { return true }
        return viewModel.isFetching && sections.isEmpty
    }

    private func filtered(_ section: OnboardingTeamSection) -> [Team] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return section.teams }
        return section.teams.filter {
            ($0.strTeam ?? "").localizedCaseInsensitiveContains(query)
                || ($0.strTeamShort ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            if sections.isEmpty {
                Section {
                    if isLoadingSchedule {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Loading teams…").foregroundStyle(.secondary)
                        }
                    } else {
                        // Only golf/tennis/racing picked, or nothing scheduled yet: not loading.
                        Text("No teams to pick for these sports right now. You can follow teams any time from Browse.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Golf, tennis and racing don't have teams. You can follow players and drivers from any event.")
                }
            }
            if let starred = starredAtStart, !starred.isEmpty, search.trimmingCharacters(in: .whitespaces).isEmpty {
                Section("Starred") {
                    ForEach(starred, id: \.team) { entry in
                        row(entry.team, sport: entry.sport)
                    }
                }
            }
            ForEach(sections) { section in
                let teams = filtered(section)
                if !teams.isEmpty {
                    Section(section.title) {
                        ForEach(teams, id: \.self) { team in
                            row(team, sport: section.sport)
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search teams")
        .navigationTitle(onlyLeague?.leagueName ?? onlySport.map { "\($0.displayName) Teams" } ?? "Your Teams")
        .navigationDestination(isPresented: $primerPresented) {
            NotificationPrimerPage(sheetType: $sheetType)
        }
        .task {
            if competitions == nil { competitions = await NetworkHandler.getTeamCompetitions() }
        }
        .task(id: sectionsKey) {
            sections = OnboardingTeamSection.build(games: viewModel.totalGames ?? [],
                                                   enabled: onlySport.map { [$0] } ?? appStorage.enabledSports,
                                                   leagueAllowed: leagueAllowed,
                                                   teams: viewModel.getTeams(for:))
                .filter { onlyLeague == nil || $0.id == String(onlyLeague!.rawValue) }
            if starredAtStart == nil, !sections.isEmpty {
                var seen: Set<String> = []
                starredAtStart = sections.flatMap { section in
                    section.teams.filter { favorites.contains(team: $0) }.map { (team: $0, sport: section.sport) }
                }
                .filter { seen.insert($0.team.idTeam ?? $0.team.strTeam ?? "").inserted }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                finish()
            } label: {
                Text(finishTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(6)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
    }

    /// Only leagues the user switched on: their own toggle for WNBA / college
    /// football / college basketball, the soccer gate (all of soccer, or the World Cup alone) minus
    /// hidden competitions, and the sport toggle for everything else.
    private func leagueAllowed(_ leagueID: String) -> Bool {
        guard let league = Int(leagueID).flatMap(Leagues.init(rawValue:)) else { return true }
        if let onlyLeague { return league == onlyLeague }
        if appStorage.hiddenCompetitions.contains(league.leagueName) { return false }
        if league.isSoccer { return viewModel.soccerGamePassesEnableGate(league) }
        switch league {
        case .wnba: return appStorage.shouldShowWNBA
        case .nba: return appStorage.shouldShowNBA
        case .ncaaf: return appStorage.shouldShowCFB
        case .ncaaMBBTournament: return appStorage.shouldShowCBB
        case .nfl: return appStorage.shouldShowNFL
        default: return true
        }
    }

    private func row(_ team: Team, sport: SportType) -> some View {
        let key = team.idTeam ?? team.strTeam ?? ""
        let isPicked = picked.contains(key) || favorites.contains(team: team)
        return Button {
            if isPicked {
                favorites.remove(team: team)
                picked.remove(key)
            } else {
                favorites.add(team: team)
                picked.insert(key)
                // Unstarring leaves the competitions on: other picks may share them.
                if appStorage.followCompetitions(teamCompetitions(team)) {
                    viewModel.filterSports(force: true)
                }
            }
        } label: {
            HStack(spacing: 12) {
                badge(team, sport: sport)
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.strTeam ?? "")
                        .foregroundStyle(.primary)
                    // Only worth saying when starring adds more than the team's own league.
                    let leagues = teamCompetitions(team)
                    if leagues.count > 1 {
                        Text(leagues.map(\.competitionShortName).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: isPicked ? "star.fill" : "star")
                    .foregroundStyle(isPicked ? Color.yellow : Color.secondary)
                    .imageScale(.large)
            }
        }
        .accessibilityLabel(team.strTeam ?? "")
        .accessibilityValue(isPicked ? "Following" : "Not following")
        .accessibilityHint(isPicked ? "Unfollow this team" : "Follow this team")
    }

    private func teamCompetitions(_ team: Team) -> [Leagues] {
        guard let id = team.idTeam, let competitions else { return [] }
        return competitions.leagues(forTeam: id)
    }

    @ViewBuilder
    private func badge(_ team: Team, sport: SportType) -> some View {
        if let string = team.strTeamBadge, let url = URL(string: string) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Circle().fill(Color.secondary.opacity(0.15))
                }
            }
            .frame(width: 32, height: 32)
        } else {
            TeamLogo(abbreviation: String((team.strTeamShort ?? team.strTeam ?? "?").prefix(3)), sport: sport, size: 32)
        }
    }

    private func finish() {
        if let onDone { return onDone() }
        primerPresented = true
    }
}

/// The team picker on its own, for following teams in one sport or league — the fix
/// when "only my teams" leaves it empty.
struct FollowTeamsSheet: View {
    let sport: SportType
    var league: Leagues? = nil
    @Environment(GameViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if FavoriteReach.hasTeams(sport) {
                    PickTeamsPage(sheetType: .constant(nil), onlySport: sport, onlyLeague: league) {
                        viewModel.filterSports(force: true)
                        dismiss()
                    }
                } else {
                    PickPlayersPage(sport: sport, league: league) {
                        viewModel.filterSports(force: true)
                        dismiss()
                    }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 520, idealHeight: 620)
        #endif
    }
}

/// Last onboarding step: say what notifications are for before iOS asks. A cold
/// system prompt is easy to refuse, and it can only be shown once.
struct NotificationPrimerPage: View {
    @Binding var sheetType: SheetType?
    @Environment(UserDefaultStorage.self) private var appStorage
    @Environment(GameViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.multicolor)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Never miss a moment")
                    .font(.title.bold())
                Text("Turn on notifications and Scoreline tells you when it matters.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 18) {
                OnboardingFeatureRow(systemImage: "clock.badge", tint: .orange,
                                     title: "Kickoff reminders", detail: "A heads-up before your teams play.")
                OnboardingFeatureRow(systemImage: "sportscourt.fill", tint: .green,
                                     title: "Scores as they happen", detail: "Goals, touchdowns and finals for the teams you follow.")
                OnboardingFeatureRow(systemImage: "iphone.gen3.radiowaves.left.and.right", tint: .blue,
                                     title: "Live on your Lock Screen", detail: "Follow a game with a Live Activity without opening the app.")
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    finish(askForNotifications: true)
                } label: {
                    Text("Turn On Notifications")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(6)
                }
                .buttonStyle(.borderedProminent)
                Button("Not Now") {
                    finish(askForNotifications: false)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(.bar)
        }
    }

    private func finish(askForNotifications: Bool) {
        appStorage.shouldShowOnboarding = false
        appStorage.recomputeEnabledSports()
        MonetizationTelemetry.onboardingCompleted(sportCount: appStorage.enabledSports.count)
        viewModel.filterSports(force: true)
        if askForNotifications {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                if granted {
                    MonetizationTelemetry.activationNotificationsEnabled()
                    NotificationManager.registerForRemoteNotificationsAfterGrant()
                }
                MonetizationTelemetry.notificationsResolved(granted: granted)
            }
        }
        let offered = UpsellCoordinator.shared.request(.postOnboarding) {
            sheetType = .paywall
        }
        if !offered { sheetType = .none }
    }
}

/// An icon, a title and a line of detail: the welcome and notification steps.
struct OnboardingFeatureRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    @Previewable @State var storage = UserDefaultStorage()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())
    
    PickSportPage(sheetType: .constant(.none))
        .environment(storage)
        .environment(viewModel)
        .environment(Favorites())
}


/// Golfers, tennis players and drivers to follow. They're followed by the name event
/// leaderboards show, so the list is every name on the loaded events' leaderboards,
/// most frequent first, with anyone already followed on top.
struct PickPlayersPage: View {
    let sport: SportType
    var league: Leagues? = nil
    var onDone: () -> Void
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @State private var search = ""
    @State private var names: [String] = []
    /// Followed when the list first filled: pinned on top, and not moved by starring.
    @State private var followedAtStart: [String] = []

    private var noun: String { sport == .racing ? "drivers" : "players" }

    var body: some View {
        List {
            let query = search.trimmingCharacters(in: .whitespaces)
            let matching = query.isEmpty ? names : names.filter { $0.localizedCaseInsensitiveContains(query) }
            if names.isEmpty {
                Section {
                    Text("No \(noun) to pick yet. Names come from event leaderboards, so check back once an event is under way.")
                        .foregroundStyle(.secondary)
                }
            }
            if query.isEmpty, !followedAtStart.isEmpty {
                Section("Following") {
                    ForEach(followedAtStart, id: \.self, content: row)
                }
            }
            let rest = matching.filter { query.isEmpty ? !followedAtStart.contains($0) : true }
            if !rest.isEmpty {
                Section(query.isEmpty ? "From recent events" : "Results") {
                    ForEach(rest, id: \.self, content: row)
                }
            }
        }
        .searchable(text: $search, prompt: "Search \(noun)")
        .navigationTitle(league?.leagueName ?? "\(sport.displayName) \(noun.capitalized)")
        .task {
            names = Self.leaderboardNames(viewModel.gamesDict[sport] ?? [], league: league)
            let followed = names.filter { favorites.containsPlayer($0) }
            let extra = favorites.players.filter { !names.contains($0) }.sorted()
            followedAtStart = followed + extra
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onDone) {
                Text("Done").font(.headline).frame(maxWidth: .infinity).padding(6)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
    }

    private func row(_ name: String) -> some View {
        let isFollowed = favorites.containsPlayer(name)
        return Button {
            if isFollowed { favorites.removePlayer(name) } else { favorites.addPlayer(name) }
        } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                Image(systemName: isFollowed ? "star.fill" : "star")
                    .foregroundStyle(isFollowed ? Color.yellow : Color.secondary)
                    .imageScale(.large)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isFollowed ? "Following" : "Not following")
    }

    /// Every leaderboard name in these events, most appearances first. Pure for tests.
    static func leaderboardNames(_ games: [Game], league: Leagues? = nil) -> [String] {
        let leagueID = league.map { String($0.rawValue) }
        var counts: [String: Int] = [:]
        for game in games where leagueID == nil || game.idLeague == leagueID {
            for entry in game.resolvedLeaderboard where !entry.name.isEmpty {
                counts[entry.name, default: 0] += 1
            }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }
}
