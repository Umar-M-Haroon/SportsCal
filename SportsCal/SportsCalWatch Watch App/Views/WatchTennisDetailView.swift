//
//  WatchTennisDetailView.swift
//  SportsCalWatch
//
//  Detail view for tennis matches.
//  Shows player names and set-by-set score columns.
//

import SwiftUI
import SportsCalModel

struct WatchTennisDetailView: View {
    let game: Game

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 4) {
                    Image(systemName: "tennis.racket")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                    if let progress = game.displayStatus {
                        Text(progress)
                            .font(.system(size: 11))
                            .foregroundStyle(isLive ? .green : .secondary)
                    }
                }

                // Score Table
                VStack(spacing: 0) {
                    let setCount = max(
                        game.homeLinescores?.count ?? 0,
                        game.awayLinescores?.count ?? 0
                    )

                    // Header
                    if setCount > 0 {
                        HStack {
                            Text("Player")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(0..<setCount, id: \.self) { i in
                                Text("S\(i + 1)")
                                    .frame(width: 22)
                            }
                            Text("W")
                                .frame(width: 22)
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                    }

                    // Away player
                    playerScoreRow(
                        name: game.strAwayTeam,
                        linescores: game.awayLinescores,
                        setsWon: game.intAwayScore,
                        setCount: setCount
                    )

                    Divider()

                    // Home player
                    playerScoreRow(
                        name: game.strHomeTeam,
                        linescores: game.homeLinescores,
                        setsWon: game.intHomeScore,
                        setCount: setCount
                    )
                }

                // Match date
                if !isLive, let date = game.standardDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Match")
        .userActivity("com.komodo.SportsCal.gameDetail") { activity in
            activity.title = "\(game.strAwayTeam) vs \(game.strHomeTeam)"
            activity.isEligibleForHandoff = true
            if let eventID = game.idEvent {
                activity.userInfo = ["eventID": eventID]
                activity.webpageURL = URL(string: "sportscal://game/\(eventID)")
            }
        }
    }

    private func playerScoreRow(name: String, linescores: [Double]?, setsWon: String?, setCount: Int) -> some View {
        HStack {
            Text(String(name.prefix(15)))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let scores = linescores {
                ForEach(0..<setCount, id: \.self) { i in
                    Text(i < scores.count ? "\(Int(scores[i]))" : "-")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(width: 22)
                }
            } else {
                ForEach(0..<setCount, id: \.self) { _ in
                    Text("-")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 22)
                }
            }
            Text(setsWon ?? "-")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 22)
        }
        .padding(.vertical, 4)
    }

    private var isLive: Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty && status != "ft" && status != "aet" &&
               status != "not started" && status != "ns" &&
               game.intHomeScore != nil
    }
}
