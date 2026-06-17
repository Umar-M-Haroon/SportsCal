//
//  AppDelegate.swift
//  AppDelegate
//
//  Created by Umar Haroon on 8/21/21.
//

import Foundation
import Sentry
import UserNotifications
import os
#if os(iOS)
import GoogleMobileAds
#endif

#if os(iOS)
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // Initialize Google Mobile Ads SDK
        #if DEBUG
        // Mark all simulators and this device as test devices so we always get test ads,
        // even if the production ad unit ID is configured. Prevents AdMob account flagging
        // from accidental clicks during development.
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [
            "kGADSimulatorID" as String,
            "2153b390d99b5b3d68e57f2a1c16c0c1"
        ]
        #endif
        // Initialize off the launch-critical path. SDK init kicks off network +
        // WebKit warmup that contends with first-frame work; nothing needs ads
        // ready before the deferred preload (1s after first paint) requests them.
        Task.detached(priority: .utility) {
            await MobileAds.shared.start()
        }

        // Request notification permissions
        requestNotificationAuthorization()

        // Register for remote notifications
        application.registerForRemoteNotifications()

        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = self

        if !Constants.sentryDSN.isEmpty {
            SentrySDK.start { options in
                options.dsn = Constants.sentryDSN
                options.tracesSampleRate = 0.05
                options.beforeSend = { event in
                    // Redact breadcrumbs that may carry device tokens or push payloads.
                    event.breadcrumbs = event.breadcrumbs?.map { crumb in
                        if let message = crumb.message,
                           message.contains("token") || message.contains("notification") {
                            crumb.message = "[REDACTED]"
                        }
                        return crumb
                    }
                    return event
                }
            }
        } else {
            AppLogger.general.error("Sentry DSN missing — crash reporting disabled for this build")
        }

        return true
    }

    private func requestNotificationAuthorization() {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if let error = error {
                AppLogger.notifications.error("Error requesting notification authorization: \(error.localizedDescription)")
                SentrySDK.capture(error: error)
            }
            if granted {
                AppLogger.notifications.info("Notification authorization granted")
            } else {
                AppLogger.notifications.notice("Notification authorization denied")
            }
        }
    }

    // MARK: - Remote Notification Registration

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        AppLogger.notifications.info("Registered for remote notifications with token: \(tokenString.prefix(12))…")

        // Store token in UserDefaults for later use
        UserDefaults(suiteName: "group.Komodo.SportsCal")?.set(tokenString, forKey: "apnsDeviceToken")

        // TODO: Send token to backend for push notification registration
        // This would typically call NetworkHandler.registerDeviceToken(tokenString)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLogger.notifications.error("Failed to register for remote notifications: \(error.localizedDescription)")
        SentrySDK.capture(error: error)
    }

    // MARK: - Handle Push Notifications

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Handle incoming push notification
        AppLogger.notifications.info("Received remote notification for event: \(userInfo["eventID"] as? String ?? "unknown")")

        // Check if this is a Live Activity update
        if let eventID = userInfo["eventID"] as? String {
            handleLiveActivityUpdate(eventID: eventID, userInfo: userInfo)
        }

        // Check if this is a final score notification
        if let notificationType = userInfo["type"] as? String, notificationType == "final_score" {
            handleFinalScoreNotification(userInfo: userInfo)
        }

        completionHandler(.newData)
    }

    private func handleLiveActivityUpdate(eventID: String, userInfo: [AnyHashable: Any]) {
        // Live Activity updates are handled automatically by ActivityKit
        // This is here for any additional processing needed
        AppLogger.liveActivity.info("Live Activity update for event: \(eventID)")
    }

    private func handleFinalScoreNotification(userInfo: [AnyHashable: Any]) {
        // Parse final score data and show local notification if app is in background
        guard let homeTeam = userInfo["homeTeam"] as? String,
              let awayTeam = userInfo["awayTeam"] as? String,
              let homeScore = userInfo["homeScore"] as? Int,
              let awayScore = userInfo["awayScore"] as? Int else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Final Score"
        content.body = "\(awayTeam) \(awayScore) - \(homeTeam) \(homeScore)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.notifications.error("Error showing final score notification: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        AppLogger.notifications.info("User tapped notification for event: \(userInfo["eventID"] as? String ?? "unknown")")

        // Handle deep linking based on notification type
        if let eventID = userInfo["eventID"] as? String {
            // Post notification to open specific game
            NotificationCenter.default.post(name: NSNotification.Name("OpenGameFromNotification"), object: nil, userInfo: ["eventID": eventID])
        }

        completionHandler()
    }
}

#else
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permissions
        requestNotificationAuthorization()

        // Register for remote notifications
        NSApplication.shared.registerForRemoteNotifications()

        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = self

        if !Constants.sentryDSN.isEmpty {
            SentrySDK.start { options in
                options.dsn = Constants.sentryDSN
                options.tracesSampleRate = 0.05
                options.beforeSend = { event in
                    // Redact breadcrumbs that may carry device tokens or push payloads.
                    event.breadcrumbs = event.breadcrumbs?.map { crumb in
                        if let message = crumb.message,
                           message.contains("token") || message.contains("notification") {
                            crumb.message = "[REDACTED]"
                        }
                        return crumb
                    }
                    return event
                }
            }
        } else {
            AppLogger.general.error("Sentry DSN missing — crash reporting disabled for this build")
        }
    }

    private func requestNotificationAuthorization() {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if let error = error {
                AppLogger.notifications.error("Error requesting notification authorization: \(error.localizedDescription)")
                SentrySDK.capture(error: error)
            }
            if granted {
                AppLogger.notifications.info("Notification authorization granted")
            } else {
                AppLogger.notifications.notice("Notification authorization denied")
            }
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        AppLogger.notifications.info("Registered for remote notifications with token: \(tokenString.prefix(12))…")
        UserDefaults(suiteName: "group.Komodo.SportsCal")?.set(tokenString, forKey: "apnsDeviceToken")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLogger.notifications.error("Failed to register for remote notifications: \(error.localizedDescription)")
        SentrySDK.capture(error: error)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        AppLogger.notifications.info("User tapped notification for event: \(userInfo["eventID"] as? String ?? "unknown")")

        if let eventID = userInfo["eventID"] as? String {
            NotificationCenter.default.post(name: NSNotification.Name("OpenGameFromNotification"), object: nil, userInfo: ["eventID": eventID])
        }

        completionHandler()
    }
}
#endif
