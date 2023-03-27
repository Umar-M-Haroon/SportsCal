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
            if #available(iOSApplicationExtension 16.0, *) {
                AccessoryWidgetBackground()
            }
            VStack(spacing: 0) {
                if let game = entry.game?.first {
                    if let homeTeamID = game.idHomeTeam, let homeTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: homeTeamID), let awayTeamID = game.idAwayTeam, let awayTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: awayTeamID) {
                        HStack(spacing: 2) {
                            TinyWidgetTeamView(shortName: awayTeam.strTeamShort, longName: String(awayTeam.strTeam?.prefix(3) ?? "") , isAway: true, data: entry.images?[awayTeamID])
                            TinyWidgetTeamView(shortName: homeTeam.strTeamShort, longName: String(homeTeam.strTeam?.prefix(3) ?? "") , isAway: false, data: entry.images?[homeTeamID])
                        }
                        if let date = game.isoDate {
                            if Calendar.current.isDateInToday(date) {
                                Text(date.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 6, weight: .semibold))
                            } else {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 6, weight: .semibold))
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
    }
}
