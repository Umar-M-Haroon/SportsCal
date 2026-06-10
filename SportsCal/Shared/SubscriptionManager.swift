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
        #if DEBUG
        return ProcessInfo.processInfo.environment["mock-subscribed"] != nil
        #else
        return false
        #endif
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

    /// Restores previous purchases via RevenueCat and refreshes Pro state.
    /// Returns the resulting `isPro` value (true if an active entitlement was found).
    @MainActor
    public func restorePurchases() async -> Bool {
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            updateProStatus(from: customerInfo)
            return isPro
        } catch {
            AppLogger.general.error("Restore failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Debug-only override for QA. Lets you flip Pro state without a sandbox purchase.
    /// Persists to UserDefaults so the change survives relaunches.
    public func setMockPro(_ value: Bool) {
        #if DEBUG
        isPro = value
        UserDefaults.standard.set(value, forKey: "isSubscribed")
        #endif
    }

    internal func updateProStatus(from customerInfo: CustomerInfo) {
        let newValue = customerInfo.entitlements["Pro"]?.isActive == true
        // Allow mock override for QA builds (skip for test instances). DEBUG-only so it
        // can never grant Pro in a release build.
        #if DEBUG
        if !isTestInstance, ProcessInfo.processInfo.environment["mock-subscribed"] != nil {
            isPro = true
            UserDefaults.standard.set(true, forKey: "isSubscribed")
            return
        }
        #endif
        isPro = newValue
        UserDefaults.standard.set(newValue, forKey: "isSubscribed")
    }
}
