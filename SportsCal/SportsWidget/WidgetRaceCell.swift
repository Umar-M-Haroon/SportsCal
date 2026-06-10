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
        let accent = WidgetTokens.sport(sportType)
        HStack(alignment: .top, spacing: compact ? 4 : 5) {
            Image(systemName: sportType.widgetSystemImage)
                .font(.system(size: compact ? 10 : 12))
                .foregroundStyle(accent)
                .frame(width: compact ? 12 : 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                // Race name
                Text(game.strHomeTeam)
                    .font(.system(size: compact ? 9 : 10, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(WidgetTokens.ink)

                // Top 3 drivers
                let entries = game.resolvedLeaderboard.prefix(3)
                if entries.isEmpty {
                    statusView
                } else {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 2) {
                            Text("P\(index + 1)")
                                .font(.system(size: compact ? 8 : 9, design: .monospaced).weight(.bold))
                                .foregroundStyle(accent)
                            Text(entry.name)
                                .font(.system(size: compact ? 8 : 9, design: .rounded))
                                .foregroundStyle(WidgetTokens.ink)
                                .lineLimit(1)
                            if let constructor = entry.constructor, !constructor.isEmpty {
                                Spacer()
                                Text(constructor)
                                    .font(.system(size: compact ? 7 : 8, design: .monospaced))
                                    .foregroundStyle(WidgetTokens.inkFaint)
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
        .background(WidgetTokens.alt)
        .clipShape(RoundedRectangle(cornerRadius: compact ? WidgetTokens.radiusSM : WidgetTokens.radiusMD, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: compact ? WidgetTokens.radiusSM : WidgetTokens.radiusMD, style: .continuous))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch game.raceWeekendStatus {
        case .live(let name):
            HStack(spacing: 3) {
                Circle().fill(WidgetTokens.live).frame(width: 4, height: 4)
                Text("\(name) LIVE")
                    .font(.system(size: compact ? 8 : 9, design: .monospaced).weight(.semibold))
                    .foregroundStyle(WidgetTokens.live)
            }
        case .finished:
            Text("Final")
                .font(.system(size: compact ? 8 : 9, design: .monospaced).weight(.semibold))
                .foregroundStyle(WidgetTokens.inkSoft)
        case .upcoming(let label, let date):
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: compact ? 7 : 8))
                    .foregroundStyle(WidgetTokens.inkSoft)
                Text("\(label) · \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .font(.system(size: compact ? 8 : 9, design: .monospaced))
                    .foregroundStyle(WidgetTokens.inkSoft)
                    .lineLimit(1)
            }
        case .none:
            if let statusText = game.displayStatus {
                HStack(spacing: 3) {
                    Circle().fill(WidgetTokens.live).frame(width: 4, height: 4)
                    Text(statusText)
                        .font(.system(size: compact ? 8 : 9, design: .monospaced).weight(.semibold))
                        .foregroundStyle(WidgetTokens.live)
                }
            } else if let gameDate = game.standardDate {
                Text(gameDate.formatToTime() ?? "")
                    .font(.system(size: compact ? 8 : 9, design: .monospaced))
                    .foregroundStyle(WidgetTokens.inkSoft)
            }
        }
    }
}
