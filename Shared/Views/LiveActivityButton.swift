//
//  LiveActivityButton.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/27/22.
//

import SwiftUI
import SportsCalModel
#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
struct LiveActivityButton: View {
    var game: Game
    var homeTeam: Team
    var awayTeam: Team
    @State var homeData: Data?
    @State var awayData: Data?
    @State var sportActivity: Activity<LiveSportActivityAttributes>!
    @EnvironmentObject var model: GameViewModel
    var isFollowing: Bool {
        return Activity<LiveSportActivityAttributes>.activities.contains(where: {$0.attributes.eventID == game.idEvent })
    }
    var body: some View {
        Button {
            if isFollowing {
                // Unfollow logic
                if let activity = Activity<LiveSportActivityAttributes>.activities.first(where: {$0.attributes.eventID == game.idEvent}) {
                    Task {
                        await activity.end(using: activity.contentState, dismissalPolicy: .immediate)
                    }
                }
                return
            }
            model.subscribeToLiveActivity(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
        } label: {
            if isFollowing {
                Label("Unfollow", systemImage: "clock.badge.xmark.fill")
            } else {
                Label("Follow", systemImage: "clock.badge")
            }
        }
    }
}
#endif
