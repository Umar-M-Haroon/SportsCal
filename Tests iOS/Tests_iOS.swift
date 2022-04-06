//
//  Tests_iOS.swift
//  Tests iOS
//
//  Created by Umar Haroon on 7/2/21.
//

import XCTest

class Tests_iOS: XCTestCase {

    var sports: Sports!
    override func setUp() async throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
        sports = try await NetworkHandler().handleCall(type: nil, year: "2020")
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() async throws {
        // UI tests must launch the application that they test.

        // Use recording to get started writing UI tests.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertNotNil(sports.NBA.games)
    }

}
