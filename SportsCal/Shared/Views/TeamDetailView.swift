//
//  TeamDetailView.swift
//  SportsCal
//
//  A team profile screen: badge + name header, a favorite toggle, and the team's
//  upcoming schedule and recent results derived from the games already loaded into
//  GameViewModel. Roster / stats are stubbed pending a dedicated server endpoint.
//
//  Reached via `.navigationDestination(for: Team.self)` — push by giving a
//  `NavigationLink(value: team)` anywhere inside a NavigationStack that registers it.
//

import SwiftUI
import SportsCalModel
import NukeUI

struct TeamDetailView: View {
    let team: Team

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites

    /// Extended profile + roster, loaded lazily from the server. Nil until the fetch
    /// resolves; an empty/failed fetch leaves it nil so the section shows "unavailable".
    @State private var detail: TeamDetail?
    @State private var didLoadDetail = false

    // MARK: - Derived schedule

    /// Every loaded game this team appears in — matched by stable TheSportsDB id
    /// first, falling back to name/alternate-name for records missing ids.
    private var teamGames: [Game] {
        let all = viewModel.totalGames ?? []
        let names = Set([team.strTeam, team.strAlternate].compactMap { $0 })
        return all.filter { game in
            if let id = team.idTeam, !id.isEmpty {
                if game.idHomeTeam == id || game.idAwayTeam == id { return true }
            }
            return names.contains(game.strHomeTeam) || names.contains(game.strAwayTeam)
        }
    }

    private var upcomingGames: [Game] {
        teamGames
            .filter { !$0.hasDoneStatus }
            .sorted { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }
    }

    private var recentGames: [Game] {
        teamGames
            .filter { $0.hasDoneStatus }
            .sorted { ($0.standardDate ?? .distantPast) > ($1.standardDate ?? .distantPast) }
    }

    private var sportType: SportType? {
        teamGames.lazy.compactMap { $0.sportType }.first
    }

    private func isTeamHome(in game: Game) -> Bool {
        if let id = team.idTeam, !id.isEmpty { return game.idHomeTeam == id }
        return game.strHomeTeam == team.strTeam
    }

    /// Current win–loss record, read from the most recent game carrying one for this
    /// team's side (future/scheduled games carry the up-to-date season record). ESPN-
    /// sourced and already on every `Game`, so this needs no extra fetch.
    private var teamRecord: String? {
        let byRecency = teamGames.sorted { ($0.standardDate ?? .distantPast) > ($1.standardDate ?? .distantPast) }
        for game in byRecency {
            let record = isTeamHome(in: game) ? game.homeRecord : game.awayRecord
            if let record, !record.isEmpty { return record }
        }
        return nil
    }

    private var isFavorited: Bool {
        guard let name = team.strTeam else { return false }
        return favorites.contains(name)
    }

    // MARK: - Body

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !upcomingGames.isEmpty {
                Section("Upcoming") {
                    ForEach(upcomingGames) { gameRow($0) }
                }
            }

            if !recentGames.isEmpty {
                Section("Recent Results") {
                    ForEach(recentGames.prefix(20)) { gameRow($0) }
                }
            }

            if teamGames.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Games Scheduled",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("There are no loaded games for this team right now.")
                    )
                }
            }

            rosterAndInfoSections
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .task(id: team.idTeam) { await loadDetail() }
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            badge(team.strTeamBadge, size: 96)

            VStack(spacing: 4) {
                Text(team.strTeam ?? "Team")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    if let sport = sportType {
                        Label(sport.displayName, systemImage: sport.systemImage)
                            .foregroundStyle(sport.color)
                    }
                    Text(team.shortCode)
                        .foregroundStyle(.secondary)
                    if let record = teamRecord {
                        Text("·").foregroundStyle(.tertiary)
                        Text(record)
                            .fontWeight(.semibold)
                    }
                }
                .font(.subheadline)
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

    // MARK: - Rows

    @ViewBuilder
    private func gameRow(_ game: Game) -> some View {
        if let teams = viewModel.getTeams(for: game) {
            NavigationLink {
                AdaptiveGameDetail(game: game, homeTeam: teams.home, awayTeam: teams.away)
                    .environment(viewModel)
                    .environment(favorites)
            } label: {
                TeamScheduleRow(team: team, game: game, home: teams.home, away: teams.away)
            }
        }
    }

    // MARK: - Roster & info

    private var hasProfileInfo: Bool {
        guard let p = detail?.profile else { return false }
        return [p.formedYear, p.stadium, p.stadiumLocation, p.stadiumCapacity, p.descriptionText]
            .contains { ($0?.isEmpty == false) }
    }

    @ViewBuilder
    private var rosterAndInfoSections: some View {
        if teamRecord != nil || hasProfileInfo {
            Section("Info") {
                // Record comes from local ESPN game data — shows immediately, even
                // before the server profile (stadium/founded/…) resolves.
                if let record = teamRecord { infoRow("Record", record) }
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

    // MARK: - Actions

    private func toggleFavorite() {
        guard let name = team.strTeam else { return }
        if favorites.contains(name) {
            favorites.remove(name)
        } else {
            favorites.add(name)
        }
    }

    // MARK: - Badge

    @ViewBuilder
    private func badge(_ urlString: String?, size: CGFloat) -> some View {
        if let urlString, let url = resolvedBadgeURL(urlString) {
            LazyImage(request: ImageRequest(url: url, processors: [.resize(size: CGSize(width: size, height: size))])) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    badgePlaceholder(size: size)
                }
            }
            .frame(width: size, height: size)
        } else {
            badgePlaceholder(size: size)
        }
    }

    private func badgePlaceholder(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.2))
            Text(team.shortCode)
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
    }

    private func resolvedBadgeURL(_ urlString: String) -> URL? {
        if urlString.contains("thesportsdb.com") {
            return URL(string: urlString + "/preview")
        }
        return URL(string: urlString)
    }
}

/// A single schedule line: opponent badge + name, the @/vs indicator, and either a
/// final score (with this team's result) or the upcoming tip-off time.
private struct TeamScheduleRow: View {
    /// The team whose page this is — used to orient home/away and win/loss.
    let team: Team
    let game: Game
    let home: Team
    let away: Team

    private var isHome: Bool {
        if let id = team.idTeam, !id.isEmpty { return game.idHomeTeam == id || home.idTeam == id }
        return game.strHomeTeam == team.strTeam
    }

    private var opponent: Team { isHome ? away : home }

    private var homeScore: Int? { game.intHomeScore.flatMap { Int($0) } }
    private var awayScore: Int? { game.intAwayScore.flatMap { Int($0) } }
    private var hasScores: Bool { homeScore != nil && awayScore != nil }

    private var resultBadge: (text: String, color: Color)? {
        guard let h = homeScore, let a = awayScore else { return nil }
        let teamScore = isHome ? h : a
        let oppScore = isHome ? a : h
        if teamScore == oppScore { return ("T", .secondary) }
        return teamScore > oppScore ? ("W", .green) : ("L", .red)
    }

    var body: some View {
        HStack(spacing: 10) {
            badge(opponent.strTeamBadge)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(isHome ? "vs" : "@") \(opponent.strTeam ?? game.strAwayTeam)")
                    .font(.subheadline)
                    .lineLimit(1)
                if let date = game.standardDate {
                    Text(date.formatted(.dateTime.month().day().year()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if hasScores, let result = resultBadge {
                HStack(spacing: 6) {
                    Text(result.text)
                        .font(.caption.bold())
                        .foregroundStyle(result.color)
                    Text("\(awayScore ?? 0)–\(homeScore ?? 0)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else if let date = game.standardDate {
                GameTimeLabel(date: date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func badge(_ urlString: String?) -> some View {
        if let urlString, let url = badgeURL(urlString) {
            LazyImage(request: ImageRequest(url: url, processors: [.resize(size: CGSize(width: 26, height: 26))])) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Circle().fill(Color.gray.opacity(0.15))
                }
            }
            .frame(width: 26, height: 26)
        } else {
            Circle().fill(Color.gray.opacity(0.15)).frame(width: 26, height: 26)
        }
    }

    private func badgeURL(_ urlString: String) -> URL? {
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
