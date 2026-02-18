//
//  WatchTournamentDetailView.swift
//  SportsCalWatch
//
//  Detail view for golf/tennis tournaments.
//  Shows top 5 leaderboard with position, name, score, thruHole.
//

import SwiftUI
import SportsCalModel

struct WatchTournamentDetailView: View {
    let game: Game

    private var leaderboard: [LeaderboardEntry] {
        Array(game.resolvedLeaderboard.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Header
                VStack(spacing: 4) {
                    let sportType = game.sportType ?? .golf
                    Image(systemName: sportType.widgetSystemImage)
                        .font(.title3)
                        .foregroundStyle(sportType.widgetColor)
                    Text(game.strHomeTeam)
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)
                    if let progress = game.strProgress ?? game.strStatus {
                        Text(progress)
                            .font(.system(size: 11))
                            .foregroundStyle(isLive ? .green : .secondary)
                    }
                }

                // Leaderboard
                if !leaderboard.isEmpty {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Pos")
                                .frame(width: 24, alignment: .leading)
                            Text("Player")
                            Spacer()
                            Text("Thru")
                                .frame(width: 32)
                            Text("Score")
                                .frame(width: 36, alignment: .trailing)
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                        ForEach(Array(leaderboard.enumerated()), id: \.offset) { _, entry in
                            HStack {
                                Text("\(entry.position)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 24, alignment: .leading)
                                Text(entry.name)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Spacer()
                                Text(entry.thruHole ?? "-")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32)
                                Text(entry.score)
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 36, alignment: .trailing)
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
        .navigationTitle("Leaderboard")
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
