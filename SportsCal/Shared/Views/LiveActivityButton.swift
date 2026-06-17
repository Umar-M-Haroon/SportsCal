//
//  LiveActivityButton.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/27/22.
//

import SwiftUI
import SportsCalModel
import Sentry
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#if os(iOS)
import UIKit
#endif

/// Context-menu content for following a live game with a Live Activity.
///
/// When Live Activities are authorized it shows the follow/unfollow toggle.
/// When they're disabled (the app's switch is off in Settings, or the user
/// turned the system feature off) it shows a tappable hint that deep-links to
/// Settings — previously the button was simply hidden, leaving the user with a
/// silently-missing "Follow" with no explanation.
struct LiveActivityFollowMenu: View {
    var game: Game
    var homeTeam: Team
    var awayTeam: Team
    @Environment(GameViewModel.self) private var viewModel

    var body: some View {
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            LiveActivityButton(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
                .environment(viewModel)
        } else {
            Button {
                #if os(iOS)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #endif
            } label: {
                Label("Turn On Live Activities", systemImage: "clock.badge.exclamationmark")
            }
        }
    }
}

struct LiveActivityButton: View {
    var game: Game
    var homeTeam: Team
    var awayTeam: Team
    @State var homeData: Data?
    @State var awayData: Data?
    @State var sportActivity: Activity<LiveSportActivityAttributes>!
    @Environment(GameViewModel.self) private var viewModel
    var isFollowing: Bool {
        return Activity<LiveSportActivityAttributes>.activities.contains(where: {$0.attributes.eventID == game.idEvent })
    }
    var body: some View {
        Button {
            // Look up inside the Task so isFollowing snapshot can't race with a
            // fresh push-to-start arrival — a stale "follow" tap would otherwise
            // route through requestActivity and (now idempotently) just update
            // the existing activity instead of starting a duplicate.
            Task {
                if let activity = Activity<LiveSportActivityAttributes>.activities
                    .first(where: { $0.attributes.eventID == game.idEvent }) {
                    await activity.end(using: activity.contentState, dismissalPolicy: .immediate)
                    return
                }
                viewModel.requestActivity(game: game, homeTeam: homeTeam, awayTeam: awayTeam)
            }
        } label: {
            if isFollowing {
                Label("Unfollow", systemImage: "clock.badge.xmark.fill")
            } else {
                Label("Follow", systemImage: "clock.badge")
            }
        }
        .sensoryFeedback(.success, trigger: isFollowing)
    }
}
#endif
