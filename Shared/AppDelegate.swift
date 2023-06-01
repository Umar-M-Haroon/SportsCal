//
//  AppDelegate.swift
//  AppDelegate
//
//  Created by Umar Haroon on 8/21/21.
//

import Foundation
import UIKit
import Sentry

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        application.registerForRemoteNotifications()
        SentrySDK.start { options in
            options.dsn = "https://02afdbcbf12d400f865620093257a781@o4505270524772352.ingest.sentry.io/4505282684321792"
            options.debug = true // Enabled debug when first installing is always helpful
            
            // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
            // We recommend adjusting this value in production.
            options.tracesSampleRate = 1.0
        }
        
        return true
    }

}
