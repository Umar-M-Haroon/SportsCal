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
        NavigationLink(value: game) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "tennis.racket")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                    if let progress = game.strProgress ?? game.strStatus {
                        Text(progress)
                            .font(.system(size: 10))
                            .foregroundStyle(isLive ? .green : .secondary)
                    }
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

                // Player rows with set scores
                playerRow(name: game.strAwayTeam, linescores: game.awayLinescores)
                playerRow(name: game.strHomeTeam, linescores: game.homeLinescores)

                if !isLive, let date = game.standardDate {
                    Text(date, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func playerRow(name: String, linescores: [Double]?) -> some View {
        HStack(spacing: 4) {
            Text(String(name.prefix(15)))
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            if let scores = linescores {
                ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                    Text("\(Int(score))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
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
