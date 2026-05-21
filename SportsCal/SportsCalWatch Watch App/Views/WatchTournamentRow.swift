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
        let sportType = game.sportType ?? .golf
        let accent = WatchTokens.sport(sportType)
        NavigationLink(value: game) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: sportType.widgetSystemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                    Text(game.strHomeTeam)
                        .font(.system(size: 12, design: .rounded).weight(.semibold))
                        .foregroundStyle(WatchTokens.ink)
                        .lineLimit(1)
                    Spacer()
                    if isLive {
                        WatchLiveTag(period: nil)
                    }
                }

                if isLive, let leader = game.resolvedLeaderboard.first {
                    HStack(spacing: 4) {
                        Text("\(leader.position).")
                            .font(.system(size: 11, design: .monospaced).weight(.bold))
                            .foregroundStyle(accent)
                        Text(leader.name)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(WatchTokens.ink)
                            .lineLimit(1)
                        Spacer()
                        Text(leader.score)
                            .font(.system(size: 11, design: .monospaced).weight(.semibold))
                            .foregroundStyle(WatchTokens.ink)
                    }
                } else if let date = game.standardDate {
                    HStack {
                        if let progress = game.strProgress {
                            Text(progress)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(WatchTokens.inkSoft)
                        } else {
                            Text(date, style: .time)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(WatchTokens.inkSoft)
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
