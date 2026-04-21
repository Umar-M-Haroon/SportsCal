//
//  RevenueCatIntegrationTests.swift
//  SportsCalTests
//
//  Created by Umar Haroon on 2026-04-12.
//

import XCTest
import RevenueCat
@testable import Scoreline

@MainActor
final class RevenueCatIntegrationTests: XCTestCase {

    private var manager: SubscriptionManager!

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: "isSubscribed")
        manager = SubscriptionManager(forTesting: false)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "isSubscribed")
        manager = nil
    }

    // MARK: - Helpers

    private func makeCustomerInfo(
        proIsActive: Bool,
        productId: String = "com.komodollc.SportsCal.Monthly",
        expirationDate: Date? = nil,
        periodType: PeriodType = .normal,
        willRenew: Bool = true,
        isSandbox: Bool = false,
        billingIssueDetectedAt: Date? = nil
    ) -> CustomerInfo {
        let entitlementInfo = EntitlementInfo(
            identifier: "Pro",
            isActive: proIsActive,
            willRenew: willRenew,
            periodType: periodType,
            latestPurchaseDate: Date(),
            originalPurchaseDate: Date(),
            expirationDate: expirationDate,
            store: .appStore,
            productIdentifier: productId,
            isSandbox: isSandbox,
            billingIssueDetectedAt: billingIssueDetectedAt,
            ownershipType: .purchased
        )
        let entitlements = EntitlementInfos(
            entitlements: ["Pro": entitlementInfo],
            verification: .notRequested
        )
        return CustomerInfo(
            entitlements: entitlements,
            requestDate: Date(),
            firstSeen: Date(),
            originalAppUserId: "test-user"
        )
    }

    private func makeEmptyCustomerInfo() -> CustomerInfo {
        let entitlements = EntitlementInfos(
            entitlements: [:],
            verification: .notRequested
        )
        return CustomerInfo(
            entitlements: entitlements,
            requestDate: Date(),
            firstSeen: Date(),
            originalAppUserId: "test-user"
        )
    }

    private func makeCustomerInfoWithWrongEntitlement(
        identifier: String,
        isActive: Bool = true
    ) -> CustomerInfo {
        let entitlementInfo = EntitlementInfo(
            identifier: identifier,
            isActive: isActive,
            willRenew: true,
            periodType: .normal,
            latestPurchaseDate: Date(),
            originalPurchaseDate: Date(),
            expirationDate: nil,
            store: .appStore,
            productIdentifier: "com.komodollc.SportsCal.Monthly",
            isSandbox: false,
            billingIssueDetectedAt: nil,
            ownershipType: .purchased
        )
        let entitlements = EntitlementInfos(
            entitlements: [identifier: entitlementInfo],
            verification: .notRequested
        )
        return CustomerInfo(
            entitlements: entitlements,
            requestDate: Date(),
            firstSeen: Date(),
            originalAppUserId: "test-user"
        )
    }

    // MARK: - Entitlement Parsing Tests

    func testActiveProEntitlement_setsProTrue() {
        let customerInfo = makeCustomerInfo(proIsActive: true)
        manager.updateProStatus(from: customerInfo)

        XCTAssertTrue(manager.isPro, "Active Pro entitlement should set isPro to true")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "isSubscribed"),
                       "Active Pro entitlement should cache true in UserDefaults")
    }

    func testInactiveProEntitlement_setsProFalse() {
        let customerInfo = makeCustomerInfo(proIsActive: false)
        manager.updateProStatus(from: customerInfo)

        XCTAssertFalse(manager.isPro, "Inactive Pro entitlement should set isPro to false")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "isSubscribed"),
                        "Inactive Pro entitlement should cache false in UserDefaults")
    }

    func testNoProEntitlement_setsProFalse() {
        let customerInfo = makeEmptyCustomerInfo()
        manager.updateProStatus(from: customerInfo)

        XCTAssertFalse(manager.isPro, "No entitlements should set isPro to false")
    }

    func testWrongEntitlementName_setsProFalse() {
        let customerInfo = makeCustomerInfoWithWrongEntitlement(identifier: "Premium")
        manager.updateProStatus(from: customerInfo)

        XCTAssertFalse(manager.isPro,
                        "Entitlement named 'Premium' instead of 'Pro' should not grant access")
    }

    func testExpiredEntitlement_setsProFalse() {
        let pastDate = Date().addingTimeInterval(-86400) // 1 day ago
        let customerInfo = makeCustomerInfo(
            proIsActive: false,
            expirationDate: pastDate
        )
        manager.updateProStatus(from: customerInfo)

        XCTAssertFalse(manager.isPro, "Expired entitlement should set isPro to false")
    }

    func testActiveEntitlementWithFutureExpiry_setsProTrue() {
        let futureDate = Date().addingTimeInterval(86400 * 30) // 30 days from now
        let customerInfo = makeCustomerInfo(
            proIsActive: true,
            expirationDate: futureDate
        )
        manager.updateProStatus(from: customerInfo)

        XCTAssertTrue(manager.isPro, "Active entitlement with future expiry should set isPro to true")
    }

    // MARK: - Subscription State Transition Tests

    func testTransition_freeToSubscribed() {
        XCTAssertFalse(manager.isPro, "Should start as free")

        let customerInfo = makeCustomerInfo(proIsActive: true)
        manager.updateProStatus(from: customerInfo)

        XCTAssertTrue(manager.isPro, "Should transition to subscribed")
    }

    func testTransition_subscribedToExpired() {
        manager.setMockPro(true)
        XCTAssertTrue(manager.isPro, "Should start as subscribed")

        let customerInfo = makeCustomerInfo(proIsActive: false)
        manager.updateProStatus(from: customerInfo)

        XCTAssertFalse(manager.isPro, "Should transition to expired/free")
    }

    func testTransition_subscribedStaysSubscribed() {
        manager.setMockPro(true)

        let customerInfo = makeCustomerInfo(proIsActive: true)
        manager.updateProStatus(from: customerInfo)

        XCTAssertTrue(manager.isPro, "Should remain subscribed")
    }

    func testTransition_freeStaysFree() {
        XCTAssertFalse(manager.isPro, "Should start as free")

        let customerInfo = makeCustomerInfo(proIsActive: false)
        manager.updateProStatus(from: customerInfo)

        XCTAssertFalse(manager.isPro, "Should remain free")
    }

    // MARK: - Entitlement Metadata Tests

    func testMonthlyProduct_entitlementInfo() {
        let customerInfo = makeCustomerInfo(
            proIsActive: true,
            productId: "com.komodollc.SportsCal.Monthly",
            periodType: .normal
        )
        manager.updateProStatus(from: customerInfo)

        XCTAssertTrue(manager.isPro, "Monthly product should grant Pro access")
    }

    func testYearlyProduct_entitlementInfo() {
        let customerInfo = makeCustomerInfo(
            proIsActive: true,
            productId: "com.komodollc.SportsCal.Yearly",
            periodType: .normal
        )
        manager.updateProStatus(from: customerInfo)

        XCTAssertTrue(manager.isPro, "Yearly product should grant Pro access")
    }

    func testTrialPeriod_entitlementInfo() {
        let customerInfo = makeCustomerInfo(
            proIsActive: true,
            productId: "com.komodollc.SportsCal.Yearly",
            periodType: .trial
        )
        manager.updateProStatus(from: customerInfo)

        XCTAssertTrue(manager.isPro, "Trial period should grant Pro access")
    }

    func testSandboxPurchase_entitlementInfo() {
        let customerInfo = makeCustomerInfo(
            proIsActive: true,
            isSandbox: true
        )
        manager.updateProStatus(from: customerInfo)

        XCTAssertTrue(manager.isPro, "Sandbox purchases should grant Pro access")
    }

    func testGracePeriod_entitlementInfo() {
        let customerInfo = makeCustomerInfo(
            proIsActive: true,
            willRenew: true,
            billingIssueDetectedAt: Date()
        )
        manager.updateProStatus(from: customerInfo)

        XCTAssertTrue(manager.isPro,
                       "Billing issue during grace period (isActive still true) should maintain Pro access")
    }

    // MARK: - UserDefaults Sync Tests

    func testUpdateProStatus_syncsToUserDefaults_true() {
        let customerInfo = makeCustomerInfo(proIsActive: true)
        manager.updateProStatus(from: customerInfo)

        XCTAssertTrue(UserDefaults.standard.bool(forKey: "isSubscribed"),
                       "Active entitlement should sync true to UserDefaults")
    }

    func testUpdateProStatus_syncsToUserDefaults_false() {
        // First set to true, then update to false
        manager.setMockPro(true)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "isSubscribed"))

        let customerInfo = makeCustomerInfo(proIsActive: false)
        manager.updateProStatus(from: customerInfo)

        XCTAssertFalse(UserDefaults.standard.bool(forKey: "isSubscribed"),
                        "Inactive entitlement should sync false to UserDefaults")
    }

    func testRapidUpdates_finalStateCorrect() {
        // Simulate rapid customer info updates (e.g., from customerInfoStream)
        for i in 0..<10 {
            let isActive = (i % 2 == 0) // even = active, odd = inactive
            let customerInfo = makeCustomerInfo(proIsActive: isActive)
            manager.updateProStatus(from: customerInfo)
        }

        // Last iteration (i=9) is odd, so isActive = false
        XCTAssertFalse(manager.isPro, "After rapid updates, final state should match last update (false)")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "isSubscribed"),
                        "UserDefaults should match final state")
    }
}
