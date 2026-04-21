//
//  F1WeekendWidget.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 4/12/26.
//

#if os(iOS)
import SwiftUI
import WidgetKit
import SportsCalModel

// MARK: - Timeline Entry

struct F1WeekendEntry: TimelineEntry {
    let date: Date
    let raceName: String
    let locality: String?
    let sessions: [EventSession]
}

// MARK: - Provider

struct F1WeekendProvider: TimelineProvider {
    func placeholder(in context: Context) -> F1WeekendEntry {
        F1WeekendEntry(date: .now, raceName: "Grand Prix", locality: nil, sessions: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (F1WeekendEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<F1WeekendEntry>) -> Void) {
        Task {
            let entry = await buildEntry()
            let refreshDate = Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }

    private func buildEntry() async -> F1WeekendEntry {
        // Try live endpoint first — it has active race sessions
        if let liveScore = try? await NetworkHandler.getLiveSnapshot(),
           let liveRacing = liveScore.racing?.events,
           let activeRace = liveRacing.first(where: { $0.sessions != nil && !($0.sessions?.isEmpty ?? true) }),
           let sessions = activeRace.sessions {
            return F1WeekendEntry(
                date: .now,
                raceName: activeRace.strHomeTeam,
                locality: activeRace.circuitInfo?.locality,
                sessions: sessions
            )
        }

        // Fall back to snapshot / widget schedule for upcoming races
        var games: [Game] = []
        if let snapshot = WidgetDataStore.readSnapshot() {
            games = snapshot.games
        }

        var racingGames = games
            .filter { $0.sportType == .racing && $0.sessions != nil && !($0.sessions?.isEmpty ?? true) }

        if racingGames.isEmpty {
            if let result = try? await NetworkHandler.getWidgetScheduleFor(sports: [.racing], limit: 5) {
                racingGames = result.games
                    .filter { $0.sessions != nil && !($0.sessions?.isEmpty ?? true) }
            }
        }

        // Filter out cancelled/postponed races
        let cancelledStatuses: Set<String> = ["cancelled", "canceled", "postponed", "suspended", "abandoned"]
        racingGames = racingGames.filter { game in
            guard let status = game.strStatus?.lowercased() else { return true }
            return !cancelledStatuses.contains(status)
        }

        racingGames.sort { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }

        let now = Date()
        let activeRace = racingGames.first { game in
            guard let sessions = game.sessions else { return false }
            return sessions.contains { session in
                if let status = session.status?.lowercased(), status == "in" { return true }
                if let dateStr = session.date,
                   let sessionDate = DateFormatters.isoFormatter.date(from: dateStr),
                   sessionDate > now { return true }
                return false
            }
        } ?? racingGames.first

        guard let race = activeRace, let sessions = race.sessions else {
            return F1WeekendEntry(date: .now, raceName: "No F1 Race", locality: nil, sessions: [])
        }

        return F1WeekendEntry(
            date: .now,
            raceName: race.strHomeTeam,
            locality: race.circuitInfo?.locality,
            sessions: sessions
        )
    }
}

// MARK: - View

struct F1WeekendWidgetView: View {
    let entry: F1WeekendEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.system(size: 12))
                    .foregroundColor(.red)

                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.raceName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if let locality = entry.locality {
                        Text(locality)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 4)

            if entry.sessions.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No F1 race scheduled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                // Session list
                VStack(spacing: 3) {
                    ForEach(Array(entry.sessions.enumerated()), id: \.offset) { _, session in
                        sessionRow(session)
                    }
                }
                .padding(.horizontal, 4)

                Spacer()
            }
        }
        .padding(8)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func sessionRow(_ session: EventSession) -> some View {
        let sessionState = self.sessionState(session)

        HStack(spacing: 6) {
            // Status indicator
            Group {
                switch sessionState {
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .live:
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                case .upcoming:
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 10))
            .frame(width: 14)

            // Session name
            Text(shortSessionName(session.sessionType))
                .font(.system(size: 10, weight: sessionState == .live ? .bold : .regular))
                .foregroundColor(sessionState == .live ? .primary : .secondary)
                .frame(width: 40, alignment: .leading)

            // Date/time
            if let dateStr = session.date, let date = DateFormatters.isoFormatter.date(from: dateStr) {
                if sessionState == .upcoming {
                    Text(date, style: .relative)
                        .font(.system(size: 9))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                } else {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(sessionState == .live ? Color.red.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }

    private enum SessionState {
        case completed, live, upcoming
    }

    private func sessionState(_ session: EventSession) -> SessionState {
        if let status = session.status?.lowercased() {
            if status == "in" { return .live }
            if status == "post" { return .completed }
        }
        if let dateStr = session.date,
           let date = DateFormatters.isoFormatter.date(from: dateStr),
           date < Date() {
            return .completed
        }
        return .upcoming
    }

    private func shortSessionName(_ type: String) -> String {
        switch type.lowercased() {
        case "fp1", "practice 1": return "FP1"
        case "fp2", "practice 2": return "FP2"
        case "fp3", "practice 3": return "FP3"
        case "qual", "qualifying": return "Qual"
        case "sprint": return "Sprint"
        case "race": return "Race"
        default: return type
        }
    }
}

// MARK: - Widget

struct F1WeekendWidget: Widget {
    let kind = "F1WeekendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: F1WeekendProvider()) { entry in
            F1WeekendWidgetView(entry: entry)
        }
        .configurationDisplayName("F1 Weekend")
        .description("Race weekend session schedule")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
#endif
