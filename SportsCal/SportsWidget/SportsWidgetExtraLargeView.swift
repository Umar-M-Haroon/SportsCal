//
//  SportsWidgetExtraLargeView.swift
//  SportsWidget
//
//  watchOS Ultra-only accessoryExtraLarge complication.
//  Room for 3 game rows: scores for live/completed, "@ time" for upcoming.
//

#if os(watchOS)
import SwiftUI
import WidgetKit
import SportsCalModel

struct SportsWidgetExtraLargeView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(spacing: 4) {
            if let games = entry.game, !games.isEmpty {
                ForEach(Array(games.prefix(3).enumerated()), id: \.offset) { _, game in
                    if game.isIndividualSport {
                        tournamentRow(game)
                    } else {
                        teamRow(game)
                    }
                    if game.id != games.prefix(3).last?.id {
                        Divider()
                    }
                }
            } else {
                Text("No upcoming games")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }

    // MARK: - Team Sport Row

    @ViewBuilder
    private func teamRow(_ game: Game) -> some View {
        if isLive(game) || game.isCompleted == true {
            // Live or final: show scores
            HStack(spacing: 0) {
                let awayAbbr = abbreviation(teamID: game.idAwayTeam, name: game.strAwayTeam)
                let homeAbbr = abbreviation(teamID: game.idHomeTeam, name: game.strHomeTeam)

                Text(awayAbbr)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, alignment: .leading)
                Text(game.intAwayScore ?? "0")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(width: 24)

                Spacer()

                if isLive(game), let progress = game.strProgress ?? game.strStatus {
                    Text(progress)
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                } else {
                    Text("Final")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(game.intHomeScore ?? "0")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(width: 24)
                Text(homeAbbr)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, alignment: .trailing)
            }
        } else {
            // Upcoming
            HStack {
                let awayAbbr = abbreviation(teamID: game.idAwayTeam, name: game.strAwayTeam)
                let homeAbbr = abbreviation(teamID: game.idHomeTeam, name: game.strHomeTeam)

                Text("\(awayAbbr) @ \(homeAbbr)")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if let date = game.standardDate {
                    Text(date, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Tournament/Race Row

    @ViewBuilder
    private func tournamentRow(_ game: Game) -> some View {
        let sportType = game.sportType ?? .golf
        HStack(spacing: 4) {
            Image(systemName: sportType.widgetSystemImage)
                .font(.system(size: 10))
                .foregroundStyle(sportType.widgetColor)
            Text(game.strHomeTeam)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            Spacer()
            if let leader = game.resolvedLeaderboard.first {
                Text("\(leader.name) \(leader.score)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let date = game.standardDate {
                Text(date, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func isLive(_ game: Game) -> Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty &&
               status != "ft" && status != "aet" &&
               status != "not started" && status != "ns" &&
               game.intHomeScore != nil && game.intAwayScore != nil
    }

    private func abbreviation(teamID: String?, name: String) -> String {
        if let id = teamID,
           let team = Team.getTeamInfoFrom(teams: entry.teams, teamID: id),
           let short = team.strTeamShort {
            return short
        }
        return String(name.prefix(3)).uppercased()
    }
}
#endif
