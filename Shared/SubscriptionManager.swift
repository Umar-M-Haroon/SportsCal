//
//  SubscriptionManager.swift
//  SubscriptionManager
//
//  Created by Umar Haroon on 8/15/21.
//

import Foundation
import Purchases
import SwiftUI


public class SubscriptionManager: ObservableObject {
    public static let shared = SubscriptionManager()
    
    public enum SubscriptionStatus: String {
        case subscribed = "subscribed"
        case notSubscribed
    }
    
    @Published public var monthlySubscription: Purchases.Package?
    @Published public var yearlySubscription: Purchases.Package?
    @Published public var inPaymentProgress = false
    @AppStorage("isSubscribed") var subscriptionStatus: SubscriptionStatus = .notSubscribed
    
    init() {
        Purchases.configure(withAPIKey: Constants.revenueCatAPIKey)
        Purchases.shared.offerings { (offerings, error) in
            self.monthlySubscription = offerings?.current?.monthly
            self.yearlySubscription = offerings?.current?.annual
        }
        refreshSubscription()
    }
    
    public func purchase(product: Purchases.Package) {
        guard !inPaymentProgress else { return }
        inPaymentProgress = true
        Purchases.shared.purchasePackage(product) { (_, info, _, _) in
            self.processInfo(info: info)
        }
    }
    
    
    public func refreshSubscription() {
        Purchases.shared.purchaserInfo { (info, _) in
            self.processInfo(info: info)
        }
    }
    
    public func restorePurchase() {
        Purchases.shared.restoreTransactions { (info, _) in
            self.processInfo(info: info)
        }
    }
    
    private func processInfo(info: Purchases.PurchaserInfo?) {
        
        if let _ = ProcessInfo.processInfo.environment["mock-subscribed"] {
            subscriptionStatus = .subscribed
            return
        }
        if info?.entitlements.all["Pro"]?.isActive == true {
            subscriptionStatus = .subscribed
        } else {
            subscriptionStatus = .notSubscribed
        }
        inPaymentProgress = false
    }
}
