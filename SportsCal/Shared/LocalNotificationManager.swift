//
//  LocalNotificationManager.swift
//  Homely
//
//  Created by Umar Haroon on 1/13/21.
//  Copyright © 2021 Umar Haroon. All rights reserved.
//

import Foundation
import UserNotifications
import SportsCalModel
import os

enum NotificationDuration: String, CaseIterable {
    case gameStarting = "Game Starting"
    case thirtyMinutes = "30 minutes"
    case oneHour = "1 hour"
    case twoHour = "2 hours"
}

enum NotificationType: String {
    case gameReminder = "game_reminder"
    case finalScore = "final_score"
}

struct NotificationManager {
    static public func addLocalNotification(date: Date, item: Game, duration: NotificationDuration) {
        requestNotificationAccessIfNeeded()
        let notiContent = UNMutableNotificationContent()

        var interval: TimeInterval

        switch duration {
        case .gameStarting:
            notiContent.title = "Game Starting Now!"
            notiContent.body = "\(item.strAwayTeam) @ \(item.strHomeTeam) is about to begin"
            // Fire 1 minute before game start
            guard let notificationDate = Calendar.current.date(byAdding: .minute, value: -1, to: date) else { return }
            interval = notificationDate.timeIntervalSince(Date())
        case .thirtyMinutes:
            notiContent.title = "Upcoming \(item.strSport ?? "Sports") Event"
            notiContent.body = "Check out \(item.strAwayTeam) @ \(item.strHomeTeam) in 30 minutes"
            guard let notificationDate = Calendar.current.date(byAdding: .minute, value: -30, to: date) else { return }
            interval = notificationDate.timeIntervalSince(Date())
        case .oneHour:
            notiContent.title = "Upcoming \(item.strSport ?? "Sports") Event"
            notiContent.body = "Check out \(item.strAwayTeam) @ \(item.strHomeTeam) in 1 hour"
            guard let notificationDate = Calendar.current.date(byAdding: .hour, value: -1, to: date) else { return }
            interval = notificationDate.timeIntervalSince(Date())
        case .twoHour:
            notiContent.title = "Upcoming \(item.strSport ?? "Sports") Event"
            notiContent.body = "Check out \(item.strAwayTeam) @ \(item.strHomeTeam) in 2 hours"
            guard let notificationDate = Calendar.current.date(byAdding: .hour, value: -2, to: date) else { return }
            interval = notificationDate.timeIntervalSince(Date())
        }

        notiContent.sound = .default
        notiContent.categoryIdentifier = NotificationType.gameReminder.rawValue

        // Ensure interval is positive
        guard interval > 0 else {
            AppLogger.notifications.notice("Notification time has already passed")
            return
        }

        AppLogger.notifications.info("Scheduling notification in \(interval) seconds")
        let trig = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let notificationIdentifier = "\(item.idEvent ?? UUID().uuidString)_\(duration.rawValue)"
        AppLogger.notifications.info("Firing notification \(notificationIdentifier) at \(Date(timeIntervalSinceNow: interval))")
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: notiContent, trigger: trig)
        let notiCenter = UNUserNotificationCenter.current()
        notiCenter.add(request) { (error) in
            if let error {
                AppLogger.notifications.error("Error adding notification: \(error.localizedDescription)")
            } else {
                AppLogger.notifications.info("Successfully added notification")
            }
        }
    }

    /// Schedule a final score notification (to be sent when game ends via push or local trigger)
    static public func scheduleFinalScoreNotification(item: Game, homeScore: Int, awayScore: Int) {
        requestNotificationAccessIfNeeded()
        let notiContent = UNMutableNotificationContent()
        notiContent.title = "Final Score"
        notiContent.body = "\(item.strAwayTeam) \(awayScore) - \(item.strHomeTeam) \(homeScore)"
        notiContent.sound = .default
        notiContent.categoryIdentifier = NotificationType.finalScore.rawValue

        let notificationIdentifier = "\(item.idEvent ?? UUID().uuidString)_final"
        // Fire immediately when called
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: notiContent, trigger: nil)
        let notiCenter = UNUserNotificationCenter.current()
        notiCenter.add(request) { (error) in
            if let error {
                AppLogger.notifications.error("Error adding final score notification: \(error.localizedDescription)")
            } else {
                AppLogger.notifications.info("Successfully added final score notification")
            }
        }
    }

    /// Cancel all notifications for a specific game
    static public func cancelNotifications(for gameID: String) {
        let notiCenter = UNUserNotificationCenter.current()
        let identifiersToRemove = NotificationDuration.allCases.map { "\(gameID)_\($0.rawValue)" }
        notiCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        AppLogger.notifications.info("Cancelled notifications for game \(gameID)")
    }

    static public func requestNotificationAccessIfNeeded() {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: {_, _ in })
    }

    /// Check if a notification is already scheduled for a game/duration
    static public func isNotificationScheduled(for gameID: String, duration: NotificationDuration, completion: @escaping (Bool) -> Void) {
        let notiCenter = UNUserNotificationCenter.current()
        let identifier = "\(gameID)_\(duration.rawValue)"
        notiCenter.getPendingNotificationRequests { requests in
            let isScheduled = requests.contains { $0.identifier == identifier }
            completion(isScheduled)
        }
    }
}
