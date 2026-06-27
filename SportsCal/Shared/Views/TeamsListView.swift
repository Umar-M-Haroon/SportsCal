//
//  TeamsListView.swift
//  SportsCal
//
//  A searchable directory of every team in the local TeamsManager cache. Taps push
//  TeamDetailView via the Browse stack's `.navigationDestination(for: Team.self)`.
//  Reached from BrowsePage; doubles as the in-app "search for a team" entry point.
//

import SwiftUI
import SportsCalModel
import NukeUI

struct TeamsListView: View {
    @Environment(Favorites.self) private var favorites
    @State private var search = ""
    /// Snapshot of the teams cache; refreshed when TeamsManager posts an update.
    @State private var teams: [Team] = TeamsListView.sortedTeams()

    private static func sortedTeams() -> [Team] {
        TeamsManager.shared.teams
            .filter { ($0.idTeam?.isEmpty == false) && ($0.strTeam?.isEmpty == false) }
            .sorted { ($0.strTeam ?? "") < ($1.strTeam ?? "") }
    }

    private var filtered: [Team] {
        guard !search.isEmpty else { return teams }
        let q = search.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        return teams.filter { team in
            let name = (team.strTeam ?? "").folding(options: .diacriticInsensitive, locale: nil).lowercased()
            let short = (team.strTeamShort ?? "").lowercased()
            return name.contains(q) || short.contains(q)
        }
    }

    private var favoriteTeams: [Team] {
        teams.filter { favorites.contains($0.strTeam ?? "") }
    }

    var body: some View {
        Group {
            if teams.isEmpty {
                ContentUnavailableView(
                    "No Teams",
                    systemImage: "person.3",
                    description: Text("Team data hasn't loaded yet. Pull to refresh or check your connection.")
                )
            } else {
                List {
                    if search.isEmpty, !favoriteTeams.isEmpty {
                        Section("Following") {
                            ForEach(favoriteTeams, id: \.self) { row($0) }
                        }
                    }

                    Section(search.isEmpty ? "All Teams" : "Results") {
                        ForEach(filtered, id: \.self) { row($0) }
                    }

                    if !search.isEmpty, filtered.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
        }
        .navigationTitle("Teams")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $search, prompt: "Search teams")
        .task { TeamsManager.shared.refreshIfStale() }
        .onReceive(NotificationCenter.default.publisher(for: .teamsManagerDidUpdate)) { _ in
            teams = TeamsListView.sortedTeams()
        }
    }

    @ViewBuilder
    private func row(_ team: Team) -> some View {
        NavigationLink(value: team) {
            HStack(spacing: 12) {
                badge(team.strTeamBadge)
                Text(team.strTeam ?? "Team")
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(team.shortCode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if favorites.contains(team.strTeam ?? "") {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    @ViewBuilder
    private func badge(_ urlString: String?) -> some View {
        if let urlString, let url = badgeURL(urlString) {
            LazyImage(request: ImageRequest(url: url, processors: [.resize(size: CGSize(width: 28, height: 28))])) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Circle().fill(Color.gray.opacity(0.15))
                }
            }
            .frame(width: 28, height: 28)
        } else {
            Circle().fill(Color.gray.opacity(0.15)).frame(width: 28, height: 28)
        }
    }

    private func badgeURL(_ urlString: String) -> URL? {
        if urlString.contains("thesportsdb.com") {
            return URL(string: urlString + "/preview")
        }
        return URL(string: urlString)
    }
}
