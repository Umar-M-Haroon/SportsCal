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
struct PickSportPage: View {
    @State var subscriptionPresented: Bool = false
    @State private var teamsPresented = false
    @Environment(UserDefaultStorage.self) private var appStorage
    @Binding var sheetType: SheetType?
    @Environment(GameViewModel.self) private var viewModel
    var body: some View {
        @Bindable var bindableAppStorage = appStorage
        
        List {
            if WorldCupSeason.isActive {
                Section {
                    Toggle(isOn: $bindableAppStorage.shouldShowWorldCup) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("FIFA World Cup 2026")
                                Text("Jun 11 – Jul 19 · follow every match")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "soccerball")
                                .modifier(SportsTint(sport: .soccer))
                        }
                    }
                } header: {
                    Text("Featured")
                } footer: {
                    Text("Turn this on to follow the World Cup without enabling all of soccer.")
                }
            }

            Section {
                Toggle(isOn: $bindableAppStorage.shouldShowNHL) {
                    Label {
                        Text("NHL")
                    } icon: {
                        Image(systemName: "hockey.puck.fill")
                            .modifier(SportsTint(sport: .hockey))
                    }
                }
                .onTapGesture {
//                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                        //                            appStorage.switchTo(sportType: .hockey)
//                        appStorage.shouldShowNFL = false
//                        appStorage.shouldShowNBA = false
//                        appStorage.shouldShowNHL.toggle()
//                        appStorage.shouldShowSoccer = false
//                        appStorage.shouldShowMLB = false
//                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowNFL) {
                    Label {
                        Text("NFL")
                    } icon: {
                        Image(systemName: "football.fill")
                            .modifier(SportsTint(sport: .nfl))
                    }
                }
                .onTapGesture {
//                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
//                        appStorage.shouldShowNFL.toggle()
//                        appStorage.shouldShowNBA = false
//                        appStorage.shouldShowNHL = false
//                        appStorage.shouldShowSoccer = false
//                        appStorage.shouldShowMLB = false
//                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowCFB) {
                    Label {
                        Text("College Football")
                    } icon: {
                        Image(systemName: "football.fill")
                            .modifier(SportsTint(sport: .nfl))
                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowNBA) {
                    Label {
                        Text("NBA")
                    } icon: {
                        Image(systemName: "basketball.fill")
                            .modifier(SportsTint(sport: .basketball))
                    }
                }
                .onTapGesture {
//                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
//                        appStorage.shouldShowNFL = false
//                        appStorage.shouldShowNBA.toggle()
//                        appStorage.shouldShowNHL = false
//                        appStorage.shouldShowSoccer = false
//                        appStorage.shouldShowMLB = false
//                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowWNBA) {
                    Label {
                        Text("WNBA")
                    } icon: {
                        Image(systemName: "basketball.fill")
                            .modifier(SportsTint(sport: .basketball))
                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowMLB) {
                    Label {
                      Text("MLB")
                    } icon: {
                        Image(systemName: "baseball.fill")
                            .modifier(SportsTint(sport: .mlb))
                    }
                }
                .onTapGesture {
//                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
//                        appStorage.shouldShowNFL = false
//                        appStorage.shouldShowNBA = false
//                        appStorage.shouldShowNHL = false
//                        appStorage.shouldShowSoccer = false
//                        appStorage.shouldShowMLB.toggle()
//                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowSoccer) {
                    Label {
                        Text("Soccer")
                    } icon: {
                        Image(systemName: "soccerball")
                            .modifier(SportsTint(sport: .soccer))
                    }
                }
                .onTapGesture {
//                    if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
//                        appStorage.shouldShowNFL = false
//                        appStorage.shouldShowNBA = false
//                        appStorage.shouldShowNHL = false
//                        appStorage.shouldShowSoccer.toggle()
//                        appStorage.shouldShowMLB = false
//                    }
                }
                
                Toggle(isOn: $bindableAppStorage.shouldShowGolf) {
                    Label {
                        Text("Golf")
                    } icon: {
                        Image(systemName: "figure.golf")
                            .modifier(SportsTint(sport: .golf))
                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowTennis) {
                    Label {
                        Text("Tennis")
                    } icon: {
                        Image(systemName: "tennis.racket")
                            .modifier(SportsTint(sport: .tennis))
                    }
                }
                Toggle(isOn: $bindableAppStorage.shouldShowRacing) {
                    Label {
                        Text("Racing")
                    } icon: {
                        Image(systemName: "flag.checkered.2.crossed")
                            .modifier(SportsTint(sport: .racing))
                    }
                }
                if appStorage.shouldShowSoccer {
                    NavigationLink("Show Soccer Leagues") {
                        CompetitionPage(competitions: Leagues.allCases.filter({$0.isSoccer}))
                            .environment(appStorage)
                    }
                }
            } header: {
                HStack {
                    Spacer()
                    Text("Try Scoreline Pro for multiple sports")
                    Spacer()
                }
            }
            
            Section {
                MiniSubscriptionPage(subscriptionPresented: $subscriptionPresented)
            } footer: {
                Button(action: {
                    appStorage.recomputeEnabledSports()
                    viewModel.getInfo()
                    teamsPresented = true
                }, label: {
                    Text("Continue")
                        .disabled(!(appStorage.shouldShowSoccer || appStorage.shouldShowWorldCup || appStorage.shouldShowMLB || appStorage.shouldShowNBA || appStorage.shouldShowWNBA || appStorage.shouldShowNFL || appStorage.shouldShowCFB || appStorage.shouldShowNHL || appStorage.shouldShowGolf || appStorage.shouldShowTennis || appStorage.shouldShowRacing))
                })
                .frame(maxWidth: .infinity,alignment: .center)
                .buttonStyle(.bordered)
            }
            .sheet(isPresented: $subscriptionPresented) {
                SubscriptionSheet(subscriptionPresented: $subscriptionPresented)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("Pick Sports")
        .navigationDestination(isPresented: $teamsPresented) {
            PickTeamsPage(sheetType: $sheetType)
        }
    }

    /// Contextual notification opt-in, asked after the user has picked sports.
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
    static func build(games: [Game], enabled: [SportType],
                      teams: (Game) -> (home: Team, away: Team)?) -> [OnboardingTeamSection] {
        var byLeague: [String: (title: String, sport: SportType, teams: [String: Team])] = [:]
        for game in games where !game.isIndividualSport {
            guard let sport = game.sportType, enabled.contains(sport),
                  let leagueID = game.idLeague, let pair = teams(game) else { continue }
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
                return l != r ? l < r : lhs.title < rhs.title
            }
    }
}

/// Second onboarding step: follow a few teams so the first feed, reminders and
/// widgets are personal from day one. Following a team is the habit that keeps
/// people, so this comes before the notification ask, which then has a reason.
struct PickTeamsPage: View {
    @Binding var sheetType: SheetType?
    @Environment(UserDefaultStorage.self) private var appStorage
    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @State private var search = ""
    @State private var picked: Set<String> = []
    /// Built once per schedule/teams/sports change, not on every body pass: each
    /// keystroke and star toggle used to re-group the whole schedule.
    @State private var sections: [OnboardingTeamSection] = []

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
        .navigationTitle("Your Teams")
        .task(id: sectionsKey) {
            sections = OnboardingTeamSection.build(games: viewModel.totalGames ?? [],
                                                   enabled: appStorage.enabledSports,
                                                   teams: viewModel.getTeams(for:))
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                finish()
            } label: {
                Text(picked.isEmpty ? "Skip for Now" : "Done · \(picked.count) \(picked.count == 1 ? "Team" : "Teams")")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(6)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
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
            }
        } label: {
            HStack(spacing: 12) {
                badge(team, sport: sport)
                Text(team.strTeam ?? "")
                    .foregroundStyle(.primary)
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
        appStorage.shouldShowOnboarding = false
        appStorage.recomputeEnabledSports()
        MonetizationTelemetry.onboardingCompleted(sportCount: appStorage.enabledSports.count)
        viewModel.filterSports(force: true)
        requestNotifications()
        let offered = UpsellCoordinator.shared.request(.postOnboarding) {
            sheetType = .paywall
        }
        if !offered { sheetType = .none }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted { MonetizationTelemetry.activationNotificationsEnabled() }
            MonetizationTelemetry.notificationsResolved(granted: granted)
        }
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
