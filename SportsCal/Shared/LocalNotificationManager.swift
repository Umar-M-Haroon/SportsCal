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
        // Don't fire twice: this reminder replaces a team alert for the same game.
        if duration == .gameStarting, let eventID = item.idEvent {
            notiCenter.removePendingNotificationRequests(withIdentifiers: [TeamAlertScheduler.identifierPrefix + eventID])
        }
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

/// Keeps pending "game starting" notifications in step with the team alerts turned on
/// from team pages (`UserDefaultStorage.teamAlertTeamIDs`). Run whenever the alert set
/// or the loaded schedule changes; it adds, retimes, and removes its own requests.
enum TeamAlertScheduler {
    static let identifierPrefix = "teamalert_"
    /// iOS keeps at most 64 pending requests per app (silently dropping the latest),
    /// shared with one-off reminders — leave them room.
    private static let maxScheduled = 30
    /// Only schedule this far ahead; later games get picked up on a future run.
    private static let horizon: TimeInterval = 21 * 24 * 60 * 60

    static func reconcile(games: [Game], teamIDs: Set<String>, isPro: Bool, now: Date = Date()) {
        // A lapsed subscription keeps the free allowance, chosen stably.
        let allowed = isPro ? teamIDs : Set(teamIDs.sorted().prefix(NotificationGate.freeTeamAlertLimit))

        var seen = Set<String>()
        let wanted: [(identifier: String, game: Game, date: Date)] = games
            .compactMap { game -> (identifier: String, game: Game, date: Date)? in
                guard !allowed.isEmpty,
                      let eventID = game.idEvent, !eventID.isEmpty,
                      let date = game.standardDate,
                      date > now.addingTimeInterval(2 * 60),
                      date < now.addingTimeInterval(horizon),
                      involves(game, anyOf: allowed) else { return nil }
                return (identifierPrefix + eventID, game, date)
            }
            .sorted { $0.date < $1.date }
            .filter { seen.insert($0.identifier).inserted }
            .prefix(maxScheduled)
            .map { $0 }

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let pending = Set(requests.map(\.identifier))
            let stale = pending.filter { $0.hasPrefix(identifierPrefix) }
                .subtracting(wanted.map(\.identifier))
            if !stale.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: Array(stale))
            }
            for item in wanted {
                // A one-off "when game starts" reminder already covers this game.
                let manualID = "\(item.game.idEvent ?? "")_\(NotificationDuration.gameStarting.rawValue)"
                if pending.contains(manualID) { continue }

                let content = UNMutableNotificationContent()
                content.title = "Game Starting Now!"
                content.body = "\(item.game.strAwayTeam) @ \(item.game.strHomeTeam) is about to begin"
                content.sound = .default
                content.categoryIdentifier = NotificationType.gameReminder.rawValue
                // Re-adding under the same identifier replaces the request, which
                // retimes it when a game is rescheduled.
                let interval = item.date.addingTimeInterval(-60).timeIntervalSince(now)
                guard interval > 0 else { continue }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
            }
            AppLogger.notifications.info("Team alerts: \(wanted.count) scheduled, \(stale.count) removed")
        }
    }

    private static func involves(_ game: Game, anyOf teamIDs: Set<String>) -> Bool {
        if let id = game.idHomeTeam, teamIDs.contains(id) { return true }
        if let id = game.idAwayTeam, teamIDs.contains(id) { return true }
        if let id = TeamsManager.shared.teamID(forName: game.strHomeTeam), teamIDs.contains(id) { return true }
        if let id = TeamsManager.shared.teamID(forName: game.strAwayTeam), teamIDs.contains(id) { return true }
        return false
    }
}
