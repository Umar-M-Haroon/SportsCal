//
//  RaceScoreView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel

/// Displays an F1 race with a mini leaderboard showing top 3 drivers and constructors
struct RaceScoreView: View {
    var game: Game
    @Environment(Favorites.self) private var favorites
    @Environment(GameViewModel.self) private var viewModel
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Race header
            HStack {
                if viewModel.appStorage.debugMode, game.idEvent?.hasPrefix(DebugGameFactory.isFakeEventPrefix) == true {
                    Text("DEBUG")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(.orange, in: RoundedRectangle(cornerRadius: 4))
                }
                Image(systemName: "flag.checkered.2.crossed")
                    .foregroundColor(.red)
                Text(game.strHomeTeam)
                    .font(.headline)
                Spacer()
                if isLive {
                    Text("LIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }

            // Circuit location + race status
            HStack(spacing: 4) {
                if let circuit = game.circuitInfo {
                    Text("\(circuit.locality), \(circuit.country)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if game.circuitInfo != nil && game.displayStatus != nil {
                    Text("·")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let progress = game.displayStatus {
                    Text(progress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Mini leaderboard (top 3 drivers)
            let entries = Array(game.resolvedLeaderboard.prefix(3))
            if !entries.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 6) {
                            Text("\(entry.position)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            HeadshotView(url: entry.headshot, size: 24)
                            Text(entry.name)
                                .font(.subheadline)
                                .fontWeight(index == 0 ? .semibold : .regular)
                                .lineLimit(1)
                            if let constructor = entry.constructor {
                                Text(constructor)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(index == 0 ? "Leader" : (entry.gap ?? entry.score))
                                .font(.subheadline)
                                .fontWeight(index == 0 ? .semibold : .regular)
                                .foregroundColor(index == 0 ? .primary : .secondary)
                        }
                    }
                }
            } else if game.strAwayTeam != "TBD" {
                HStack {
                    Text(game.strAwayTeam)
                        .font(.subheadline)
                    Spacer()
                    if let score = game.intAwayScore {
                        Text(score)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            } else if let date = game.standardDate {
                GameTimeLabel(date: date, includeDate: true)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Session indicator strip
            if let sessions = game.sessions, !sessions.isEmpty {
                SessionIndicatorStrip(sessions: sessions)
            }

            // Action menu
            HStack {
                Spacer()
                Menu {
                    CalendarButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                    NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

/// Horizontal strip of session status pills (FP1, FP2, Qual, Race etc.)
struct SessionIndicatorStrip: View {
    let sessions: [EventSession]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(statusColor(for: session.status))
                            .frame(width: 6, height: 6)
                        Text(session.sessionType.isEmpty ? "?" : session.sessionType)
                            .font(.caption2)
                            .fontWeight(session.status == "in" ? .bold : .regular)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(session.status == "in" ? Color.red.opacity(0.15) : Color.gray.opacity(0.1))
                    )
                }
            }
        }
    }

    private func statusColor(for status: String?) -> Color {
        switch status {
        case "post": return .green
        case "in": return .red
        default: return .gray
        }
    }
}
