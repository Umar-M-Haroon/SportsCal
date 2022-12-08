//
//  SportsWidgetCircularView.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 12/7/22.
//

import SwiftUI
import SportsCalModel
struct SportsWidgetCircularView: View {
    var entry: Provider.Entry
    var body: some View {
        VStack(spacing: 0) {
            if let game = entry.game?.first {
                if let homeTeamID = game.idHomeTeam, let homeTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: homeTeamID), let awayTeamID = game.idAwayTeam, let awayTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: awayTeamID) {
                    HStack(spacing: 2) {
                        TinyWidgetTeamView(shortName: awayTeam.strTeamShort, longName: String(awayTeam.strTeam?.prefix(3) ?? "") , isAway: true, data: entry.images?[awayTeamID])
                        TinyWidgetTeamView(shortName: homeTeam.strTeamShort, longName: String(homeTeam.strTeam?.prefix(3) ?? "") , isAway: false, data: entry.images?[homeTeamID])
                    }
                    if let isoDate = game.getDate(dateFormatter: DateFormatters.backupISOFormatter, isoFormatter: DateFormatters.isoFormatter),
                       let isoString = isoDate.formatToTime() {
                        Text(isoString)
                            .font(.system(size: 8))
//                            .fontWeight(.medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    
                }
            }
        }
    }
}
