//
//  WatchRaceDetailView.swift
//  SportsCalWatch
//
//  Detail view for F1 races.
//  Shows top 5 drivers with position, name, constructor, gap.
//

import SwiftUI
import SportsCalModel

struct WatchRaceDetailView: View {
    let game: Game

    private var leaderboard: [LeaderboardEntry] {
        Array(game.resolvedLeaderboard.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Header
                VStack(spacing: 4) {
                    Image(systemName: "flag.checkered.2.crossed")
                        .font(.title3)
                        .foregroundStyle(.red)
                    Text(game.strHomeTeam)
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)
                    if let progress = game.displayStatus {
                        Text(progress)
                            .font(.system(size: 11))
                            .foregroundStyle(isLive ? .green : .secondary)
                    }
                }

                // Sessions (if available)
                if let sessions = game.sessions, !sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                            HStack {
                                Text(session.sessionName)
                                    .font(.system(size: 10))
                                Spacer()
                                if let status = session.status {
                                    Text(status)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Leaderboard
                if !leaderboard.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text("P")
                                .frame(width: 18, alignment: .leading)
                            Text("Driver")
                            Spacer()
                            Text("Gap")
                                .frame(width: 50, alignment: .trailing)
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                        ForEach(Array(leaderboard.enumerated()), id: \.offset) { _, entry in
                            HStack {
                                Text("\(entry.position)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 18, alignment: .leading)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(entry.name)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    if let constructor = entry.constructor {
                                        Text(constructor)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(entry.gap ?? (entry.position == 1 ? "Leader" : "-"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                            Divider()
                        }
                    }
                } else if let date = game.standardDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Race")
        .userActivity("com.komodo.SportsCal.gameDetail") { activity in
            activity.title = game.strHomeTeam
            activity.isEligibleForHandoff = true
            if let eventID = game.idEvent {
                activity.userInfo = ["eventID": eventID]
                activity.webpageURL = URL(string: "sportscal://game/\(eventID)")
            }
        }
    }

    private var isLive: Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty && status != "ft" && status != "aet" &&
               status != "not started" && status != "ns"
    }
}
