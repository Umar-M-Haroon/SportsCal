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
    var body: some View {
        VStack {
            VStack {
                Text(Date.currentDateToDayString())
                    .bold()
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                
                HStack {
                    Text(Date.currentDateToNumberString())
                        .bold()
                    Spacer()
                    Text("Up Next")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(alignment: .leading)
                        .padding([.leading], 8)
                }
            }
            VStack(spacing: 4) {
                if let games = entry.game {
                    if games.isEmpty {
                        Text("No upcoming games")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(games.prefix(upTo: 2))) { game in
                            if let homeTeamID = game.idHomeTeam, let homeTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: homeTeamID), let awayTeamID = game.idAwayTeam, let awayTeam = Team.getTeamInfoFrom(teams: entry.teams, teamID: awayTeamID) {
                                HStack {
                                    //                                    HStack {
                                    WidgetTeamView(shortName: awayTeam.strTeamShort, longName: awayTeam.strTeam, isAway: true, data: entry.images?[awayTeamID])
                                    Spacer()
                                    VStack(alignment: .center, spacing: 0) {
                                        if let isoDate = game.isoDate {
                                            
                                            Text(isoDate.formatToDate(dateFormat: "d MMM") ?? "")
                                                .font(.system(.subheadline, design: .monospaced))
                                                .fontWeight(.medium)
                                            //                                                    .accessibilityValue(accessibilityLabel)
                                            //                                                    .accessibilityLabel(accessibilityLabel)
                                                .foregroundColor(.secondary)
                                        }
                                        if let isoDate = game.isoDate,
                                           let isoString = isoDate.formatToTime() {
                                            Text(isoString)
                                                .font(.system(.subheadline, design: .monospaced))
                                                .fontWeight(.medium)
                                                .foregroundColor(Color(UIColor.secondaryLabel))
                                        }
                                        //
                                    }
                                    Spacer()
                                    //                                        .frame(maxWidth: .infinity)
                                    WidgetTeamView(shortName: homeTeam.strTeamShort, longName: homeTeam.strTeam, isAway: false, data: entry.images?[homeTeamID])
                                    
                                    //                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("No upcoming games")
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(8)
    }
}

