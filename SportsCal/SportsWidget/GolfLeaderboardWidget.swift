//
//  GolfLeaderboardWidget.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 4/12/26.
//

#if os(iOS)
import SwiftUI
import WidgetKit
import SportsCalModel

// MARK: - Timeline Entry

struct GolfLeaderboardEntry: TimelineEntry {
    let date: Date
    let tournamentName: String
    let venueName: String?
    let entries: [LeaderboardEntry]
    let status: String?
    let progress: String?
}

// MARK: - Provider

struct GolfLeaderboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> GolfLeaderboardEntry {
        GolfLeaderboardEntry(date: .now, tournamentName: "Golf Tournament", venueName: nil, entries: [], status: nil, progress: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (GolfLeaderboardEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GolfLeaderboardEntry>) -> Void) {
        Task {
            let entry = await buildEntry()
            let refreshDate = Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }

    private func buildEntry() async -> GolfLeaderboardEntry {
        // Try live endpoint first — it has active tournament leaderboards
        if let liveScore = try? await NetworkHandler.getLiveSnapshot(),
           let liveGolf = liveScore.golf?.events,
           let activeGame = liveGolf.first(where: { !$0.resolvedLeaderboard.isEmpty }) {
            let leaderboard = activeGame.resolvedLeaderboard
            return GolfLeaderboardEntry(
                date: .now,
                tournamentName: activeGame.strHomeTeam,
                venueName: activeGame.venueName,
                entries: Array(leaderboard.prefix(8)),
                status: activeGame.strStatus,
                progress: activeGame.strProgress
            )
        }

        // Fall back to snapshot / widget schedule for upcoming tournaments
        var games: [Game] = []
        if let snapshot = WidgetDataStore.readSnapshot() {
            games = snapshot.games
        }

        var golfGames = games.filter { $0.sportType == .golf }

        if golfGames.isEmpty {
            if let result = try? await NetworkHandler.getWidgetScheduleFor(sports: [.golf], limit: 5) {
                golfGames = result.games
            }
        }

        // Filter out cancelled/postponed events
        let cancelledStatuses: Set<String> = ["cancelled", "canceled", "postponed", "suspended", "abandoned", "match finished"]
        golfGames = golfGames.filter { game in
            guard let status = game.strStatus?.lowercased() else { return true }
            return !cancelledStatuses.contains(status)
        }

        golfGames.sort { ($0.standardDate ?? .distantFuture) < ($1.standardDate ?? .distantFuture) }

        let game = golfGames.first { !$0.resolvedLeaderboard.isEmpty } ?? golfGames.first

        guard let game else {
            return GolfLeaderboardEntry(date: .now, tournamentName: "No Tournament", venueName: nil, entries: [], status: nil, progress: nil)
        }

        let leaderboard = game.resolvedLeaderboard

        return GolfLeaderboardEntry(
            date: .now,
            tournamentName: game.strHomeTeam,
            venueName: game.venueName,
            entries: Array(leaderboard.prefix(8)),
            status: game.strStatus,
            progress: game.strProgress
        )
    }
}

// MARK: - View

struct GolfLeaderboardWidgetView: View {
    let entry: GolfLeaderboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "figure.golf")
                    .font(.system(size: 12))
                    .foregroundColor(.mint)

                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.tournamentName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if let venue = entry.venueName {
                        Text(venue)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let status = entry.status, !status.isEmpty, status != "NS", status != "pre" {
                    Text(entry.progress ?? status)
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 4)

            // Column headers
            HStack(spacing: 0) {
                Text("Pos")
                    .frame(width: 24, alignment: .leading)
                Text("Player")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Thru")
                    .frame(width: 36, alignment: .trailing)
                Text("Score")
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.system(size: 8, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)

            if entry.entries.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    if let status = entry.status?.lowercased(), status == "ns" || status == "not started" || status.isEmpty {
                        Text("Tournament hasn't started yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No leaderboard available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                // Leaderboard rows
                VStack(spacing: 0) {
                    ForEach(Array(entry.entries.enumerated()), id: \.offset) { index, player in
                        leaderboardRow(player: player, index: index)
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer()
        }
        .padding(8)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func leaderboardRow(player: LeaderboardEntry, index: Int) -> some View {
        HStack(spacing: 0) {
            // Position + movement
            HStack(spacing: 1) {
                Text("\(player.position)")
                    .font(.system(size: 10, weight: index == 0 ? .bold : .regular))
                    .frame(width: 16, alignment: .leading)
                if let movement = player.movement, movement != 0 {
                    Image(systemName: movement > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 6))
                        .foregroundColor(movement > 0 ? .green : .red)
                }
            }
            .frame(width: 24, alignment: .leading)

            // Player name
            Text(player.name)
                .font(.system(size: 10))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Thru hole
            if let thru = player.thruHole, !thru.isEmpty {
                Text(thru)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            } else {
                Text("-")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            // Score
            Text(player.score)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(scoreColor(player.score))
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(index == 0 ? Color.mint.opacity(0.08) : Color.clear)
        .cornerRadius(4)
    }

    private func scoreColor(_ score: String) -> Color {
        if score.hasPrefix("-") { return .red }
        if score == "E" { return .primary }
        if score.hasPrefix("+") { return .secondary }
        return .primary
    }
}

// MARK: - Widget

struct GolfLeaderboardWidget: Widget {
    let kind = "GolfLeaderboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GolfLeaderboardProvider()) { entry in
            GolfLeaderboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Golf Leaderboard")
        .description("Tournament leaderboard at a glance")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}
#endif
