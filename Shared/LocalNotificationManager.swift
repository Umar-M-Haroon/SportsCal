//
//  LocalNotificationManager.swift
//  Homely
//
//  Created by Umar Haroon on 1/13/21.
//  Copyright © 2021 Umar Haroon. All rights reserved.
//

import Foundation
import UserNotifications
enum NotificationDuration: String {
    case thirtyMinutes = "30 minutes"
    case oneHour = "1 hour"
    case twoHour = "2 hours"
}
struct NotificationManager {
    static public func addLocalNotification(date: Date, item: Game, duration: NotificationDuration) {
        requestNotificationAccessIfNeeded()
        let notiContent = UNMutableNotificationContent()
        notiContent.title = "Upcoming \(item.sport.rawValue) Event"
        if item.sport == .F1 {
            notiContent.body = "Check out \(item.home) in \(duration.rawValue)"
        } else {
            notiContent.body = "Check out \(item.away) @ \(item.home) in \(duration.rawValue)"
        }
        notiContent.sound = .default
        var interval = date.timeIntervalSince(Date())
        if duration == .thirtyMinutes {
            interval -= 1800
        } else if duration == .oneHour {
            interval -= 3600
        } else if duration == .twoHour {
            interval -= 7200
        }
        print("⚠️ shooting notification in \(interval) seconds")
        let trig = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let notificationIdentifier = UUID().uuidString
        print("⚠️ firing notification at \(notificationIdentifier) and at Date \(Date(timeIntervalSinceNow: interval))")
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: notiContent, trigger: trig)
        let notiCenter = UNUserNotificationCenter.current()
        notiCenter.add(request) { (error) in
            if error != nil {
                print("⚠️ error adding notification \(error)")
            }
        }
    }
    static private func requestNotificationAccessIfNeeded() {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: {_, _ in })
        
    }
}
