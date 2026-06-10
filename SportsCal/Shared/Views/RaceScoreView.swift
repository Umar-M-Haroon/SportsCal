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

    private var hasSessionStrip: Bool {
        !(game.sessions ?? []).isEmpty
    }

    /// Caption status next to the circuit location. When the session strip is shown it carries the
    /// live/next/done detail, so the caption only summarises the weekend ("Final" when the race is
    /// done) to avoid stating the same session twice. Without a strip, fall back to the full
    /// session-aware text ("Race · Sun 2:00 PM").
    private var raceStatusText: String? {
        if hasSessionStrip {
            if case .finished = game.raceWeekendStatus { return "Final" }
            return nil
        }
        switch game.raceWeekendStatus {
        case .live(let name):
            return "\(name) LIVE"
        case .finished:
            return "Final"
        case .upcoming(let label, let date):
            return "\(label) · \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
        case .none:
            return game.displayStatus
        }
    }

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
                if game.circuitInfo != nil && raceStatusText != nil {
                    Text("·")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let progress = raceStatusText {
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
                SessionIndicatorStrip(
                    sessions: sessions,
                    focusedSessionType: game.liveSessionEntry?.sessionType
                        ?? game.nextUpcomingSession?.sessionType
                )
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

/// Horizontal strip of session pills (FP1, FP2, Quali, Race…). Each pill is state-aware:
/// completed sessions show a result hint (pole sitter / winner), the live or next session is
/// highlighted, and later sessions stay muted — so a finished qualifying no longer reads as an
/// unexplained green dot or an "inconclusive" weekend.
struct SessionIndicatorStrip: View {
    let sessions: [EventSession]
    /// The session to emphasise: the live one if any, otherwise the next upcoming.
    var focusedSessionType: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                    pill(for: session)
                }
            }
        }
    }

    @ViewBuilder
    private func pill(for session: EventSession) -> some View {
        let isLive = session.status == "in"
        let isDone = session.status == "post"
        let isFocused = focusedSessionType != nil
            && session.sessionType == focusedSessionType
        let accent = Color.app(.racing)

        HStack(spacing: 4) {
            statusGlyph(for: session)
            Text(shortLabel(session.sessionType))
                .font(.caption2)
                .fontWeight(isLive || isFocused ? .bold : .regular)
            if isLive {
                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.red)
            } else if let hint = resultHint(for: session) {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isDone && !isFocused ? Color.secondary : Color.primary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(
                isLive ? Color.red.opacity(0.15)
                    : isFocused ? accent.opacity(0.15)
                    : Color.gray.opacity(0.1)
            )
        )
        .overlay(
            Capsule().strokeBorder(
                isFocused && !isLive ? accent.opacity(0.6) : .clear,
                lineWidth: 1
            )
        )
    }

    /// Leading glyph: green check (done), red dot (live), accent dot (next/focused), else faint dot.
    @ViewBuilder
    private func statusGlyph(for session: EventSession) -> some View {
        let isFocused = session.sessionType == focusedSessionType
        switch session.status {
        case "post":
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.green)
        case "in":
            Circle().fill(.red).frame(width: 6, height: 6)
        default:
            Circle()
                .fill(isFocused ? Color.app(.racing) : Color.gray.opacity(0.5))
                .frame(width: 6, height: 6)
        }
    }

    /// Tidy short label for the pill (keeps it compact: "Quali" reads better than "Qual").
    private func shortLabel(_ type: String) -> String {
        switch type.lowercased() {
        case "qual", "qualifying": return "Quali"
        case "sprint qualifying", "sprint shootout", "sq", "ss": return "Sprint Q"
        case "": return "?"
        default: return type
        }
    }

    /// For a completed session that has a ranked result (qualifying / sprint / race), show the
    /// leader's surname so the green check has meaning. Practice sessions get no hint.
    private func resultHint(for session: EventSession) -> String? {
        guard session.status == "post",
              let leader = session.leaderboard.first else { return nil }
        switch session.sessionType.lowercased() {
        case "qual", "qualifying", "sprint qualifying", "sprint shootout", "sq", "ss",
             "sprint", "race", "r":
            return leader.name.split(separator: " ").last.map(String.init) ?? leader.name
        default:
            return nil
        }
    }
}
