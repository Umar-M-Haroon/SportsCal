//
//  PollRankingsView.swift
//  SportsCal (iOS)
//
//  College polls in a league hub: AP Top 25, the Coaches Poll, the CFP and the
//  lower-division polls, for any week of the season. Wide layouts (Mac, iPad) add
//  conference, poll points and first-place votes.
//

import SwiftUI
import NukeUI
import SportsCalModel

struct PollRankingsView: View {
    let league: Leagues

    @Environment(Favorites.self) private var favorites
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var rankings: PollRankings?
    /// The latest week's polls, kept so going back to it needs no request.
    @State private var latest: PollRankings?
    @State private var selectedPollID: String?
    @State private var isLoading = false
    @State private var didFail = false
    @State private var weekTask: Task<Void, Never>?

    private var sport: SportType { SportType(league: league) }

    private var isWide: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    private var selectedPoll: PollRankings.Poll? {
        rankings?.polls.first { $0.id == selectedPollID } ?? rankings?.polls.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .appSpace4) {
            if let rankings, let poll = selectedPoll {
                controls(rankings, poll: poll)
                pollTable(poll)
                    .opacity(isLoading ? 0.5 : 1)
                if !poll.others.isEmpty {
                    othersCard(title: "Others receiving votes", entries: poll.others)
                }
                if !poll.droppedOut.isEmpty {
                    othersCard(title: "Dropped out", entries: poll.droppedOut)
                }
            } else if didFail {
                ContentUnavailableView("No Rankings", systemImage: "trophy",
                                       description: Text("\(league.leagueName) rankings aren't available right now."))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .appSpace5)
            }
        }
        .task { await loadLatest() }
    }

    // MARK: - Loading

    private func loadLatest() async {
        guard latest == nil else { return }
        do {
            let loaded = try await NetworkHandler.getPollRankings(league: league)
            latest = loaded
            rankings = loaded
        } catch {
            didFail = rankings == nil
        }
    }

    private func select(_ week: PollRankings.Week) {
        weekTask?.cancel()
        isLoading = false
        guard week != rankings?.week else { return }
        if let latest, week == latest.week {
            rankings = latest
            return
        }
        isLoading = true
        weekTask = Task {
            // On failure the previous week stays up; the picker snaps back to it.
            let loaded = try? await NetworkHandler.getPollRankings(league: league, week: week)
            guard !Task.isCancelled else { return }
            if let loaded { rankings = loaded }
            isLoading = false
        }
    }

    // MARK: - Controls

    private func controls(_ rankings: PollRankings, poll: PollRankings.Poll) -> some View {
        HStack(spacing: .appSpace2) {
            Menu {
                Picker("Poll", selection: Binding(
                    get: { poll.id },
                    set: { selectedPollID = $0 }
                )) {
                    ForEach(rankings.polls) { Text($0.name).tag($0.id) }
                }
            } label: {
                menuLabel(poll.shortName)
            }

            Menu {
                Picker("Week", selection: Binding(
                    get: { rankings.week },
                    set: { select($0) }
                )) {
                    ForEach(rankings.weeks.reversed()) { Text($0.label).tag($0) }
                }
            } label: {
                menuLabel(rankings.week.label)
            }

            Spacer(minLength: 0)

            if let released = poll.releaseDate {
                Text("Released \(released.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.app(sport))
        .padding(.horizontal, .appSpace3)
        .padding(.vertical, 6)
        .background(Color.appTint(sport), in: Capsule())
    }

    // MARK: - Table

    private func pollTable(_ poll: PollRankings.Poll) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(poll.ranks) { entry in
                Divider().overlay(Color.appDivider)
                row(entry)
            }
        }
        .appCard()
    }

    private var header: some View {
        HStack(spacing: .appSpace2) {
            Text("#").frame(width: 24, alignment: .leading)
            Text("").frame(width: 30)
            Text("Team").frame(maxWidth: .infinity, alignment: .leading)
            if isWide {
                Text("Conf").frame(width: 70, alignment: .leading)
            }
            Text("Rec").frame(width: 44, alignment: .trailing)
            if isWide {
                Text("Pts").frame(width: 56, alignment: .trailing)
                Text("1st").frame(width: 36, alignment: .trailing)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
    }

    private func row(_ entry: PollRankings.Entry) -> some View {
        let followed = isFollowed(entry.team)
        return HStack(spacing: .appSpace2) {
            Text(entry.rank.map(String.init) ?? "–")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .frame(width: 24, alignment: .leading)
            MovementBadge(entry: entry)
                .frame(width: 30, alignment: .leading)
            HStack(spacing: .appSpace2) {
                PollTeamLogo(team: entry.team, size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(isWide ? entry.team.displayName : entry.team.location)
                        .font(.subheadline.weight(followed ? .bold : .regular))
                        .lineLimit(1)
                    if !isWide, let votes = entry.firstPlaceVotes {
                        Text("\(votes) first-place vote\(votes == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isWide {
                Text(entry.team.conference ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 70, alignment: .leading)
            }
            Text(entry.record ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            if isWide {
                Text(entry.points.map(Self.formatPoints) ?? "")
                    .font(.caption.monospacedDigit())
                    .frame(width: 56, alignment: .trailing)
                Text(entry.firstPlaceVotes.map(String.init) ?? "")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
        .background(followed ? Color.appTint(sport).opacity(0.6) : .clear)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Others

    private func othersCard(title: String, entries: [PollRankings.Entry]) -> some View {
        VStack(alignment: .leading, spacing: .appSpace2) {
            Text(title.uppercased()).appEyebrow().foregroundStyle(Color.app(sport))
            Text(entries.map { entry in
                if let previous = entry.previous, title == "Dropped out" {
                    return "\(entry.team.location) (was \(previous))"
                }
                return entry.points.map { "\(entry.team.location) \(Self.formatPoints($0))" } ?? entry.team.location
            }.joined(separator: ", "))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    // MARK: - Helpers

    /// College teams are followed by their prefixed ESPN ID (`ncaaf-2390`).
    private func isFollowed(_ team: PollRankings.Team) -> Bool {
        favorites.teamIDs.contains(league.teamID(espnID: team.id))
    }

    private static func formatPoints(_ points: Double) -> String {
        points.formatted(.number.precision(.fractionLength(0)))
    }
}

/// ▲3 / ▼2 / NEW, or nothing for an unchanged rank.
private struct MovementBadge: View {
    let entry: PollRankings.Entry

    var body: some View {
        if entry.isNew {
            Text("NEW")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.appPositive)
        } else if let movement = entry.movement, movement != 0 {
            HStack(spacing: 1) {
                Image(systemName: movement > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 7))
                Text("\(abs(movement))")
                    .font(.caption2.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(movement > 0 ? Color.appPositive : Color.appNegative)
            .accessibilityLabel(movement > 0 ? "Up \(movement)" : "Down \(-movement)")
        }
    }
}

private struct PollTeamLogo: View {
    let team: PollRankings.Team
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let href = colorScheme == .dark ? (team.darkLogo ?? team.logo) : team.logo
        if let href, let url = URL(string: href) {
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
        Circle().fill(Color.gray.opacity(0.2)).frame(width: size, height: size)
    }
}
