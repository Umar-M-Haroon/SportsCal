//
//  AppDelegate.swift
//  AppDelegate
//
//  Created by Umar Haroon on 8/21/21.
//

import Foundation
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        application.registerForRemoteNotifications()
        
        return true
    }

}
