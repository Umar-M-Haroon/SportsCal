//
//  RaceScoreView.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/9/26.
//

import SwiftUI
import SportsCalModel

/// Displays a race weekend (F1, NASCAR) with a mini leaderboard of the top 3
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
        // A series beyond F1 says where the race stands ("Caution · Lap 92/267", "Hour 6
        // of 10"), which the session strip can't.
        if game.isMotorsportSeries, isLive, let progress = game.strProgress {
            return progress
        }
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

    /// One VoiceOver sentence: "Monaco Grand Prix, live, Monte Carlo, Monaco,
    /// 1 Verstappen, leader, 2 Norris, +1.2s, 3 …".
    private var accessibilityLabel: String {
        var parts = [game.strHomeTeam]
        if isLive { parts.append("live") }
        if let circuit = game.circuitInfo { parts.append("\(circuit.locality), \(circuit.country)") }
        else if let venue = game.venueName, game.isMotorsportSeries { parts.append(venue) }
        if let status = raceStatusText { parts.append(status) }
        let entries = game.resolvedLeaderboard.prefix(3)
        if !entries.isEmpty {
            for (index, entry) in entries.enumerated() {
                let gap = index == 0 ? "leader" : (entry.gap ?? entry.score)
                parts.append("\(entry.position) \(entry.name), \(gap)")
            }
        } else if game.strAwayTeam != "TBD" {
            parts.append([game.strAwayTeam, game.intAwayScore].compactMap { $0 }.joined(separator: " "))
        } else if let date = game.standardDate {
            parts.append(GameRowAccessibility.when(date))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Summary reads as one VoiceOver element; the session strip and the action
            // menu stay separate so they remain navigable/operable.
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
                    if game.isMotorsportSeries, let tag = game.racingSeries?.racingShortName {
                        Text(tag)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4)))
                    }
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
                    } else if game.isMotorsportSeries, let venue = game.venueName {
                        Text(venue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if (game.circuitInfo != nil || (game.isMotorsportSeries && game.venueName != nil)) && raceStatusText != nil {
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
                                if let car = entry.stockCar {
                                    CarNumberBadge(number: car.carNumber, manufacturer: car.manufacturer, size: 20)
                                } else {
                                    HeadshotView(url: entry.headshot, size: 24)
                                }
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
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(accessibilityLabel))

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
                    #if canImport(ActivityKit) && os(iOS)
                    if isLive, let teams = viewModel.getTeams(for: game) {
                        LiveActivityFollowMenu(game: game, homeTeam: teams.home, awayTeam: teams.away)
                            .environment(viewModel)
                    }
                    #endif
                    CalendarButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                    NotifyButton(shouldShowSportsCalProAlert: $shouldShowSportsCalProAlert, sheetType: $sheetType, game: game)
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("Actions")
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
    /// Done-checkmark glyph size; 8pt at the default Dynamic Type size.
    @ScaledMetric(relativeTo: .caption2) private var checkmarkSize: CGFloat = 8

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
            Text(session.shortName)
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
                .font(.system(size: checkmarkSize, weight: .bold))
                .foregroundStyle(.green)
        case "in":
            Circle().fill(.red).frame(width: 6, height: 6)
        default:
            Circle()
                .fill(isFocused ? Color.app(.racing) : Color.gray.opacity(0.5))
                .frame(width: 6, height: 6)
        }
    }

    /// For a completed session that has a ranked result (qualifying / sprint / race), show the
    /// leader's surname so the green check has meaning. Practice sessions get no hint.
    private func resultHint(for session: EventSession) -> String? {
        guard session.status == "post",
              let leader = session.leaderboard.first else { return nil }
        switch session.sessionType.lowercased() {
        case "qual", "qualifying", "sprint qualifying", "sprint shootout", "sq", "ss",
             "sprint", "sr", "race", "r":
            return leader.name.split(separator: " ").last.map(String.init) ?? leader.name
        default:
            return nil
        }
    }
}
