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
        // Nudge the interruption monitor to clear the alert WITHOUT navigating:
        // tap a neutral spot near the top (title area), not a game cell.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
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

    /// iPhone Duo audit tour. Fold the device in DeviceHub first, then run with
    /// `TEST_RUNNER_DUO_TAG=outer|inner` so attachments are named per posture.
    /// On the inner display the tour runs twice: portrait, then landscape.
    /// Every step is best-effort: a missing control skips that shot.
    func testDuoTour() throws {
        let tag = ProcessInfo.processInfo.environment["DUO_TAG"] ?? "duo"
        let app = XCUIApplication()
        app.launchArguments += [
            "-shouldShowOnboarding", "0", "-whatsNewLastSeenVersion", "3.3",
            "-shouldShowNBA", "1", "-shouldShowNFL", "1", "-shouldShowNHL", "1",
            "-shouldShowSoccer", "1", "-shouldShowMLB", "1", "-shouldShowCFB", "1",
            "-shouldShowTennis", "1", "-shouldShowGolf", "1", "-shouldShowRacing", "1",
        ]
        addUIInterruptionMonitor(withDescription: "permission") { alert in
            for label in ["Don't Allow", "Allow", "OK", "Not Now", "Dismiss"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        sleep(15)

        // The inner display ignores interface orientation, so posture comes from
        // DeviceHub and is named by the tag.
        tour(app: app, prefix: tag)
    }

    private func tour(app: XCUIApplication, prefix: String) {
        var index = 0
        // XCUIScreen only sees the inner panel, so the host takes the screenshot:
        // write a request into the runner's tmp/duo (the host finds it through the
        // device's data folder) and wait for the host's .done marker.
        let shotDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("duo")
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        func shot(_ name: String) {
            index += 1
            let base = String(format: "%@_%02d_%@", prefix, index, name)
            let request = shotDir.appendingPathComponent("\(base).req")
            let done = shotDir.appendingPathComponent("\(base).done")
            try? Data().write(to: request)
            let deadline = Date().addingTimeInterval(20)
            while !FileManager.default.fileExists(atPath: done.path) && Date() < deadline {
                usleep(200_000)
            }
        }
        func button(_ label: String) -> XCUIElement? {
            let exact = app.buttons[label].firstMatch
            if exact.waitForExistence(timeout: 3) && exact.isHittable { return exact }
            let fuzzy = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
            guard fuzzy.exists else { return nil }
            for _ in 0..<4 where !fuzzy.isHittable {
                app.swipeUp()
                sleep(1)
            }
            return fuzzy.isHittable ? fuzzy : nil
        }
        func dumpTree(_ name: String) {
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "\(prefix)_tree_\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        func goBack() {
            // On the Duo the back button moves into the vertical bar and loses its
            // navigation-bar parent; it keeps the "BackButton" identifier.
            let back = app.buttons["BackButton"].firstMatch
            if back.exists {
                back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                sleep(2)
            }
        }
        func dismissSheet() {
            for label in ["Done", "Close", "Cancel"] {
                if let b = button(label) { b.tap(); sleep(2); return }
            }
            app.swipeDown(velocity: .fast)
            sleep(2)
        }
        // TipKit popovers block everything behind them, so close any that appear.
        func dismissTips() {
            for _ in 0..<3 {
                let close = app.buttons.matching(NSPredicate(format: "label == 'Close'")).allElementsBoundByIndex
                    .first { $0.isHittable }
                guard let close else { return }
                close.tap()
                sleep(1)
            }
        }
        func openTab(_ label: String) -> Bool {
            dismissTips()
            // Tabs sit on a window edge (the bottom bar, or the Duo's trailing
            // rail). Taking the edge-most match keeps "Calendar" from hitting game
            // detail's Add to Calendar button; identifiers vary by posture.
            let window = app.windows.firstMatch.frame
            func edgeness(_ element: XCUIElement) -> CGFloat {
                max(element.frame.maxX / max(window.width, 1), element.frame.maxY / max(window.height, 1))
            }
            let tabs = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
                .filter(\.exists)
                .sorted { edgeness($0) > edgeness($1) }
            if let tab = tabs.first, tab.isHittable {
                tab.tap()
            } else if let tab = tabs.first {
                // Reported unhittable (glass overlay); tap its centre anyway.
                dumpTree("unhittable_tab_\(label)")
                tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            } else {
                dumpTree("missing_tab_\(label)")
                return false
            }
            sleep(4)
            dismissTips()
            return true
        }

        // Games
        if openTab("Games") || true {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
            sleep(1)
            shot("games")
            dumpTree("games")
            app.swipeUp()
            sleep(2)
            shot("games_scrolled")
            app.swipeDown()
            app.swipeDown()
            sleep(2)
            // Game cards are buttons labelled "Live, Team A 47, Team B 58, ..." or
            // "Team A at Team B, 7:30 PM"; tap the first one fully on screen, at its
            // leading edge so the Duo's glass overlays can't swallow the tap.
            let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Live, ' OR label CONTAINS ' at ' OR label CONTAINS ' vs '"))
                .allElementsBoundByIndex.first { $0.isHittable && $0.frame.width > 150 }
            if let card {
                card.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
                sleep(5)
                shot("game_detail")
                app.swipeUp()
                sleep(2)
                shot("game_detail_scrolled")
                goBack()
            } else {
                dumpTree("no_game_card")
            }
            if let gear = button("Settings") {
                gear.tap()
                sleep(3)
                shot("settings")
                dismissSheet()
                sleep(1)
            }
        }

        // Calendar
        if openTab("Calendar") {
            shot("calendar")
            let day = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "October 26")).firstMatch
            if day.exists && day.isHittable {
                day.tap()
                sleep(4)
                shot("calendar_day")
                dismissSheet()
            }
        }

        // Browse
        if openTab("Browse") {
            shot("browse")
            dumpTree("browse")
            for (sport, league) in [("Soccer", "Premier League"), ("Basketball", "NBA"), ("Racing", "Formula 1")] {
                guard let tile = button(sport) else { continue }
                tile.tap()
                sleep(5)
                shot("browse_\(sport.lowercased())")
                if let hub = button(league) {
                    hub.tap()
                    sleep(5)
                    shot("hub_\(sport.lowercased())")
                    goBack()
                }
                goBack()
            }
        }
        _ = openTab("Games")
    }
    #endif
}
