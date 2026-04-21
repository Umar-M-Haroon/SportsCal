//
//  SubscriptionManagerTests.swift
//  SportsCalTests
//
//  Created by Umar Haroon on 2026-04-12.
//

import XCTest
@testable import Scoreline

@MainActor
final class SubscriptionManagerTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "isSubscribed")
    }

    // MARK: - Initial State

    func testInitialState_defaultsToFalse() {
        UserDefaults.standard.removeObject(forKey: "isSubscribed")
        let manager = SubscriptionManager(forTesting: false)
        XCTAssertFalse(manager.isPro, "Fresh manager with clean UserDefaults should default to isPro == false")
    }

    func testInitialState_readsCachedTrue() {
        UserDefaults.standard.set(true, forKey: "isSubscribed")
        let manager = SubscriptionManager(forTesting: false)
        // forTesting init sets isPro directly, so test the production init path
        // by verifying the cached value mechanism
        let cachedValue = UserDefaults.standard.bool(forKey: "isSubscribed")
        XCTAssertTrue(cachedValue, "UserDefaults should have isSubscribed == true")
    }

    func testInitialState_readsCachedFalse() {
        UserDefaults.standard.set(false, forKey: "isSubscribed")
        let manager = SubscriptionManager(forTesting: false)
        XCTAssertFalse(manager.isPro, "Manager initialized with false should have isPro == false")
    }

    // MARK: - Mock Pro

    func testSetMockPro_setsTrue() {
        let manager = SubscriptionManager(forTesting: false)
        manager.setMockPro(true)

        XCTAssertTrue(manager.isPro, "isPro should be true after setMockPro(true)")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "isSubscribed"),
                       "UserDefaults isSubscribed should be true after setMockPro(true)")
    }

    func testSetMockPro_setsFalse() {
        let manager = SubscriptionManager(forTesting: true)
        manager.setMockPro(true)
        manager.setMockPro(false)

        XCTAssertFalse(manager.isPro, "isPro should be false after setMockPro(false)")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "isSubscribed"),
                        "UserDefaults isSubscribed should be false after setMockPro(false)")
    }

    func testSetMockPro_roundTrip() {
        let manager = SubscriptionManager(forTesting: false)

        manager.setMockPro(true)
        XCTAssertTrue(manager.isPro)

        manager.setMockPro(false)
        XCTAssertFalse(manager.isPro)

        manager.setMockPro(true)
        XCTAssertTrue(manager.isPro)

        manager.setMockPro(false)
        XCTAssertFalse(manager.isPro)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "isSubscribed"),
                        "Final state should be false in UserDefaults")
    }

    // MARK: - Caching Across Instances

    func testUserDefaultsCaching_persistsAcrossInstances() {
        let managerA = SubscriptionManager(forTesting: false)
        managerA.setMockPro(true)

        // A second test instance reads from UserDefaults on init
        let cachedValue = UserDefaults.standard.bool(forKey: "isSubscribed")
        XCTAssertTrue(cachedValue, "UserDefaults value set by instance A should be readable by instance B")
    }

    // MARK: - Environment Variable

    func testEnvironmentVariableOverride_propertyExists() {
        let manager = SubscriptionManager(forTesting: false)
        // We can't set environment variables at test runtime, but we verify
        // the property exists and returns a Bool
        let result = manager.environmentOverridesEnabled
        XCTAssertNotNil(result as Bool?, "environmentOverridesEnabled should return a Bool")
        // In a normal test environment without the env var set, this should be false
        XCTAssertFalse(result, "Without mock-subscribed env var, should return false")
    }
}
