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

/// Loads a team badge image from the shared app group container, with a fallback to team initials.
@ViewBuilder
private func badgeImage(for teamName: String, size: CGFloat) -> some View {
    if let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(teamName),
       let data = try? Data(contentsOf: fileURL),
       let image = UIImage(data: data) {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    } else {
        teamInitialsView(teamName, size: size)
    }
}

/// Fallback view showing team initials in a circle when badge image is unavailable.
@ViewBuilder
private func teamInitialsView(_ teamName: String, size: CGFloat) -> some View {
    ZStack {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: size, height: size)
        Text(String(teamName.prefix(3)))
            .font(.system(size: size * 0.35, weight: .bold))
            .foregroundColor(.white)
    }
}

struct LiveSportActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveSportActivityAttributes.self) { context in
            HStack {
                if let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(context.attributes.awayTeam) {
                    IndividualTeamView(shortName: context.attributes.awayTeam, longName: context.attributes.awayTeam, score: context.state.awayScore, isWinning: context.state.awayScore > context.state.homeScore, isAway: true, data: try? Data(contentsOf: fileURL))
                } else {
                    IndividualTeamView(shortName: context.attributes.awayTeam, longName: context.attributes.awayTeam, score: -1, isWinning: context.state.awayScore > context.state.homeScore, isAway: true)
                }
                if let formatted = context.state.progress {
                    Text(formatted)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appendingPathComponent(context.attributes.homeTeam) {
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
                        badgeImage(for: context.attributes.awayTeam, size: 35)
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
                        badgeImage(for: context.attributes.homeTeam, size: 35)
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    LiveAnimatedView()
                        .transition(.scale(scale: 2.5))
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        if let formatted = context.state.progress {
                            Text(formatted)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        if let lastPlay = context.state.lastPlay, !lastPlay.isEmpty {
                            Text(lastPlay)
                                .font(.caption2)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                
            } compactLeading: {
                HStack(spacing: 4) {
                    badgeImage(for: context.attributes.awayTeam, size: 10)
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
                HStack(spacing: 4) {
                    badgeImage(for: context.attributes.homeTeam, size: 10)
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
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        badgeImage(for: context.attributes.awayTeam, size: 10)
                        Text("\(context.state.awayScore)")
                            .font(.system(size: 8))
                    }
                    HStack(spacing: 4) {
                        badgeImage(for: context.attributes.homeTeam, size: 10)
                        Text("\(context.state.homeScore)")
                            .font(.system(size: 8))
                    }
                }
            }
        }
    }
    
}

#Preview("Island Compact", as: .dynamicIsland(.compact), using: LiveSportActivityAttributes(homeTeam: "VGK", awayTeam: "EDM", eventID: "401459774")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 3, awayScore: 6, status: "in", progress: "2:14 - 2nd", lastPlay: "Goal by McDavid (PP)")
}

#Preview("Island Expanded", as: .dynamicIsland(.expanded), using: LiveSportActivityAttributes(homeTeam: "VGK", awayTeam: "EDM", eventID: "401459774")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 3, awayScore: 6, status: "in", progress: "2:14 - 2nd", lastPlay: "Goal by McDavid (PP)")
}

#Preview("Notification", as: .content, using: LiveSportActivityAttributes(homeTeam: "VGK", awayTeam: "EDM", eventID: "401459774")) {
    LiveSportActivityWidget()
} contentStates: {
    LiveSportActivityAttributes.ContentState(homeScore: 3, awayScore: 6, status: "in", progress: "2:14 - 2nd", lastPlay: "Goal by McDavid (PP)")
}
#endif
