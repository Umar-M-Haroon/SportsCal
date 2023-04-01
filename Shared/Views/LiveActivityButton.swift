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
    @Binding var activityState: LiveActivityStatus
//    @Binding var activeLiveActivities: [Activity<LiveSportActivityAttributes>]
    var body: some View {
        Button {
            if Activity<LiveSportActivityAttributes>.activities.contains(where: {$0.attributes.eventID == game.idEvent }) {
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
                        withAnimation {
                            activityState = .loading
                        }
                        (homeData, _) = try await URLSession.shared.data(for: URLRequest(url: homeBadgeURL, cachePolicy: .returnCacheDataElseLoad))
                        (awayData, _) = try await URLSession.shared.data(for: URLRequest(url: awayBadgeURL, cachePolicy: .returnCacheDataElseLoad))
                        
                        if let homeID = homeTeam.idTeam, let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appending(path: homeID), let data = homeData {
                            try data.write(to: fileURL)
                        }
                        
                        if let awayID = awayTeam.idTeam, let fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Komodo.SportsCal")?.appending(path: awayID), let data = awayData {
                            try data.write(to: fileURL)
                        }
                        let initialContentState = LiveSportActivityAttributes.ContentState(homeScore: Int(game.intHomeScore ?? "") ?? 0, awayScore: Int(game.intAwayScore ?? "") ?? 0, status: game.strStatus, progress: game.strProgress)
                        let activityAttributes = LiveSportActivityAttributes(homeTeam: homeTeam.strTeamShort ?? homeTeam.strTeam ?? "", awayTeam: awayTeam.strTeamShort ?? awayTeam.strTeam ?? "", homeID: homeTeam.idTeam ?? "''", awayID: awayTeam.idTeam ?? "", eventID: game.idEvent ?? "", league: game.idLeague, awayURL: awayTeam.strTeamBadge, homeURL: homeTeam.strTeamBadge)
<<<<<<< HEAD
                        sportActivity = try Activity.request(attributes: activityAttributes, contentState: initialContentState, pushType: .token)
                        print(sportActivity.pushToken)
=======
                        if #available(iOS 16.2, *) {
                            sportActivity = try Activity.request(attributes: activityAttributes, content: .init(state: initialContentState, staleDate: .distantFuture, relevanceScore:  100), pushType: .token)
                        } else {
                            sportActivity = try Activity.request(attributes: activityAttributes, contentState: initialContentState, pushType: .token)
                        }
>>>>>>> update live activities to work again
                        if let token = sportActivity.pushToken, let eventID = game.idEvent {
                            let tokenString = token.map { String(format: "%02x", $0)}.joined()
                            try await NetworkHandler.subscribeToLiveActivityUpdate(token: tokenString, eventID: eventID, debug: UserDefaultStorage().debugMode)
                            withAnimation {
                                activityState = .added
                            }
                        } else {
                            print("Failed to get token")
                        }
                        withAnimation {
                            activityState = .added
                        }
                        
                    } catch let error {
                        print(error.localizedDescription)
                    }
                }
                
            }
        } label: {
            if Activity<LiveSportActivityAttributes>.activities.contains(where: {$0.attributes.eventID == game.idEvent }) {
                Label("Unfollow", systemImage: "clock.badge.xmark.fill")
            } else {
                Label("Follow", systemImage: "clock.badge")
            }
        }
    }
}
#endif
