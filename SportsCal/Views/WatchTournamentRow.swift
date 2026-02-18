//
//  WatchTournamentRow.swift
//  SportsCalWatch
//
//  Compact tournament row for Golf/Tennis on Apple Watch.
//

import SwiftUI
import SportsCalModel

struct WatchTournamentRow: View {
    let game: Game

    var body: some View {
        NavigationLink(value: game) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    let sportType = game.sportType ?? .golf
                    Image(systemName: sportType.widgetSystemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(sportType.widgetColor)
                    Text(game.strHomeTeam)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if isLive {
                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.green, in: Capsule())
                    }
                }

                if isLive, let leader = game.resolvedLeaderboard.first {
                    HStack(spacing: 4) {
                        Text("\(leader.position).")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(leader.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        Text(leader.score)
                            .font(.system(size: 11, weight: .semibold))
                    }
                } else if let date = game.standardDate {
                    HStack {
                        if let progress = game.strProgress {
                            Text(progress)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(date, style: .time)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var isLive: Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty && status != "ft" && status != "aet" &&
               status != "not started" && status != "ns"
    }
}
