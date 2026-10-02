//
//  GolfLeaderboardWidget.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 4/12/26.
//

#if os(iOS)
import SwiftUI
import WidgetKit
import AppIntents
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

// MARK: - Intent

/// Which tour a leaderboard widget follows. The widget started out static; `.allTours`
/// keeps that behaviour — the biggest event this week.
enum GolfTourSelection: String, AppEnum {
    case allTours
    case pga
    case dpWorld
    case lpga
    case livGolf
    case championsTour
    case kornFerry

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Tour"
    }

    static var caseDisplayRepresentations: [GolfTourSelection: DisplayRepresentation] {
        [
            .allTours: "All Tours",
            .pga: "PGA Tour",
            .dpWorld: "DP World Tour",
            .lpga: "LPGA Tour",
            .livGolf: "LIV Golf",
            .championsTour: "PGA Tour Champions",
            .kornFerry: "Korn Ferry Tour",
        ]
    }

    var league: Leagues? {
        switch self {
        case .allTours: return nil
        case .pga: return .pga
        case .dpWorld: return .dpWorld
        case .lpga: return .lpga
        case .livGolf: return .livGolf
        case .championsTour: return .championsTour
        case .kornFerry: return .kornFerry
        }
    }
}

/// A picked tour shows regardless of the app's golf coverage or hidden competitions: the
/// widget has never been gated by those, and picking a tour is as explicit as a follow.
struct GolfLeaderboardIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Golf Leaderboard"
    static var description: IntentDescription = "Choose which tour's leaderboard to show"

    @Parameter(title: "Tour", default: .allTours)
    var tour: GolfTourSelection

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$tour) leaderboard")
    }
}

// MARK: - Provider

struct GolfLeaderboardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GolfLeaderboardEntry {
        GolfLeaderboardEntry(date: .now, tournamentName: "Golf Tournament", venueName: nil, entries: [], status: nil, progress: nil)
    }

    func snapshot(for configuration: GolfLeaderboardIntent, in context: Context) async -> GolfLeaderboardEntry {
        placeholder(in: context)
    }

    func timeline(for configuration: GolfLeaderboardIntent, in context: Context) async -> Timeline<GolfLeaderboardEntry> {
        let entry = await buildEntry(tour: configuration.tour.league)
        let refreshDate = Date().addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    /// `tour` nil means every tour.
    private func buildEntry(tour: Leagues?) async -> GolfLeaderboardEntry {
        // Try live endpoint first — it has active tournament leaderboards
        if let liveScore = try? await NetworkHandler.getLiveSnapshot(),
           let liveGolf = liveScore.golf?.events,
           let activeGame = WidgetTourFilter.featuredLiveGolfEvent(liveGolf, tour: tour) {
            return entry(for: activeGame)
        }

        // Fall back to snapshot / widget schedule for upcoming tournaments
        var game = WidgetTourFilter.scheduledGolfEvent(WidgetDataStore.readSnapshot()?.games ?? [], tour: tour)

        if game == nil {
            // The endpoint returns the soonest golf events across every tour, so ask for
            // more when only one tour's will do.
            let limit = tour == nil ? 5 : 30
            if let result = try? await NetworkHandler.getWidgetScheduleFor(sports: [.golf], limit: limit) {
                game = WidgetTourFilter.scheduledGolfEvent(result.games, tour: tour)
            }
        }

        guard let game else {
            let name = tour.map { "No \($0.leagueName) Event" } ?? "No Tournament"
            return GolfLeaderboardEntry(date: .now, tournamentName: name, venueName: nil, entries: [], status: nil, progress: nil)
        }

        return entry(for: game)
    }

    private func entry(for game: Game) -> GolfLeaderboardEntry {
        GolfLeaderboardEntry(
            date: .now,
            tournamentName: game.strHomeTeam,
            venueName: game.venueName,
            entries: Array(game.resolvedLeaderboard.prefix(8)),
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
        .containerBackground(for: .widget) { WidgetBackground() }
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
        // Same kind as when this was a StaticConfiguration, so placed widgets carry over
        // with the intent's defaults.
        AppIntentConfiguration(kind: kind, intent: GolfLeaderboardIntent.self, provider: GolfLeaderboardProvider()) { entry in
            GolfLeaderboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Golf Leaderboard")
        .description("Tournament leaderboard at a glance")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}
#endif
