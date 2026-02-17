//
//  TournamentDetailView.swift
//  SportsCal
//
//  Created by Umar Haroon on 2/7/26.
//

import SwiftUI
import SportsCalModel
#if os(iOS)
import EventKit
import EventKitUI
#endif

struct TournamentDetailView: View {
    let game: Game

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @State private var shouldShowSportsCalProAlert = false
    @State private var sheetType: SheetType?
    @State private var expandedPlayers: Set<Int> = []

    private var league: Leagues? {
        guard let id = game.idLeague, let intID = Int(id) else { return nil }
        return Leagues(rawValue: intID)
    }

    private var sportType: SportType? {
        guard let league else { return nil }
        return SportType(league: league)
    }

    private var isLive: Bool {
        game.strStatus == "in"
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                tournamentHeader
                roundProgressBar
                gameInfo
                actionsRow
                leaderboardSection
                roundHeatmapSection
            }
            .padding()
        }
        .navigationTitle(league?.leagueName ?? "Tournament")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Tournament Header
    private var tournamentHeader: some View {
        VStack(spacing: 12) {
            HStack {
                if let sport = sportType {
                    Image(systemName: sport.systemImage)
                        .font(.title2)
                        .foregroundColor(sport.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.strHomeTeam)
                        .font(.title2)
                        .fontWeight(.bold)
                    if let venue = game.venueName {
                        Text(venue)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if isLive {
                    Text("LIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }

            if let progress = game.strProgress {
                Text(progress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Leader highlight
            if let leader = game.resolvedLeaderboard.first {
                HStack(spacing: 8) {
                    HeadshotView(url: leader.headshot, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Leader")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(leader.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    Text(leader.score)
                        .font(.title3)
                        .fontWeight(.bold)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Round Progress Bar
    @ViewBuilder
    private var roundProgressBar: some View {
        let entries = game.resolvedLeaderboard
        let maxRounds = entries.map(\.rounds.count).max() ?? 0
        if maxRounds > 0 {
            let currentRound = detectCurrentRound(entries: entries, maxRounds: maxRounds)
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(0..<maxRounds, id: \.self) { i in
                        if i > 0 {
                            Rectangle()
                                .fill(i <= currentRound ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(height: 2)
                        }
                        ZStack {
                            Circle()
                                .fill(roundColor(index: i, current: currentRound))
                                .frame(width: 24, height: 24)
                            Text("R\(i + 1)")
                                .font(.caption2)
                                .fontWeight(i == currentRound ? .bold : .regular)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func detectCurrentRound(entries: [LeaderboardEntry], maxRounds: Int) -> Int {
        // Current round = the round most players are on (incomplete round)
        // If all have same count, the last round is current/done
        guard let leader = entries.first else { return 0 }
        let leaderRounds = leader.rounds.count
        if leader.thruHole != nil && leader.thruHole != "F" {
            return max(0, leaderRounds - 1)
        }
        return max(0, leaderRounds - 1)
    }

    private func roundColor(index: Int, current: Int) -> Color {
        if index < current { return .green }
        if index == current { return .accentColor }
        return Color.gray.opacity(0.4)
    }

    // MARK: - Game Info
    private var gameInfo: some View {
        HStack(spacing: 12) {
            if let sport = sportType {
                Image(systemName: sport.systemImage)
                    .foregroundColor(sport.color)
            }
            if let leagueName = league?.leagueName {
                Text(leagueName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let date = game.standardDate {
                Text(date.formatted(.dateTime.month().day().year().hour().minute()))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Actions Row
    private var actionsRow: some View {
        HStack(spacing: 16) {
            Menu {
                FavoriteMenu(game: game)
                    .environment(favorites)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: favorites.contains(game) ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundColor(favorites.contains(game) ? .yellow : .secondary)
                    Text("Favorite")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            #if canImport(ActivityKit) && os(iOS)
            autoFollowAction
            #endif

            #if os(iOS)
            Button {
                EKEventStore().requestAccess(to: .event) { _, _ in
                    sheetType = .calendar(game: game)
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Calendar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            #endif

            Menu {
                NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "bell.badge")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Notify")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Auto-Follow Action
    #if canImport(ActivityKit) && os(iOS)
    @ViewBuilder
    private var autoFollowAction: some View {
        if let eventID = game.idEvent, !isGameCompleted(game), !isLive {
            let isFollowing = viewModel.appStorage.isAutoFollowing(eventID)
            Button {
                if isFollowing {
                    viewModel.appStorage.removeAutoFollow(eventID)
                } else {
                    viewModel.appStorage.addAutoFollow(eventID)
                    if let (home, away) = viewModel.getTeams(for: game) {
                        viewModel.preCacheBadges(homeTeam: home, awayTeam: away)
                    }
                }
                #if os(iOS)
                viewModel.sendAutoFollowRegistration()
                #endif
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: isFollowing ? "clock.badge.fill" : "clock.badge")
                        .font(.title3)
                        .foregroundColor(isFollowing ? .accentColor : .secondary)
                    Text(isFollowing ? "Following" : "Auto-Follow")
                        .font(.caption2)
                        .foregroundColor(isFollowing ? .accentColor : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    #endif

    // MARK: - Leaderboard
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leaderboard")
                .font(.headline)

            let entries = game.resolvedLeaderboard
            if entries.isEmpty {
                VStack(spacing: 8) {
                    if game.strAwayTeam != "TBD" {
                        HStack {
                            Text(game.strAwayTeam)
                                .font(.subheadline)
                            Spacer()
                            if let score = game.intAwayScore {
                                Text(score)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    Text("Detailed leaderboard not available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else {
                let hasRounds = entries.contains(where: { !$0.rounds.isEmpty })
                let hasThru = entries.contains(where: { $0.thruHole != nil })

                // Header row
                HStack(spacing: 0) {
                    Text("Pos")
                        .frame(width: 32, alignment: .leading)
                    // Headshot column spacer
                    Color.clear.frame(width: 30)
                    Text("Player")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if hasThru {
                        Text("Thru")
                            .frame(width: 44, alignment: .trailing)
                    }
                    Text("Score")
                        .frame(width: 50, alignment: .trailing)
                    if hasRounds {
                        // Chevron spacer
                        Color.clear.frame(width: 24)
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

                // Player rows
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    let isLeader = index == 0
                    let isExpanded = expandedPlayers.contains(index)

                    VStack(spacing: 0) {
                        Button {
                            if !entry.rounds.isEmpty {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedPlayers.contains(index) {
                                        expandedPlayers.remove(index)
                                    } else {
                                        expandedPlayers.insert(index)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 0) {
                                Text("\(entry.position)")
                                    .frame(width: 32, alignment: .leading)
                                HeadshotView(url: entry.headshot, size: 28)
                                    .padding(.trailing, 2)
                                Text(entry.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                if hasThru {
                                    Text(entry.thruHole ?? "-")
                                        .frame(width: 44, alignment: .trailing)
                                        .foregroundColor(.secondary)
                                }
                                Text(entry.score)
                                    .frame(width: 50, alignment: .trailing)
                                if hasRounds && !entry.rounds.isEmpty {
                                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 24)
                                } else if hasRounds {
                                    Color.clear.frame(width: 24)
                                }
                            }
                            .font(.caption)
                            .fontWeight(isLeader ? .bold : .regular)
                            .foregroundColor(isLeader ? .primary : .secondary)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Expanded round scores
                        if isExpanded && !entry.rounds.isEmpty {
                            HStack(spacing: 0) {
                                Color.clear.frame(width: 62) // pos + headshot
                                ForEach(Array(entry.rounds.enumerated()), id: \.offset) { rIndex, round in
                                    VStack(spacing: 2) {
                                        Text("R\(rIndex + 1)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(round)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Round Heatmap
    @ViewBuilder
    private var roundHeatmapSection: some View {
        let entries = game.resolvedLeaderboard
        let hasRounds = entries.contains(where: { !$0.rounds.isEmpty })
        if hasRounds {
            RoundHeatmapView(entries: entries)
        }
    }

    #if os(iOS)
    // MARK: - Calendar Event
    private func makeCalendarEvent(game: Game) -> CalendarRepresentable {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        event.title = game.strHomeTeam
        if let gameDate = game.standardDate {
            event.startDate = gameDate
            event.endDate = gameDate.afterHoursFromNow(hours: 4)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif
}
