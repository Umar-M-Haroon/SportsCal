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
            if let homeBadgeString = homeTeam.strTeamBadge,  let homeBadgeURL = URL(string: homeBadgeString + "/tiny"), let awayBadgeString = awayTeam.strTeamBadge,  let awayBadgeURL = URL(string: awayBadgeString + "/tiny") {
                Task(priority: .userInitiated) { @MainActor in
                    do {
                        async let (homeData, _) = URLSession.shared.data(for: URLRequest(url: homeBadgeURL, cachePolicy: .returnCacheDataElseLoad))
                        async let (awayData, _) = URLSession.shared.data(for: URLRequest(url: awayBadgeURL, cachePolicy: .returnCacheDataElseLoad))
                        guard let homeTeamName = homeTeam.strTeamShort ?? homeTeam.strTeam,
                              let awayTeamName = awayTeam.strTeamShort ?? awayTeam.strTeam else { return }
                        
                        if let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appending(path: homeTeamName) {
                            try await homeData.write(to: fileURL)
                        }
                        
                        if let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appending(path: awayTeamName) {
                            try await awayData.write(to: fileURL)
                        }
                        let initialContentState = LiveSportActivityAttributes.ContentState(homeScore: Int(game.intHomeScore ?? "") ?? 0, awayScore: Int(game.intAwayScore ?? "") ?? 0, status: game.strStatus, progress: game.strProgress)
                        let activityAttributes = LiveSportActivityAttributes(homeTeam: homeTeamName, awayTeam: awayTeamName, eventID: game.idEvent ?? "")
                        if #available(iOS 16.2, *) {
                            sportActivity = try Activity.request(attributes: activityAttributes, content: .init(state: initialContentState, staleDate: .distantFuture, relevanceScore:  100), pushType: .token)
                        } else {
                            sportActivity = try Activity.request(attributes: activityAttributes, contentState: initialContentState, pushType: .token)
                        }
                        if let token = sportActivity.pushToken, let eventID = game.idEvent {
                            let tokenString = token.map { String(format: "%02x", $0)}.joined()
                            try await NetworkHandler.subscribeToLiveActivityUpdate(token: tokenString, eventID: eventID, debug: UserDefaultStorage().debugMode)
                        }
                    } catch let error {
                        print(error.localizedDescription)
                    }
                }
                
            }
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
