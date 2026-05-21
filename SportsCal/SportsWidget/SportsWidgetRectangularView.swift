//
//  SportsWidgetRectangularView.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 12/7/22.
//

import SwiftUI
import SportsCalModel
import WidgetKit

struct SportsWidgetRectangularView: View {
    var entry: Provider.Entry
    var body: some View {
        VStack(spacing: 4) {
            if let game = entry.game?.first {
                if game.isIndividualSport {
                    // Individual sport: show sport icon + event name + leader
                    let sportType = game.sportType ?? .golf
                    HStack(spacing: 4) {
                        Image(systemName: sportType.widgetSystemImage)
                            .font(.caption2)
                            .widgetAccentable()
                        Text(game.strHomeTeam)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                    }
                    if isLive(game), let leader = game.resolvedLeaderboard.first {
                        Text("Leader: \(leader.name) \(leader.score)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else if let leader = game.resolvedLeaderboard.first {
                        Text("\(leader.name) \(leader.score)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if let statusText = game.displayStatus {
                        Text(statusText)
                            .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    } else if let date = game.standardDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    }
                } else if isLive(game) {
                    // Live team sport: show scores
                    let sportType = game.sportType ?? .basketball
                    HStack(spacing: 4) {
                        Image(systemName: sportType.widgetSystemImage)
                            .font(.caption2)
                            .widgetAccentable()
                        let awayAbbr = abbreviation(teamID: game.idAwayTeam, name: game.strAwayTeam)
                        let homeAbbr = abbreviation(teamID: game.idHomeTeam, name: game.strHomeTeam)
                        Text("\(awayAbbr) \(game.intAwayScore ?? "0") - \(homeAbbr) \(game.intHomeScore ?? "0")")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    if let progress = game.strProgress ?? game.strStatus {
                        Text(progress)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    // Show next game if available
                    if let next = entry.game?.dropFirst().first, !isLive(next) {
                        nextGameLine(next)
                    }
                } else if let homeTeamID = game.idHomeTeam, let homeTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: homeTeamID, teamName: game.strHomeTeam), let awayTeamID = game.idAwayTeam, let awayTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: awayTeamID, teamName: game.strAwayTeam) {
                    RectangularWidgetTeamView(longName: awayTeam.strTeam, isAway: true, data: entry.images?[awayTeamID])
                    RectangularWidgetTeamView(longName: homeTeam.strTeam, isAway: false, data: entry.images?[homeTeamID])
                    if let date = game.standardDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func nextGameLine(_ game: Game) -> some View {
        if game.isIndividualSport {
            Text("Next: \(game.strHomeTeam)")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            let awayAbbr = abbreviation(teamID: game.idAwayTeam, name: game.strAwayTeam)
            let homeAbbr = abbreviation(teamID: game.idHomeTeam, name: game.strHomeTeam)
            if let date = game.standardDate {
                Text("Next: \(awayAbbr) @ \(homeAbbr) \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func isLive(_ game: Game) -> Bool {
        guard let status = game.strStatus?.lowercased() else { return false }
        return !status.isEmpty &&
               status != "ft" && status != "aet" &&
               status != "not started" && status != "ns" &&
               game.intHomeScore != nil && game.intAwayScore != nil
    }

    private func abbreviation(teamID: String?, name: String) -> String {
        if let team = Team.getTeamInfoFrom(teams: entry.teams, teamID: teamID, teamName: name),
           let short = team.strTeamShort {
            return short
        }
        return String(name.prefix(3)).uppercased()
    }
}
