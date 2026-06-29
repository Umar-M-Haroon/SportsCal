//
//  SportsCalUITests.swift
//  SportsCalUITests
//
//  Created by Umar Haroon on 12/8/21.
//

import XCTest

class SportsCalUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// Captures App Store screenshots of the Mac app's main screens.
    /// Run on macOS: xcodebuild test -scheme "SportsCal (iOS)" -destination 'platform=macOS'
    ///   -only-testing:SportsCalUITests/SportsCalUITests/testCaptureMacScreenshots
    func testCaptureMacScreenshots() throws {
        let app = XCUIApplication()
        app.launch()
        // Let the games feed fetch + render before the first capture.
        sleep(10)
        capture("01_Games", app: app)

        // Best-effort tab navigation; each tab is optional so a missing/renamed
        // control never fails the run (we still get the screens that exist).
        for (idx, label) in ["Calendar", "Browse"].enumerated() {
            let control = app.buttons[label].firstMatch
            if control.waitForExistence(timeout: 3) {
                #if os(macOS)
                control.click()
                #else
                control.tap()
                #endif
                sleep(4)
                capture(String(format: "%02d_%@", idx + 2, label), app: app)
            }
        }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        // Window-only screenshot (excludes desktop background) when available.
        let target = app.windows.firstMatch.exists ? app.windows.firstMatch : app
        let attachment = XCTAttachment(screenshot: target.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    #if os(iOS)
    /// App Store screenshots. Seeds sports + skips onboarding via launch args
    /// (NSArgumentDomain), auto-dismisses the notification prompt, then captures
    /// the main tabs as attachments. Appearance follows the simulator — run with
    /// the sim set to dark (`xcrun simctl ui <udid> appearance dark`) or via the
    /// Snapfile `dark_mode` option. Extract with:
    ///   xcrun xcresulttool export attachments --path <result.xcresult> --output-path <dir>
    func testAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-shouldShowOnboarding", "0",
            "-shouldShowNBA", "1", "-shouldShowNFL", "1", "-shouldShowNHL", "1",
            "-shouldShowSoccer", "1", "-shouldShowMLB", "1", "-shouldShowWorldCup", "1",
        ]
        // Dismiss the system notification permission alert if it appears.
        addUIInterruptionMonitor(withDescription: "permission") { alert in
            for label in ["Don't Allow", "Allow", "OK", "Dismiss"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        sleep(12)            // network fetch + render + logo load
        app.tap()            // nudge the interruption monitor to clear the alert
        sleep(1)
        capture("01_Games", app: app)

        func tab(_ label: String, _ shot: String) {
            let button = app.tabBars.buttons[label].firstMatch
            if button.waitForExistence(timeout: 5) {
                button.tap()
                sleep(3)
                capture(shot, app: app)
            }
        }
        tab("Browse", "02_Browse")
        tab("Calendar", "03_Calendar")
    }
    #endif
}
