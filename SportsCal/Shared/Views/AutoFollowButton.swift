//
//  AutoFollowButton.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 2/12/26.
//

import SwiftUI
import SportsCalModel
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// Statuses that mean a game is finished — auto-follow should not show
let autoFollowCompletedStatuses: Set<String> = ["FT", "AOT", "Final", "Final/OT", "AP", "post"]

/// Whether a game is completed (finished). Unlike `hasDoneStatus`, this does NOT
/// include "pre" or "NS" which are pre-game states where auto-follow should be available.
func isGameCompleted(_ game: Game) -> Bool {
    if let isCompleted = game.isCompleted, isCompleted { return true }
    if let status = game.strStatus, autoFollowCompletedStatuses.contains(status) { return true }
    if let progress = game.strProgress, autoFollowCompletedStatuses.contains(progress) { return true }
    return false
}

@available(iOS 16.1, *)
struct AutoFollowButton: View {
    var game: Game
    var homeTeam: Team
    var awayTeam: Team
    @Environment(GameViewModel.self) private var viewModel

    private var eventID: String? { game.idEvent }

    private var isAutoFollowing: Bool {
        guard let eventID else { return false }
        return viewModel.appStorage.isAutoFollowing(eventID)
    }

    /// Only show for upcoming games (not live or completed)
    private var shouldShow: Bool {
        guard game.idEvent != nil else { return false }
        // Don't show if game is currently live or already finished
        if game.strStatus == "in" || isGameCompleted(game) { return false }
        // Don't show if already following via LiveActivity
        if Activity<LiveSportActivityAttributes>.activities.contains(where: { $0.attributes.eventID == game.idEvent }) {
            return false
        }
        return true
    }

    var body: some View {
        if shouldShow {
            Button {
                guard let eventID else { return }
                if isAutoFollowing {
                    viewModel.appStorage.removeAutoFollow(eventID)
                    if viewModel.appStorage.debugMode {
                        AutoFollowLogger.shared.log("Auto-follow removed: \(eventID)")
                    }
                } else {
                    viewModel.appStorage.addAutoFollow(eventID)
                    viewModel.preCacheBadges(homeTeam: homeTeam, awayTeam: awayTeam)
                    if viewModel.appStorage.debugMode {
                        AutoFollowLogger.shared.log("Auto-follow added: \(eventID)")
                    }
                }
                #if os(iOS)
                viewModel.sendAutoFollowRegistration()
                #endif
            } label: {
                if isAutoFollowing {
                    Label("Auto-Following", systemImage: "clock.badge.fill")
                } else {
                    Label("Auto-Follow", systemImage: "clock.badge")
                }
            }
        }
    }
}

#endif
