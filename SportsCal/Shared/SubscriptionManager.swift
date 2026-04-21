//
//  SubscriptionManager.swift
//  SportsCal
//
//  Created by Umar Haroon on 8/15/21.
//

import Foundation
import SwiftUI
import RevenueCat
import os

@Observable
public class SubscriptionManager: @unchecked Sendable {
    public static let shared = SubscriptionManager()

    public var isPro: Bool = false
    private var isTestInstance: Bool = false

    private init() {
        // Check cached value first for instant UI
        isPro = UserDefaults.standard.bool(forKey: "isSubscribed")
    }

    /// Test-only initializer that skips RevenueCat configuration.
    /// Allows creating isolated instances for unit testing.
    /// Test instances ignore the mock-subscribed environment variable.
    internal init(forTesting initialProValue: Bool) {
        isPro = initialProValue
        isTestInstance = true
    }

    internal var environmentOverridesEnabled: Bool {
        ProcessInfo.processInfo.environment["mock-subscribed"] != nil
    }

    /// Call once at app launch (e.g., in SportsCalApp.init)
    public func configure() {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Constants.revenueCatAPIKey)

        // Listen for customer info changes
        Task { @MainActor in
            for try await customerInfo in Purchases.shared.customerInfoStream {
                self.updateProStatus(from: customerInfo)
            }
        }

        // Get initial customer info
        Task { @MainActor in
            await refreshStatus()
        }
    }

    @MainActor
    public func refreshStatus() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateProStatus(from: customerInfo)
        } catch {
            AppLogger.general.error("Failed to get customer info: \(error.localizedDescription)")
        }
    }

    /// Debug-only override for QA. Lets you flip Pro state without a sandbox purchase.
    /// Persists to UserDefaults so the change survives relaunches.
    public func setMockPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: "isSubscribed")
    }

    internal func updateProStatus(from customerInfo: CustomerInfo) {
        let newValue = customerInfo.entitlements["Pro"]?.isActive == true
        // Allow mock override for QA builds (skip for test instances)
        if !isTestInstance, ProcessInfo.processInfo.environment["mock-subscribed"] != nil {
            isPro = true
            UserDefaults.standard.set(true, forKey: "isSubscribed")
            return
        }
        isPro = newValue
        UserDefaults.standard.set(newValue, forKey: "isSubscribed")
    }
}
