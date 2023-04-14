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
                if let homeTeamID = game.idHomeTeam, let homeTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: homeTeamID), let awayTeamID = game.idAwayTeam, let awayTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: awayTeamID) {
                    RectangularWidgetTeamView(longName: awayTeam.strTeam, isAway: true, data: entry.images?[awayTeamID])
                    RectangularWidgetTeamView(longName: homeTeam.strTeam, isAway: false, data: entry.images?[homeTeamID])
                    if let date = game.standardDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
            }
        }
    }
}

