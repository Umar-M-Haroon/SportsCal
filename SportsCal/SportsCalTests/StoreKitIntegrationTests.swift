//
//  StoreKitIntegrationTests.swift
//  SportsCalTests
//
//  Created by Umar Haroon on 2026-04-12.
//

import XCTest
import StoreKit
import StoreKitTest
@testable import Scoreline

final class StoreKitIntegrationTests: XCTestCase {

    private var session: SKTestSession!

    private let monthlyProductId = "com.komodollc.SportsCal.Monthly"
    private let yearlyProductId = "com.komodollc.SportsCal.Yearly"

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "SportsCalStoreKit")
        session.disableDialogs = true
        session.clearTransactions()
        session.resetToDefaultState()
    }

    override func tearDown() {
        session?.clearTransactions()
        session = nil
    }

    // MARK: - Helpers

    /// The simulator's StoreKit daemon can lag behind a freshly created
    /// SKTestSession, returning [] for the first queries. Retry briefly
    /// before treating an empty catalog as a real failure.
    private func loadProducts(_ ids: [String]) async throws -> [Product] {
        for attempt in 0..<10 {
            let products = try await Product.products(for: ids)
            if products.count == ids.count { return products }
            if attempt < 9 {
                try await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        return try await Product.products(for: ids)
    }

    private func fetchProduct(_ id: String) async throws -> Product {
        let products = try await loadProducts([id])
        return try XCTUnwrap(products.first, "Product \(id) should exist")
    }

    private func purchaseProduct(_ id: String) async throws -> Transaction {
        let product = try await fetchProduct(id)
        let result = try await product.purchase()
        guard case .success(let verification) = result else {
            XCTFail("Purchase should succeed, got: \(result)")
            throw StoreKitTestError.purchaseFailed
        }
        guard case .verified(let transaction) = verification else {
            XCTFail("Transaction should be verified")
            throw StoreKitTestError.verificationFailed
        }
        await transaction.finish()
        return transaction
    }

    private func currentEntitlementProductIds() async -> Set<String> {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                ids.insert(transaction.productID)
            }
        }
        return ids
    }

    // MARK: - Product Catalog Tests

    func testMonthlyProductExists() async throws {
        let products = try await loadProducts([monthlyProductId])
        XCTAssertEqual(products.count, 1, "Monthly product should exist")
    }

    func testMonthlyProductPrice() async throws {
        let product = try await fetchProduct(monthlyProductId)
        XCTAssertEqual(product.price, 0.99, accuracy: 0.01, "Monthly price should be $0.99")
        XCTAssertTrue(product.displayPrice.contains("0.99"),
                       "Display price should contain 0.99, got: \(product.displayPrice)")
    }

    func testMonthlyProductIsSubscription() async throws {
        let product = try await fetchProduct(monthlyProductId)
        let subscription = try XCTUnwrap(product.subscription, "Monthly should be a subscription product")
        XCTAssertEqual(subscription.subscriptionPeriod.unit, .month, "Period unit should be month")
        XCTAssertEqual(subscription.subscriptionPeriod.value, 1, "Period value should be 1")
    }

    func testMonthlyProductNoTrial() async throws {
        let product = try await fetchProduct(monthlyProductId)
        let subscription = try XCTUnwrap(product.subscription)
        XCTAssertNil(subscription.introductoryOffer, "Monthly product should have no trial")
    }

    func testYearlyProductExists() async throws {
        let products = try await loadProducts([yearlyProductId])
        XCTAssertEqual(products.count, 1, "Yearly product should exist")
    }

    func testYearlyProductPrice() async throws {
        let product = try await fetchProduct(yearlyProductId)
        XCTAssertEqual(product.price, 6.99, accuracy: 0.01, "Yearly price should be $6.99")
        XCTAssertTrue(product.displayPrice.contains("6.99"),
                       "Display price should contain 6.99, got: \(product.displayPrice)")
    }

    func testYearlyProductIsSubscription() async throws {
        let product = try await fetchProduct(yearlyProductId)
        let subscription = try XCTUnwrap(product.subscription, "Yearly should be a subscription product")
        XCTAssertEqual(subscription.subscriptionPeriod.unit, .year, "Period unit should be year")
        XCTAssertEqual(subscription.subscriptionPeriod.value, 1, "Period value should be 1")
    }

    func testYearlyProductHasFreeTrial() async throws {
        let product = try await fetchProduct(yearlyProductId)
        let subscription = try XCTUnwrap(product.subscription)
        let offer = try XCTUnwrap(subscription.introductoryOffer, "Yearly should have an introductory offer")
        XCTAssertEqual(offer.paymentMode, .freeTrial, "Offer should be a free trial")
        XCTAssertEqual(offer.period.unit, .week, "Trial period should be in weeks")
        XCTAssertEqual(offer.period.value, 1, "Trial should be 1 week")
    }

    func testBothProductsExist() async throws {
        let products = try await loadProducts([monthlyProductId, yearlyProductId])
        XCTAssertEqual(products.count, 2, "Both products should exist")
    }

    func testBothProductsInSameSubscriptionGroup() async throws {
        let monthly = try await fetchProduct(monthlyProductId)
        let yearly = try await fetchProduct(yearlyProductId)

        let monthlyGroup = try XCTUnwrap(monthly.subscription?.subscriptionGroupID)
        let yearlyGroup = try XCTUnwrap(yearly.subscription?.subscriptionGroupID)

        XCTAssertEqual(monthlyGroup, yearlyGroup,
                        "Both products should be in the same subscription group")
    }

    func testProductDescriptions() async throws {
        let monthly = try await fetchProduct(monthlyProductId)
        let yearly = try await fetchProduct(yearlyProductId)

        XCTAssertFalse(monthly.description.isEmpty, "Monthly should have a description")
        XCTAssertFalse(yearly.description.isEmpty, "Yearly should have a description")
    }

    func testInvalidProductIdReturnsEmpty() async throws {
        let products = try await Product.products(for: ["com.invalid.nonexistent.product"])
        XCTAssertTrue(products.isEmpty, "Invalid product ID should return empty results")
    }

    // MARK: - Purchase Flow Tests

    func testPurchaseMonthly_succeeds() async throws {
        let product = try await fetchProduct(monthlyProductId)
        let result = try await product.purchase()

        guard case .success(let verification) = result else {
            XCTFail("Monthly purchase should succeed")
            return
        }
        guard case .verified(let transaction) = verification else {
            XCTFail("Transaction should be verified")
            return
        }
        XCTAssertEqual(transaction.productID, monthlyProductId)
        await transaction.finish()
    }

    func testPurchaseYearly_succeeds() async throws {
        let product = try await fetchProduct(yearlyProductId)
        let result = try await product.purchase()

        guard case .success(let verification) = result else {
            XCTFail("Yearly purchase should succeed")
            return
        }
        guard case .verified(let transaction) = verification else {
            XCTFail("Transaction should be verified")
            return
        }
        XCTAssertEqual(transaction.productID, yearlyProductId)
        await transaction.finish()
    }

    func testPurchaseMonthly_transactionFinishes() async throws {
        let transaction = try await purchaseProduct(monthlyProductId)

        // After finishing, should not appear in unfinished transactions
        var unfinishedIds = Set<String>()
        for await result in Transaction.unfinished {
            if case .verified(let t) = result {
                unfinishedIds.insert(t.productID)
            }
        }
        XCTAssertFalse(unfinishedIds.contains(monthlyProductId),
                         "Finished transaction should not appear in unfinished")
    }

    func testPurchaseYearly_startsWithTrial() async throws {
        let product = try await fetchProduct(yearlyProductId)
        let result = try await product.purchase()

        guard case .success(let verification) = result,
              case .verified(let transaction) = verification else {
            XCTFail("Purchase should succeed and verify")
            return
        }

        XCTAssertEqual(transaction.offerType, .introductory,
                        "First yearly purchase should start with introductory offer (trial)")
        await transaction.finish()
    }

    // MARK: - Subscription Lifecycle Tests

    func testSubscription_appearsInCurrentEntitlements() async throws {
        _ = try await purchaseProduct(monthlyProductId)

        let entitledProducts = await currentEntitlementProductIds()
        XCTAssertTrue(entitledProducts.contains(monthlyProductId),
                       "Purchased subscription should appear in current entitlements")
    }

    func testSubscription_expiryRemovesFromEntitlements() async throws {
        _ = try await purchaseProduct(monthlyProductId)

        try session.expireSubscription(productIdentifier: monthlyProductId)

        let entitledProducts = await currentEntitlementProductIds()
        XCTAssertFalse(entitledProducts.contains(monthlyProductId),
                        "Expired subscription should not appear in current entitlements")
    }

    func testSubscription_renewalCreatesNewTransaction() async throws {
        let originalTransaction = try await purchaseProduct(monthlyProductId)

        try session.forceRenewalOfSubscription(productIdentifier: monthlyProductId)

        // Check that there's a newer transaction
        var latestTransaction: Transaction?
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == monthlyProductId {
                latestTransaction = t
            }
        }

        let renewed = try XCTUnwrap(latestTransaction, "Should have a renewed transaction")
        XCTAssertNotEqual(renewed.id, originalTransaction.id,
                           "Renewed transaction should have a different ID")
    }

    func testTrialToPayment_renewsPastTrial() async throws {
        // Purchase yearly (starts with trial)
        let trialTransaction = try await purchaseProduct(yearlyProductId)
        XCTAssertEqual(trialTransaction.offerType, .introductory, "Should start with trial")

        // Force renewal past trial
        try session.forceRenewalOfSubscription(productIdentifier: yearlyProductId)

        var latestTransaction: Transaction?
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == yearlyProductId {
                latestTransaction = t
            }
        }

        let paidTransaction = try XCTUnwrap(latestTransaction)
        XCTAssertNotEqual(paidTransaction.offerType, .introductory,
                           "Renewal after trial should not be introductory")
    }

    func testUpgrade_monthlyToYearly() async throws {
        _ = try await purchaseProduct(monthlyProductId)

        // Upgrade to yearly (same subscription group)
        _ = try await purchaseProduct(yearlyProductId)

        let entitledProducts = await currentEntitlementProductIds()
        XCTAssertTrue(entitledProducts.contains(yearlyProductId),
                       "Yearly subscription should be active after upgrade")
        // Monthly may or may not still appear depending on StoreKit behavior,
        // but yearly should definitely be present
    }

    func testDowngrade_yearlyToMonthly() async throws {
        _ = try await purchaseProduct(yearlyProductId)

        // Downgrade in same subscription group — StoreKit queues the downgrade
        // for the next renewal period. The yearly subscription remains active.
        let product = try await fetchProduct(monthlyProductId)
        let result = try await product.purchase()

        // A downgrade may succeed immediately or return pending depending on
        // StoreKit Testing behavior. Either way, yearly should still be active.
        let entitledProducts = await currentEntitlementProductIds()
        XCTAssertTrue(entitledProducts.contains(yearlyProductId),
                       "Yearly subscription should remain active until renewal period ends")
    }

    // MARK: - Error Handling Tests

    func testFailedTransaction_returnsUserCancelled() async throws {
        session.failTransactionsEnabled = true
        let product = try await fetchProduct(monthlyProductId)
        let result = try await product.purchase()

        guard case .userCancelled = result else {
            XCTFail("Failed transaction should return .userCancelled, got: \(result)")
            return
        }
        session.failTransactionsEnabled = false
    }

    func testFailedTransaction_noEntitlementGranted() async throws {
        session.failTransactionsEnabled = true
        let product = try await fetchProduct(monthlyProductId)
        _ = try await product.purchase()
        session.failTransactionsEnabled = false

        let entitledProducts = await currentEntitlementProductIds()
        XCTAssertFalse(entitledProducts.contains(monthlyProductId),
                        "Failed purchase should not grant entitlement")
    }

    func testInterruptedTransaction_pending() async throws {
        session.interruptedPurchasesEnabled = true
        let product = try await fetchProduct(monthlyProductId)
        let result = try await product.purchase()

        guard case .pending = result else {
            XCTFail("Interrupted purchase should return .pending, got: \(result)")
            return
        }
        session.interruptedPurchasesEnabled = false
    }

    // MARK: - Restore Tests

    func testRestorePurchases_findsActiveSubscription() async throws {
        _ = try await purchaseProduct(monthlyProductId)

        // Even without explicit restore, Transaction.currentEntitlements reflects server state
        let entitledProducts = await currentEntitlementProductIds()
        XCTAssertTrue(entitledProducts.contains(monthlyProductId),
                       "Active subscription should be found via currentEntitlements")
    }

    func testRestorePurchases_noActiveSubscription() async throws {
        // No purchases made
        let entitledProducts = await currentEntitlementProductIds()
        XCTAssertTrue(entitledProducts.isEmpty,
                       "Without any purchases, currentEntitlements should be empty")
    }
}

// MARK: - Test Errors

private enum StoreKitTestError: Error {
    case purchaseFailed
    case verificationFailed
}
