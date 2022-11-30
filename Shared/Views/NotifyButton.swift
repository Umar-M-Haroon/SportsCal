//
//  NotifyButton.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/27/22.
//

import SwiftUI
import EventKitUI
import SportsCalModel

struct NotifyButton: View {
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var game: Game
    var body: some View {
        Menu {
            Button {
                if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                    shouldShowSportsCalProAlert = true
                } else {
                    //                                        NotificationManager.addLocalNotification(date: game.gameDate, item: game, duration: .thirtyMinutes)
                }
            } label: {
                Text("\(NotificationDuration.thirtyMinutes.rawValue) before")
            }
            Button {
                if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                    shouldShowSportsCalProAlert = true
                } else {
                    //                                        NotificationManager.addLocalNotification(date: game.gameDate, item: game, duration: .oneHour)
                }
            } label: {
                Text("\(NotificationDuration.oneHour.rawValue) before")
            }
            Button {
                
                if SubscriptionManager.shared.subscriptionStatus == .notSubscribed {
                    shouldShowSportsCalProAlert = true
                } else {
                    //                                        NotificationManager.addLocalNotification(date: game.gameDate, item: game, duration: .twoHour)
                }
            } label: {
                Text("\(NotificationDuration.twoHour.rawValue) before")
            }
        } label: {
            Label("Notify Me", systemImage: "bell.badge.fill")
        }
    }
}

//struct NotifyButton_Previews: PreviewProvider {
//    static var previews: some View {
//        NotifyButton()
//    }
//}
