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
    @State private var selectedSessionIndex: Int = 0

    private var isLive: Bool {
        game.strStatus == "in"
    }

    private var hasSessions: Bool {
        guard let sessions = game.sessions else { return false }
        return !sessions.isEmpty
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                raceHeader
                if hasSessions {
                    sessionPicker
                }
                gameInfo
                actionsRow
                if hasSessions {
                    sessionLeaderboard
                    weekendSchedule
                } else {
                    legacyLeaderboard
                }
            }
            .padding()
        }
        .navigationTitle("Formula 1")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            selectDefaultSession()
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
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Default Session Selection
    private func selectDefaultSession() {
        guard let sessions = game.sessions, !sessions.isEmpty else { return }
        // Pick live session first, else highest-priority completed, else last
        if let liveIndex = sessions.firstIndex(where: { $0.status == "in" }) {
            selectedSessionIndex = liveIndex
        } else {
            let priorities = ["Race": 6, "Sprint": 5, "Qual": 4, "FP3": 3, "FP2": 2, "FP1": 1]
            var bestIndex = sessions.count - 1
            var bestPriority = -1
            for (i, session) in sessions.enumerated() where session.status == "post" {
                let p = priorities[session.sessionType] ?? 0
                if p > bestPriority {
                    bestPriority = p
                    bestIndex = i
                }
            }
            selectedSessionIndex = bestIndex
        }
    }

    // MARK: - Race Header
    private var raceHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.title2)
                    .foregroundColor(.red)
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
                        HStack(spacing: 4) {
                            Text(leader.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if let constructor = leader.constructor {
                                Text("(\(constructor))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
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

    // MARK: - Session Picker
    private var sessionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let sessions = game.sessions {
                    ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedSessionIndex = index
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(sessionStatusColor(session.status))
                                    .frame(width: 6, height: 6)
                                Text(session.sessionType.isEmpty ? session.sessionName : session.sessionType)
                                    .font(.caption)
                                    .fontWeight(index == selectedSessionIndex ? .bold : .regular)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(index == selectedSessionIndex ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(index == selectedSessionIndex ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func sessionStatusColor(_ status: String?) -> Color {
        switch status {
        case "post": return .green
        case "in": return .red
        default: return .gray
        }
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

    // MARK: - Session Leaderboard (new: per-session)
    private var sessionLeaderboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            let sessions = game.sessions ?? []
            let session = selectedSessionIndex < sessions.count ? sessions[selectedSessionIndex] : nil
            let sessionName = session?.sessionName ?? "Standings"

            Text(sessionName)
                .font(.headline)

            if let session, !session.leaderboard.isEmpty {
                // Header row
                HStack(spacing: 0) {
                    Text("Pos")
                        .frame(width: 32, alignment: .leading)
                    Color.clear.frame(width: 34)
                    Text("Driver")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Constructor")
                        .frame(width: 90, alignment: .leading)
                    Text("Time/Gap")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

                ForEach(Array(session.leaderboard.enumerated()), id: \.offset) { index, entry in
                    let isLeader = index == 0
                    HStack(spacing: 0) {
                        Text("\(entry.position)")
                            .frame(width: 32, alignment: .leading)
                        HeadshotView(url: entry.headshot, size: 28)
                            .padding(.trailing, 6)
                        Text(entry.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text(entry.constructor ?? "")
                            .frame(width: 90, alignment: .leading)
                            .lineLimit(1)
                            .font(.caption)
                        Text(entry.gap ?? "--")
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption)
                    .fontWeight(isLeader ? .bold : .regular)
                    .foregroundColor(isLeader ? .primary : .secondary)
                    .padding(.vertical, 2)
                }
            } else {
                Text("No standings available for this session")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Weekend Schedule
    private var weekendSchedule: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekend Schedule")
                .font(.headline)

            if let sessions = game.sessions {
                ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                    HStack {
                        Circle()
                            .fill(sessionStatusColor(session.status))
                            .frame(width: 8, height: 8)
                        Text(session.sessionName)
                            .font(.subheadline)
                        Spacer()
                        if let status = session.status {
                            Text(status == "post" ? "Complete" : (status == "in" ? "In Progress" : "Upcoming"))
                                .font(.caption)
                                .foregroundColor(sessionStatusColor(status))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(Color.secondaryGroupedBackground)
        .cornerRadius(12)
    }

    // MARK: - Legacy Leaderboard (fallback when no sessions)
    private var legacyLeaderboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Race Standings")
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
                    Color.clear.frame(width: 34)
                    Text("Driver")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Constructor")
                        .frame(width: 90, alignment: .leading)
                    Text("Time/Gap")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    let isLeader = index == 0
                    HStack(spacing: 0) {
                        Text("\(entry.position)")
                            .frame(width: 32, alignment: .leading)
                        HeadshotView(url: entry.headshot, size: 28)
                            .padding(.trailing, 6)
                        Text(entry.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text(entry.constructor ?? "")
                            .frame(width: 90, alignment: .leading)
                            .lineLimit(1)
                            .font(.caption)
                        Text(entry.gap ?? "--")
                            .frame(width: 80, alignment: .trailing)
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
