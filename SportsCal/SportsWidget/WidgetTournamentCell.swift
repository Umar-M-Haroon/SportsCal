//
//  WidgetTournamentCell.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 2/15/26.
//

import SwiftUI
import SportsCalModel

/// Compact tournament cell for golf/tennis in medium/large widgets
struct WidgetTournamentCell: View {
    let game: Game
    let compact: Bool

    private var sportType: SportType { game.sportType ?? .golf }

    var body: some View {
        let accent = WidgetTokens.sport(sportType)
        HStack(alignment: .top, spacing: compact ? 4 : 5) {
            Image(systemName: sportType.widgetSystemImage)
                .font(.system(size: compact ? 10 : 12))
                .foregroundStyle(accent)
                .frame(width: compact ? 12 : 14)
                .padding(.top, 2)

            if game.isTennisMatch {
                tennisMatch
            } else {
            VStack(alignment: .leading, spacing: 2) {
                // Event name
                Text(game.strHomeTeam)
                    .font(.system(size: compact ? 9 : 10, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(WidgetTokens.ink)

                // Top 3 leaderboard
                let board = game.resolvedLeaderboard
                let entries = board.prefix(3)
                let positions = sportType == .golf ? board.golfPositionLabels() : []
                if entries.isEmpty {
                    statusView
                } else {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 2) {
                            Text(index < positions.count ? positions[index] : "\(index + 1).")
                                .font(.system(size: compact ? 8 : 9, design: .monospaced).weight(.bold))
                                .foregroundStyle(accent)
                            Text(entry.name)
                                .font(.system(size: compact ? 8 : 9, design: .rounded))
                                .foregroundStyle(WidgetTokens.ink)
                                .lineLimit(1)
                            Spacer()
                            Text(entry.score)
                                .font(.system(size: compact ? 8 : 9, design: .monospaced).weight(.semibold))
                                .foregroundStyle(WidgetTokens.ink)
                        }
                    }
                }

                if !entries.isEmpty {
                    statusView
                }
            }
            }
        }
        .padding(compact ? 4 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// A followed player's match: both players, the sets, who's serving.
    private var tennisMatch: some View {
        let sets = game.tennisSets
        let winner = game.tennisMatchWinner
        return VStack(alignment: .leading, spacing: 2) {
            if let tournament = game.tournamentName {
                Text([tournament, game.shortRoundLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: compact ? 8 : 9, design: .rounded).weight(.semibold))
                    .foregroundStyle(WidgetTokens.inkSoft)
                    .lineLimit(1)
            }
            tennisSide(.home, name: game.strHomeTeam, sets: sets, isWinner: winner == .home)
            tennisSide(.away, name: game.strAwayTeam, sets: sets, isWinner: winner == .away)
            statusView
        }
    }

    private func tennisSide(_ side: GameSituation.Side, name: String, sets: [TennisSet], isWinner: Bool) -> some View {
        HStack(spacing: 2) {
            if game.tennisServer == side {
                Circle().fill(WidgetTokens.live).frame(width: 4, height: 4)
            }
            Text(name)
                .font(.system(size: compact ? 8 : 9, design: .rounded).weight(isWinner ? .bold : .regular))
                .foregroundStyle(WidgetTokens.ink)
                .lineLimit(1)
            Spacer(minLength: 2)
            ForEach(Array(sets.enumerated()), id: \.offset) { _, set in
                Text(set.text(for: side))
                    .font(.system(size: compact ? 8 : 9, design: .monospaced).weight(set.winner == side ? .bold : .regular))
                    .foregroundStyle(set.winner == nil || set.winner == side ? WidgetTokens.ink : WidgetTokens.inkSoft)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
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
