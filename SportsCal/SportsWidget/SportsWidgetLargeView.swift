//
//  SportsWidgetLargeView.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 12/7/22.
//

import SwiftUI
import SportsCalModel

struct SportsWidgetLargeView: View {
    var entry: Provider.Entry

    private var dayOffset: Int {
        UserDefaults(suiteName: "group.Komodo.SportsCal")?.integer(forKey: "widgetDayOffset") ?? 0
    }

    private var displayDate: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(spacing: 6) {
            // Header with day navigation
            HStack(spacing: 6) {
                Button(intent: NavigateDayIntent(dayOffset: dayOffset - 1)) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    Text(displayDate.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.red)
                    Text(displayDate.formatted(.dateTime.month(.abbreviated).day(.twoDigits)))
                        .font(.subheadline)
                        .bold()
                }

                Button(intent: NavigateDayIntent(dayOffset: dayOffset + 1)) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                if dayOffset != 0 {
                    Button(intent: NavigateDayIntent(dayOffset: 0)) {
                        Text("Today")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }

                Text("Scoreboard")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            // Multi-game grid (2x3 = 6 games)
            if let games = entry.game, !games.isEmpty {
                let displayGames = Array(games.prefix(6))
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ], spacing: 6) {
                    ForEach(displayGames) { game in
                        gameCellView(game: game)
                    }
                }
            } else {
                Spacer()
                Text("No upcoming games")
                    .foregroundColor(.secondary)
                Spacer()
            }

            Spacer()
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
            WidgetRaceCell(game: game, compact: false)
        } else if game.isIndividualSport {
            WidgetTournamentCell(game: game, compact: false)
        } else {
            LargeCompactGameCell(game: game, teams: entry.teams, images: entry.images)
        }
    }
}

// Larger compact cell for the large widget
struct LargeCompactGameCell: View {
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
        VStack(spacing: 4) {
            // Sport icon header
            HStack(spacing: 4) {
                Image(systemName: sportType.widgetSystemImage)
                    .font(.system(size: 10))
                    .foregroundColor(sportType.widgetColor)
                Spacer()
                // Time or status
                if let status = game.strStatus, !status.isEmpty, status != "NS" {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 5, height: 5)
                        Text(game.strProgress ?? status)
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                } else if let gameDate = game.standardDate {
                    Text(gameDate.formatToTime() ?? "")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                #if os(iOS)
                if isLive, let gameID = game.idEvent {
                    Button(intent: FollowGameIntent(gameID: gameID, homeTeam: game.strHomeTeam, awayTeam: game.strAwayTeam)) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }

            // Teams row with scores
            HStack(spacing: 6) {
                teamColumn(teamID: game.idAwayTeam, teamName: game.strAwayTeam, score: game.intAwayScore, isWinning: isAwayWinning())

                Text("vs")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                teamColumn(teamID: game.idHomeTeam, teamName: game.strHomeTeam, score: game.intHomeScore, isWinning: isHomeWinning())
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(widgetCellBackground.opacity(0.5))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func teamColumn(teamID: String?, teamName: String, score: String?, isWinning: Bool) -> some View {
        VStack(spacing: 2) {
            if let id = teamID, let data = images?[id], let image = widgetImage(from: data) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "sportscourt")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.secondary)
            }

            Text(getTeamAbbrev(teamID: teamID, teamName: teamName))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            if let scoreStr = score, let scoreInt = Int(scoreStr) {
                Text("\(scoreInt)")
                    .font(.system(size: 14, weight: isWinning ? .bold : .regular))
                    .foregroundColor(isWinning ? .primary : .secondary)
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

    private func isHomeWinning() -> Bool {
        guard let homeScore = Int(game.intHomeScore ?? ""),
              let awayScore = Int(game.intAwayScore ?? "") else { return false }
        return homeScore > awayScore
    }

    private func isAwayWinning() -> Bool {
        guard let homeScore = Int(game.intHomeScore ?? ""),
              let awayScore = Int(game.intAwayScore ?? "") else { return false }
        return awayScore > homeScore
    }
}
