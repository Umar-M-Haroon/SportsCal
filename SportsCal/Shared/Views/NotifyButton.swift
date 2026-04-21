//
//  NotifyButton.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 10/27/22.
//

import SwiftUI
#if os(iOS)
import EventKitUI
#endif
import SportsCalModel
import UserNotifications

struct NotifyButton: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Binding var shouldShowSportsCalProAlert: Bool
    @Binding var sheetType: SheetType?
    var game: Game
    @State private var scheduledNotifications: Set<NotificationDuration> = []

    var body: some View {
        Menu {
            // Game Starting Now option
            Button {
                scheduleNotification(duration: .gameStarting)
            } label: {
                HStack {
                    Text("When game starts")
                    if scheduledNotifications.contains(.gameStarting) {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            // 30 minutes before
            Button {
                scheduleNotification(duration: .thirtyMinutes)
            } label: {
                HStack {
                    Text("\(NotificationDuration.thirtyMinutes.rawValue) before")
                    if scheduledNotifications.contains(.thirtyMinutes) {
                        Image(systemName: "checkmark")
                    }
                }
            }

            // 1 hour before
            Button {
                scheduleNotification(duration: .oneHour)
            } label: {
                HStack {
                    Text("\(NotificationDuration.oneHour.rawValue) before")
                    if scheduledNotifications.contains(.oneHour) {
                        Image(systemName: "checkmark")
                    }
                }
            }

            // 2 hours before
            Button {
                scheduleNotification(duration: .twoHour)
            } label: {
                HStack {
                    Text("\(NotificationDuration.twoHour.rawValue) before")
                    if scheduledNotifications.contains(.twoHour) {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            // Cancel all notifications
            if !scheduledNotifications.isEmpty {
                Button(role: .destructive) {
                    cancelAllNotifications()
                } label: {
                    Label("Cancel All Reminders", systemImage: "bell.slash")
                }
            }
        } label: {
            Label(scheduledNotifications.isEmpty ? "Notify Me" : "Notifying", systemImage: scheduledNotifications.isEmpty ? "bell.badge" : "bell.badge.fill")
        }
        .onAppear {
            checkScheduledNotifications()
        }
    }

    private func scheduleNotification(duration: NotificationDuration) {
        guard subscriptionManager.isPro else {
            shouldShowSportsCalProAlert = true
            return
        }
        guard let gameDate = game.standardDate else { return }

        if scheduledNotifications.contains(duration) {
            // Cancel this specific notification
            if let gameID = game.idEvent {
                let notiCenter = UNUserNotificationCenter.current()
                notiCenter.removePendingNotificationRequests(withIdentifiers: ["\(gameID)_\(duration.rawValue)"])
                scheduledNotifications.remove(duration)
            }
        } else {
            // Schedule the notification
            NotificationManager.addLocalNotification(date: gameDate, item: game, duration: duration)
            scheduledNotifications.insert(duration)
        }
    }

    private func cancelAllNotifications() {
        if let gameID = game.idEvent {
            NotificationManager.cancelNotifications(for: gameID)
            scheduledNotifications.removeAll()
        }
    }

    private func checkScheduledNotifications() {
        guard let gameID = game.idEvent else { return }
        for duration in NotificationDuration.allCases {
            NotificationManager.isNotificationScheduled(for: gameID, duration: duration) { isScheduled in
                DispatchQueue.main.async {
                    if isScheduled {
                        scheduledNotifications.insert(duration)
                    }
                }
            }
        }
    }
}

#Preview {
    NotifyButton(shouldShowSportsCalProAlert: .constant(false), sheetType: .constant(nil), game: Game(idLeague: "4387", strHomeTeam: "Lakers", strAwayTeam: "Celtics", isoDate: nil))
}
