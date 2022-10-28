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
            guard let notificationDate = Calendar.current.date(byAdding: .minute, value: -30, to: date) else { return }
            interval = notificationDate.timeIntervalSince(Date())
        } else if duration == .oneHour {
            guard let notificationDate = Calendar.current.date(byAdding: .hour, value: -1, to: date) else { return }
            interval = notificationDate.timeIntervalSince(Date())
        } else if duration == .twoHour {
            guard let notificationDate = Calendar.current.date(byAdding: .hour, value: -2, to: date) else { return }
            interval = notificationDate.timeIntervalSince(Date())
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
            } else {
                print("⚠️ successfully added notification")
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
