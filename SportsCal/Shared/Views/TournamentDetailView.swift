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
                gameInfo
                actionsRow
                leaderboardSection
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
                Text(game.strHomeTeam)
                    .font(.title2)
                    .fontWeight(.bold)
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
            if let entries = game.leaderboard.first {
                HStack {
                    Text("Leader:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(entries.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(entries.score)
                        .font(.title3)
                        .fontWeight(.bold)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
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
            if #available(iOS 16.1, *) {
                autoFollowAction
            }
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
    @available(iOS 16.1, *)
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
                viewModel.sendAutoFollowRegistration()
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

            let entries = game.leaderboard
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
                let maxRounds = entries.map(\.rounds.count).max() ?? 0

                // Header row
                HStack(spacing: 0) {
                    Text("Pos")
                        .frame(width: 32, alignment: .leading)
                    Text("Player")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Score")
                        .frame(width: 50, alignment: .trailing)
                    if hasRounds {
                        ForEach(0..<maxRounds, id: \.self) { i in
                            Text("R\(i + 1)")
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

                // Player rows
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    let isLeader = index == 0
                    HStack(spacing: 0) {
                        Text("\(index + 1)")
                            .frame(width: 32, alignment: .leading)
                        Text(entry.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text(entry.score)
                            .frame(width: 50, alignment: .trailing)
                        if hasRounds {
                            ForEach(0..<maxRounds, id: \.self) { i in
                                Text(i < entry.rounds.count ? entry.rounds[i] : "-")
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                    .font(.caption)
                    .fontWeight(isLeader ? .bold : .regular)
                    .foregroundColor(isLeader ? .primary : .secondary)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
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
