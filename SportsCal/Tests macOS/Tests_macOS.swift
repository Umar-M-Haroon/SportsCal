//
//  Tests_macOS.swift
//  Tests macOS
//
//  Hosted-in-app smoke test: the bundle loads inside Scoreline.app, so this
//  verifies the mac app binary itself launched and its module is importable.
//

import XCTest
@testable import Scoreline

class Tests_macOS: XCTestCase {

    func testHostAppIsRunning() throws {
        let bundle = Bundle.main
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, "Scoreline")
    }
}
