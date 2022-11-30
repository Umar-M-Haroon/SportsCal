//
//  LiveSportActivityWidget.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/28/22.
//

import SwiftUI
import WidgetKit
import UIKit
#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct LiveSportActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveSportActivityAttributes.self) { context in
            HStack {
                if let awayID = context.attributes.awayID, let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(awayID) {
                    IndividualTeamView(shortName: context.attributes.awayTeam, longName: context.attributes.awayTeam, score: context.state.awayScore, isWinning: context.state.awayScore > context.state.homeScore, isAway: true, data: try? Data(contentsOf: fileURL))
                } else {
                    Text("no file url")
                    IndividualTeamView(shortName: context.attributes.awayTeam, longName: context.attributes.awayTeam, score: -1, isWinning: context.state.awayScore > context.state.homeScore, isAway: true)
                }
                if let formatted = GameFormatter().string(for: (context.attributes, context.state)) {
                    Text(formatted)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if let homeID = context.attributes.homeID, let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(homeID) {
                    IndividualTeamView(shortName: context.attributes.homeTeam, longName: context.attributes.homeTeam, score: context.state.homeScore, isWinning: context.state.homeScore > context.state.awayScore, isAway: false, data: try? Data(contentsOf: fileURL))
                } else {
                    IndividualTeamView(shortName: context.attributes.homeTeam, longName: context.attributes.homeTeam, score: context.state.homeScore, isWinning: context.state.homeScore > context.state.awayScore, isAway: false)
                }
            }
            .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        if let awayID = context.attributes.awayID, let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(awayID),
                           let data = try? Data(contentsOf: fileURL),
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 35, height: 35)
                        }
                        VStack {
                            if context.state.awayScore > context.state.homeScore {
                                Text("\(context.state.awayScore)")
                                    .font(.system(size: 24))
                                    .fontWeight(.heavy)
                            } else {
                                Text("\(context.state.awayScore)")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                            }
                            Text(context.attributes.awayTeam)
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    HStack {
                        VStack {
                            if context.state.awayScore < context.state.homeScore {
                                Text("\(context.state.homeScore)")
                                    .font(.system(size: 24))
                                    .fontWeight(.heavy)
                            } else {
                                Text("\(context.state.homeScore)")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                            }
                            Text(context.attributes.homeTeam)
                        }
                        if let homeID = context.attributes.homeID, let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(homeID),
                           let data = try? Data(contentsOf: fileURL),
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 35, height: 35)
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    LiveAnimatedView()
                        .transition(.scale(scale: 2.5))
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    if let formatted = GameFormatter().string(for: (context.attributes, context.state)) {
                        Text(formatted)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                
            } compactLeading: {
                Text(context.attributes.awayTeam)
                    .font(.caption2)
                if context.state.awayScore > context.state.homeScore {
                    Text("\(context.state.awayScore)")
                        .fontWeight(.heavy)
                } else {
                    Text("\(context.state.awayScore)")
                        .foregroundColor(.secondary)
                }
            } compactTrailing: {
                Text(context.attributes.homeTeam)
                    .font(.caption2)
                if context.state.awayScore < context.state.homeScore {
                    Text("\(context.state.homeScore)")
                        .fontWeight(.heavy)
                } else {
                    Text("\(context.state.homeScore)")
                        .foregroundColor(.secondary)
                }
            } minimal: {
                if context.state.awayScore > context.state.homeScore {
                    Text(context.attributes.awayTeam)
                        .font(.caption2)
                } else {
                    Text(context.attributes.homeTeam)
                        .font(.caption2)
                }
            }
        }
        
    }
}

//struct LiveSportActivityWidget_Previews: PreviewProvider {
//    static var previews: some View {
//        LiveSportActivityWidget()
//    }
//}
#endif
