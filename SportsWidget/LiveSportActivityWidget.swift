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
                    IndividualTeamView(shortName: context.attributes.awayTeam, longName: context.attributes.awayTeam, score: -1, isWinning: context.state.awayScore > context.state.homeScore, isAway: true)
                }
                if let formatted = context.state.progress {
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
                        } else {
                            #if DEBUG
                            Image(systemName: "circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 35, height: 35)
                            #endif
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
                        } else {
#if DEBUG
                            Image(systemName: "circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 35, height: 35)
#endif
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    LiveAnimatedView()
                        .transition(.scale(scale: 2.5))
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    if let formatted = context.state.progress {
                        Text(formatted)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                
            } compactLeading: {
<<<<<<< HEAD
                HStack(spacing: 0) {
                    if let homeID = context.attributes.awayID, let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(homeID),
                       let data = try? Data(contentsOf: fileURL),
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10, height: 10)
                    }
                    Text(context.attributes.awayTeam)
                        .font(.caption2)
                    if context.state.awayScore > context.state.homeScore {
                        Text("\(context.state.awayScore)")
                            .fontWeight(.heavy)
                    } else {
                        Text("\(context.state.awayScore)")
                            .foregroundColor(.secondary)
                    }
                }
            } compactTrailing: {
                HStack(spacing: 0) {
                    if let homeID = context.attributes.awayID, let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(homeID),
                       let data = try? Data(contentsOf: fileURL),
                       let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10, height: 10)
                    }
                    Text(context.attributes.homeTeam)
                        .font(.caption2)
                    if context.state.awayScore < context.state.homeScore {
                        Text("\(context.state.homeScore)")
                            .fontWeight(.heavy)
                    } else {
                        Text("\(context.state.homeScore)")
                            .foregroundColor(.secondary)
                    }
                }
            } minimal: {
                if context.state.awayScore > context.state.homeScore {
=======
                VStack {
>>>>>>> update live activities to work again
                    Text(context.attributes.awayTeam)
                        .font(.caption2)
                    if context.state.awayScore > context.state.homeScore {
                        Text("\(context.state.awayScore)")
                            .fontWeight(.heavy)
                    } else {
                        Text("\(context.state.awayScore)")
                            .foregroundColor(.secondary)
                    }
                }
                .scenePadding()
            } compactTrailing: {
                VStack {
                    Text(context.attributes.homeTeam)
                        .font(.caption2)
                    if context.state.awayScore < context.state.homeScore {
                        Text("\(context.state.homeScore)")
                            .fontWeight(.heavy)
                    } else {
                        Text("\(context.state.homeScore)")
                            .foregroundColor(.secondary)
                    }
                }
                    .scenePadding()
            } minimal: {
                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        if let awayID = context.attributes.awayID, let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(awayID),
                           let data = try? Data(contentsOf: fileURL),
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 5, height: 5)
                        } else {
#if DEBUG
                            Image(systemName: "circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 5, height: 5)
#endif
                        }
//                        if context.state.awayScore > context.state.homeScore {
//                            Text(context.attributes.awayTeam)
//                                .font(.system(size: 5))
//                        } else {
//                            Text(context.attributes.homeTeam)
//                                .font(.system(size: 5))
//                        }
                        Text("114")
                            .font(.system(size: 5))

                    }
                    HStack(spacing: 2) {
                        if let awayID = context.attributes.awayID, let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(awayID),
                           let data = try? Data(contentsOf: fileURL),
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 5, height: 5)
                        } else {
#if DEBUG
                            Image(systemName: "circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 5, height: 5)
#endif
                        }
//                        if context.state.awayScore > context.state.homeScore {
//                            Text(context.attributes.awayTeam)
//                                .font(.system(size: 5))
//                        } else {
//                            Text(context.attributes.homeTeam)
//                                .font(.system(size: 5))
//                        }
                        Text("114")
                                .font(.system(size: 5))
                    }
                }
//                    .scenePadding()
            }
        }
        
    }
}
<<<<<<< HEAD
=======

@available(iOSApplicationExtension 16.2, *)
struct LiveActivityWidgetLiveActivity_Previews: PreviewProvider {
    
    static let attributes = LiveSportActivityAttributes(homeTeam: "VGK", awayTeam: "EDM", homeID: "135913", awayID: "134849", eventID: "401459774")
    static let contentState = LiveSportActivityAttributes.ContentState(homeScore: 3, awayScore: 6, status: "in", progress: "2:14 - 2nd")
    
    static var previews: some View {
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.compact))
            .previewDisplayName("Island Compact")
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.expanded))
            .previewDisplayName("Island Expanded")
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.minimal))
            .previewDisplayName("Minimal")
        attributes
            .previewContext(contentState, viewKind: .content)
            .previewDisplayName("Notification")
    }
}

>>>>>>> update live activities to work again
#endif
