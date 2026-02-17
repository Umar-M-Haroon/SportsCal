//
//  WidgetRaceCell.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 2/15/26.
//

import SwiftUI
import SportsCalModel

/// Compact race cell for F1 in medium/large widgets
struct WidgetRaceCell: View {
    let game: Game
    let compact: Bool

    private var sportType: SportType { game.sportType ?? .racing }

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 4 : 5) {
            Image(systemName: sportType.widgetSystemImage)
                .font(.system(size: compact ? 10 : 12))
                .foregroundColor(sportType.widgetColor)
                .frame(width: compact ? 12 : 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                // Race name
                Text(game.strHomeTeam)
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .lineLimit(1)

                // Top 3 drivers
                let entries = game.resolvedLeaderboard.prefix(3)
                if entries.isEmpty {
                    statusView
                } else {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 2) {
                            Text("P\(index + 1)")
                                .font(.system(size: compact ? 8 : 9, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(entry.name)
                                .font(.system(size: compact ? 8 : 9))
                                .lineLimit(1)
                            if let constructor = entry.constructor, !constructor.isEmpty {
                                Spacer()
                                Text(constructor)
                                    .font(.system(size: compact ? 7 : 8))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if !entries.isEmpty {
                    statusView
                }
            }
        }
        .padding(compact ? 4 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(widgetCellBackground.opacity(0.5))
        .cornerRadius(compact ? 6 : 8)
    }

    @ViewBuilder
    private var statusView: some View {
        if let status = game.strStatus, !status.isEmpty, status != "NS" {
            Text(game.strProgress ?? status)
                .font(.system(size: compact ? 8 : 9))
                .foregroundColor(.orange)
        } else if let gameDate = game.standardDate {
            Text(gameDate.formatToTime() ?? "")
                .font(.system(size: compact ? 8 : 9))
                .foregroundColor(.secondary)
        }
    }
}
