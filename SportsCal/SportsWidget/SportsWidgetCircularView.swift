//
//  SportsWidgetCircularView.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 12/7/22.
//

import SwiftUI
import SportsCalModel
import WidgetKit

struct SportsWidgetCircularView: View {
    var entry: Provider.Entry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                if let game = entry.game?.first {
                    if isLive(game) {
                        liveView(game)
                    } else if game.isIndividualSport {
                        // Individual sport: show sport icon + event name
                        let sportType = game.sportType ?? .golf
                        Image(systemName: sportType.widgetSystemImage)
                            .font(.system(size: 14))
                            .widgetAccentable()
                        Text(game.strHomeTeam)
                            .font(.system(size: 7, design: .rounded).weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    } else if let homeTeamID = game.idHomeTeam, let homeTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: homeTeamID, teamName: game.strHomeTeam), let awayTeamID = game.idAwayTeam, let awayTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: awayTeamID, teamName: game.strAwayTeam) {
                        HStack(spacing: 2) {
                            TinyWidgetTeamView(shortName: awayTeam.strTeamShort, longName: Team.shortCode(strTeamShort: nil, name: awayTeam.strTeam ?? "") , isAway: true, data: entry.images?[awayTeamID])
                            TinyWidgetTeamView(shortName: homeTeam.strTeamShort, longName: Team.shortCode(strTeamShort: nil, name: homeTeam.strTeam ?? "") , isAway: false, data: entry.images?[homeTeamID])
                        }
                        if let date = game.standardDate {
                            Group {
                                if Calendar.current.isDateInToday(date) {
                                    Text(date.formatted(date: .omitted, time: .shortened))
                                } else {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                }
                            }
                            .font(.system(size: 6, design: .monospaced).weight(.semibold))
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Live View (scores when game is live)

    @ViewBuilder
    private func liveView(_ game: Game) -> some View {
        if game.isIndividualSport {
            // Individual sport live: sport icon + leader score
            let sportType = game.sportType ?? .golf
            Image(systemName: sportType.widgetSystemImage)
                .font(.system(size: 14))
                .widgetAccentable()
            if let leader = game.resolvedLeaderboard.first {
                Text(leader.score)
                    .font(.system(size: 12, design: .rounded).weight(.heavy))
                    .monospacedDigit()
            }
        } else {
            // Team sport live: stacked scores with accent divider
            VStack(spacing: 1) {
                Text(game.intAwayScore ?? "0")
                    .font(.system(size: 16, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                Rectangle()
                    .frame(width: 20, height: 1)
                    .widgetAccentable()
                Text(game.intHomeScore ?? "0")
                    .font(.system(size: 16, design: .rounded).weight(.heavy))
                    .monospacedDigit()
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
}
