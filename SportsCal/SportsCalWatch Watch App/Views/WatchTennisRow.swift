//
//  WatchTennisRow.swift
//  SportsCalWatch
//
//  Compact tennis match row for Apple Watch.
//

import SwiftUI
import SportsCalModel

struct WatchTennisRow: View {
    let game: Game

    var body: some View {
        let accent = WatchTokens.sport(.tennis)
        NavigationLink(value: game) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "tennis.racket")
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                    if let progress = game.displayStatus {
                        Text(progress)
                            .font(.system(size: 10, design: .monospaced).weight(.semibold))
                            .foregroundStyle(isLive ? WatchTokens.live : WatchTokens.inkSoft)
                    }
                    Spacer()
                    if isLive {
                        WatchLiveTag(period: nil)
                    }
                }

                // Player rows with set scores
                playerRow(name: game.strAwayTeam, linescores: game.awayLinescores)
                playerRow(name: game.strHomeTeam, linescores: game.homeLinescores)

                if !isLive, let date = game.standardDate {
                    Text(date, style: .time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(WatchTokens.inkSoft)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func playerRow(name: String, linescores: [Double]?) -> some View {
        HStack(spacing: 4) {
            Text(String(name.prefix(15)))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(WatchTokens.ink)
                .lineLimit(1)
            Spacer()
            if let scores = linescores {
                ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                    Text("\(Int(score))")
                        .font(.system(size: 11, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(WatchTokens.ink)
                        .frame(width: 14)
                }
            }
        }
    }

    private var isLive: Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty && status != "ft" && status != "aet" &&
               status != "not started" && status != "ns" &&
               game.intHomeScore != nil
    }
}
