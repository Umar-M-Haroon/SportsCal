//
//  RaceDetailView.swift
//  SportsCal
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel
#if os(iOS)
import EventKit
import EventKitUI
#endif

struct RaceDetailView: View {
    let game: Game

    @Environment(GameViewModel.self) private var viewModel
    @Environment(Favorites.self) private var favorites
    @State private var shouldShowSportsCalProAlert = false
    @State private var sheetType: SheetType?

    private var isLive: Bool {
        game.strStatus == "in"
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                raceHeader
                gameInfo
                actionsRow
                leaderboardSection
            }
            .padding()
        }
        .navigationTitle("Formula 1")
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

    // MARK: - Race Header
    private var raceHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.title2)
                    .foregroundColor(.red)
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
            if let leader = game.raceLeaderboard.first {
                HStack {
                    Text("Leader:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(leader.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if !leader.constructor.isEmpty {
                        Text("(\(leader.constructor))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(leader.position)
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
            Image(systemName: "flag.checkered.2.crossed")
                .foregroundColor(.red)
            Text("Formula 1")
                .font(.subheadline)
                .foregroundColor(.secondary)
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
            Text("Race Standings")
                .font(.headline)

            let entries = game.raceLeaderboard
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
                    Text("Detailed standings not available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else {
                // Header row
                HStack(spacing: 0) {
                    Text("Pos")
                        .frame(width: 32, alignment: .leading)
                    Text("Driver")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Constructor")
                        .frame(width: 100, alignment: .leading)
                    Text("Time/Gap")
                        .frame(width: 90, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

                // Driver rows
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    let isLeader = index == 0
                    HStack(spacing: 0) {
                        Text("\(index + 1)")
                            .frame(width: 32, alignment: .leading)
                        Text(entry.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text(entry.constructor)
                            .frame(width: 100, alignment: .leading)
                            .lineLimit(1)
                            .font(.caption)
                        Text(entry.gap.isEmpty ? "--" : entry.gap)
                            .frame(width: 90, alignment: .trailing)
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
            event.endDate = gameDate.afterHoursFromNow(hours: 3)
        }
        return CalendarRepresentable(eventStore: eventStore, event: event)
    }
    #endif
}
