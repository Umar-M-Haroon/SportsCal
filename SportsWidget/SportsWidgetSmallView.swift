//
//  SportsWidgetSmallView.swift
//  SportsWidgetExtension
//
//  Created by Umar Haroon on 12/7/22.
//

import SwiftUI
import WidgetKit
import SportsCalModel

struct SportsWidgetSmallView: View {
    var entry: Provider.Entry
    var body: some View {
        VStack(spacing: 4) {
            VStack {
                Text(Date().formatted(.dateTime.weekday(.abbreviated)))
                    .bold()
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                HStack {
                    Text(Date().formatted(.dateTime.month(.abbreviated).day(.twoDigits)))
                        .bold()
                    Spacer()
                    Text("Up Next")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(alignment: .leading)
                }
            }
            .padding(.bottom, 4)
            if let games = entry.game, !games.isEmpty {
                ForEach(Array(games.prefix(through: 1))) { game in
                    SportsView(home: game.strHomeTeam, away: game.strAwayTeam, type: SportType.basketball, color: .orange, gameDate: game.strTimestamp ?? "")
                }
            } else {
                Spacer()
                Text("No upcoming games")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding([.leading, .trailing, .bottom], 8)
    }
}
