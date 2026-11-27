//
//  InjuriesView.swift
//  SportsCal
//
//  The injury report: who's hurt, with what, and roughly how long they're out.
//  NBA, NFL, NHL and MLB, from ESPN via the server's `/injuries`.
//

import SwiftUI
import NukeUI
import SportsCalModel

struct InjuriesView: View {
    /// Opens with this search filled in (Siri / Spotlight hand-off, day page search).
    var initialSearch: String = ""
    /// Defaults to My Teams (All when no team is followed).
    var initialScope: Scope? = nil

    @Environment(Favorites.self) private var favorites
    @State private var store = InjuryStore.shared
    @State private var search = ""
    @State private var scope: Scope = .myTeams
    @State private var didSetScope = false

    enum Scope: Hashable {
        case myTeams, all, league(String)
    }

    private static let leagues = ["nba", "nfl", "nhl", "mlb"]

    private var followsAnyTeam: Bool {
        !favorites.teamIDs.isEmpty || !favorites.legacyTeamNames.isEmpty
    }

    private var visible: [PlayerInjury] {
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { return store.search(query) }
        switch scope {
        case .myTeams: return store.injuries.filter { favorites.contains($0.teamName) }
        case .all: return store.injuries
        case .league(let slug): return store.injuries.filter { $0.league == slug }
        }
    }

    /// Grouped by team; the user's teams first when showing more than one league.
    private var sections: [(team: String, injuries: [PlayerInjury])] {
        Dictionary(grouping: visible, by: \.teamName)
            .map { (team: $0.key, injuries: $0.value.sorted(by: InjuryText.severityOrder)) }
            .sorted { lhs, rhs in
                let l = favorites.contains(lhs.team), r = favorites.contains(rhs.team)
                if l != r { return l }
                return lhs.team < rhs.team
            }
    }

    var body: some View {
        List {
            if search.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    Picker("Show", selection: $scope) {
                        Text("My Teams").tag(Scope.myTeams)
                        Text("All").tag(Scope.all)
                        ForEach(Self.leagues, id: \.self) { slug in
                            Text(InjuryText.leagueName(slug)).tag(Scope.league(slug))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            if store.feed == nil {
                Section {
                    if store.isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading injuries…").foregroundStyle(.secondary)
                        }
                    } else {
                        ContentUnavailableView("Injuries unavailable", systemImage: "cross.case",
                                               description: Text("Check your connection and pull to refresh."))
                    }
                }
            } else if visible.isEmpty {
                Section {
                    emptyState
                }
            } else {
                ForEach(sections, id: \.team) { section in
                    Section {
                        ForEach(section.injuries) { injury in
                            NavigationLink {
                                InjuryDetailView(injury: injury)
                            } label: {
                                InjuryRow(injury: injury)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(section.team)
                            if favorites.contains(section.team) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .imageScale(.small)
                                    .accessibilityLabel("Your team")
                            }
                        }
                    }
                }
            }

            if let updated = store.feed?.updated {
                Section {
                } footer: {
                    Text("From ESPN's injury report, updated \(updated.formatted(.relative(presentation: .named))). Return dates are estimates.")
                }
            }
        }
        .navigationTitle("Injuries")
        .searchable(text: $search, prompt: "Search players")
        .refreshable { await store.refreshIfStale(maxAge: 0) }
        .task {
            if !didSetScope {
                didSetScope = true
                search = initialSearch
                if let initialScope { scope = initialScope } else if !followsAnyTeam { scope = .all }
            }
            await store.refreshIfStale()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            ContentUnavailableView("No injury for “\(query)”", systemImage: "figure.run",
                                   description: Text("They aren't on the NBA, NFL, NHL or MLB injury report."))
        } else if scope == .myTeams {
            ContentUnavailableView(followsAnyTeam ? "Your teams are healthy" : "No teams followed",
                                   systemImage: followsAnyTeam ? "checkmark.seal" : "star",
                                   description: Text(followsAnyTeam
                                                     ? "Nobody on your NBA, NFL, NHL or MLB teams is on the injury report."
                                                     : "Follow teams to see their injuries here, or switch to All."))
        } else {
            ContentUnavailableView("No injuries", systemImage: "checkmark.seal")
        }
    }
}

// MARK: - Row

struct InjuryRow: View {
    let injury: PlayerInjury
    var showsTeam = false

    var body: some View {
        HStack(spacing: 12) {
            InjuryHeadshot(injury: injury, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(injury.playerName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text([injury.position, showsTeam ? injury.teamAbbreviation : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(InjuryText.headline(injury))
                    .font(.subheadline)
                    .lineLimit(1)
                Text(InjuryText.returnLine(injury))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            InjuryStatusPill(injury: injury)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct InjuryStatusPill: View {
    let injury: PlayerInjury

    var body: some View {
        Text(InjuryText.status(injury))
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .fixedSize()
    }

    private var color: Color {
        switch InjuryText.severity(injury) {
        case .out: .red
        case .doubtful: .orange
        case .questionable: .yellow
        case .suspended: .purple
        }
    }
}

struct InjuryHeadshot: View {
    let injury: PlayerInjury
    var size: CGFloat

    var body: some View {
        Group {
            if let string = injury.headshot, let url = URL(string: string) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.45))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Detail

struct InjuryDetailView: View {
    let injury: PlayerInjury

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    InjuryHeadshot(injury: injury, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(injury.playerName)
                            .font(.title3.weight(.bold))
                        Text([injury.position, injury.teamName].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        InjuryStatusPill(injury: injury)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Injury") {
                LabeledContent("What", value: InjuryText.headline(injury))
                LabeledContent("Status", value: InjuryText.status(injury))
                LabeledContent("Back", value: InjuryText.returnLine(injury))
            }

            if injury.summary != nil || injury.details != nil {
                Section("Latest") {
                    if let summary = injury.summary {
                        Text(summary).font(.body.weight(.medium))
                    }
                    if let details = injury.details, details != injury.summary {
                        Text(details).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let updated = injury.updated.flatMap(DateParsers.parse) {
                        Text("Updated \(updated.formatted(.relative(presentation: .named))).")
                    }
                    Text("Return dates are ESPN's estimates and often move.")
                }
            }
        }
        .navigationTitle(injury.playerName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Team page section

/// A team's injuries, for the team page. Nothing when the team has none (or isn't in
/// a league the report covers).
struct TeamInjuriesSection: View {
    let teamName: String?
    @State private var store = InjuryStore.shared

    var body: some View {
        let injuries = store.injuries(forTeam: teamName)
        Group {
            if !injuries.isEmpty {
                Section {
                    ForEach(injuries.prefix(6)) { injury in
                        NavigationLink {
                            InjuryDetailView(injury: injury)
                        } label: {
                            InjuryRow(injury: injury)
                        }
                    }
                    if injuries.count > 6 {
                        NavigationLink("All \(injuries.count) injuries") {
                            List(injuries) { injury in
                                NavigationLink {
                                    InjuryDetailView(injury: injury)
                                } label: {
                                    InjuryRow(injury: injury)
                                }
                            }
                            .navigationTitle("Injuries")
                        }
                    }
                } header: {
                    Text("Injuries")
                }
            }
        }
    }
}

#if DEBUG
extension InjuryFeed {
    /// Entries from ESPN's report on Nov 26 2026.
    static let preview = InjuryFeed(updated: Date().addingTimeInterval(-40 * 60), injuries: [
        PlayerInjury(id: "1", athleteID: "3146557", playerName: "Jock Landale", position: "C",
                     headshot: "https://a.espncdn.com/i/headshots/nba/players/full/3146557.png",
                     league: "nba", teamName: "Atlanta Hawks", teamAbbreviation: "ATL", status: "Out",
                     bodyPart: "Hip", injury: "Inflammation", side: "Right", returnDate: "2026-11-29",
                     summary: "Landale (hip) is out for Friday's game against the Celtics.",
                     details: "Landale won't suit up Friday and this will be his fifth consecutive absence. His next chance to play will come against the Knicks on Sunday.",
                     updated: "2026-11-26T22:44Z"),
        PlayerInjury(id: "2", playerName: "CJ McCollum", position: "G", league: "nba", teamName: "Atlanta Hawks",
                     teamAbbreviation: "ATL", status: "Out", bodyPart: "Calf", injury: "Strain", side: "Left",
                     returnDate: "2026-12-19",
                     summary: "McCollum (calf) will miss at least four weeks, per Brad Rowland of the Locked On Podcast Network.",
                     updated: "2026-11-25T18:10Z"),
        PlayerInjury(id: "3", playerName: "Asa Newell", position: "F", league: "nba", teamName: "Atlanta Hawks",
                     teamAbbreviation: "ATL", status: "Out", bodyPart: "Toe", side: "Left", returnDate: "2027-03-17",
                     summary: "Newell underwent surgery Tuesday for a plantar plate tear in his left great toe.",
                     updated: "2026-11-24T20:00Z"),
        PlayerInjury(id: "4", playerName: "Carson Beck", position: "QB", league: "nfl", teamName: "Arizona Cardinals",
                     teamAbbreviation: "ARI", status: "Questionable", bodyPart: "Back", injury: "Spasms",
                     returnDate: "2026-11-29",
                     summary: "Beck (back) was listed as a non-participant on Thursday's injury report.",
                     updated: "2026-11-26T21:00Z"),
        PlayerInjury(id: "5", playerName: "Leo Carlsson", position: "C", league: "nhl", teamName: "Anaheim Ducks",
                     teamAbbreviation: "ANA", status: "Day-To-Day", bodyPart: "Upper Body", returnDate: "2026-11-27",
                     updated: "2026-11-26T16:00Z"),
        PlayerInjury(id: "6", playerName: "Ryan Poehling", position: "C", league: "nhl", teamName: "Anaheim Ducks",
                     teamAbbreviation: "ANA", status: "Injured Reserve", bodyPart: "Knee", returnDate: "2026-11-27",
                     summary: "Poehling (knee) is expected back in the short term.", updated: "2026-11-26T15:00Z"),
    ])
}

#Preview("Injuries") {
    NavigationStack {
        InjuriesView(initialScope: .all)
    }
    .environment(Favorites())
    .onAppear { InjuryStore.shared.usePreviewFeed(.preview) }
}

#Preview("Injury detail") {
    NavigationStack {
        InjuryDetailView(injury: InjuryFeed.preview.injuries[1])
    }
}
#endif
