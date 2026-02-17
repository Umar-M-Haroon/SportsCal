//
//  SportsWidgetMediumView.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 12/7/22.
//

import SwiftUI
import WidgetKit
import SportsCalModel

struct SportsWidgetMediumView: View {
    var entry: Provider.Entry

    private var dayOffset: Int {
        UserDefaults(suiteName: "group.Komodo.SportsCal")?.integer(forKey: "widgetDayOffset") ?? 0
    }

    private var displayDate: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(spacing: 4) {
            // Header with day navigation
            HStack(spacing: 6) {
                Button(intent: NavigateDayIntent(dayOffset: dayOffset - 1)) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    Text(displayDate.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption)
                        .bold()
                        .foregroundColor(.red)
                    Text(displayDate.formatted(.dateTime.month(.abbreviated).day(.twoDigits)))
                        .font(.caption)
                        .bold()
                }

                Button(intent: NavigateDayIntent(dayOffset: dayOffset + 1)) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                if dayOffset != 0 {
                    Button(intent: NavigateDayIntent(dayOffset: 0)) {
                        Text("Today")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }

                Text("Scoreboard")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            // Compact multi-game grid (2x2 = 4 games)
            if let games = entry.game, !games.isEmpty {
                let displayGames = Array(games.prefix(4))
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 4),
                    GridItem(.flexible(), spacing: 4)
                ], spacing: 4) {
                    ForEach(displayGames) { game in
                        gameCellView(game: game)
                    }
                }
            } else {
                Spacer()
                Text("No upcoming games")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(8)
        .widgetURL(widgetDeepLink)
    }

    private var widgetDeepLink: URL? {
        guard let game = entry.game?.first, let id = game.idEvent else { return nil }
        return URL(string: "sportscal://game/\(id)")
    }

    @ViewBuilder
    private func gameCellView(game: Game) -> some View {
        if game.isRace {
            WidgetRaceCell(game: game, compact: true)
        } else if game.isIndividualSport {
            WidgetTournamentCell(game: game, compact: true)
        } else {
            CompactGameCell(game: game, teams: entry.teams, images: entry.images)
        }
    }
}

// Compact cell for showing a single game in the grid
struct CompactGameCell: View {
    let game: Game
    let teams: [Team]
    let images: [String: Data]?

    private var sportType: SportType { game.sportType ?? .basketball }

    private var isLive: Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty && status != "ft" && status != "aet" && status != "not started" && status != "ns"
            && game.intHomeScore != nil && game.intAwayScore != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: sportType.widgetSystemImage)
                .font(.system(size: 10))
                .foregroundColor(sportType.widgetColor)
                .frame(width: 12)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                // Teams row
                HStack(spacing: 4) {
                    compactTeamView(teamID: game.idAwayTeam, teamName: game.strAwayTeam, score: game.intAwayScore)
                    Text("@")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    compactTeamView(teamID: game.idHomeTeam, teamName: game.strHomeTeam, score: game.intHomeScore)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Time or status + follow button
                HStack(spacing: 4) {
                    if let status = game.strStatus, !status.isEmpty, status != "NS" {
                        Text(game.strProgress ?? status)
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    } else if let gameDate = game.standardDate {
                        Text(gameDate.formatToTime() ?? "")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    #if os(iOS)
                    if isLive, let gameID = game.idEvent {
                        Spacer()
                        Button(intent: FollowGameIntent(gameID: gameID, homeTeam: game.strHomeTeam, awayTeam: game.strAwayTeam)) {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    #endif
                }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(widgetCellBackground.opacity(0.5))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func compactTeamView(teamID: String?, teamName: String, score: String?) -> some View {
        HStack(spacing: 2) {
            if let id = teamID, let data = images?[id], let image = widgetImage(from: data) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
            }

            Text(getTeamAbbrev(teamID: teamID, teamName: teamName))
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)

            if let scoreStr = score, let scoreInt = Int(scoreStr) {
                Text("\(scoreInt)")
                    .font(.system(size: 10, weight: .bold))
            }
        }
    }

    private func getTeamAbbrev(teamID: String?, teamName: String) -> String {
        if let id = teamID,
           let team = Team.getTeamInfoFrom(teams: teams, teamID: id),
           let shortName = team.strTeamShort {
            return shortName
        }
        let name = teamName.trimmingCharacters(in: .whitespaces)
        if name.count >= 3 {
            return String(name.prefix(3)).uppercased()
        }
        return name.uppercased()
    }
}
