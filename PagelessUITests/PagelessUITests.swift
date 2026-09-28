//
//  PagelessUITests.swift
//  PagelessUITests
//
//  Created by andreibalu on 17.03.2026.
//

import XCTest

final class PagelessUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testShelvesIsTheHomeTabWhenChosen() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-onboardingComplete", "YES",
            "-startOnFreeBooks", "YES",
            "-shelvesSource", "librivox"
        ]
        app.launch()

        let shelvesTab = app.buttons["shelvesTab"]
        XCTAssertTrue(shelvesTab.waitForExistence(timeout: 15))
        XCTAssertTrue(shelvesTab.label.contains("Shelves"))

        let shelvesScreenshot = XCTAttachment(screenshot: app.screenshot())
        shelvesScreenshot.name = "Shelves Tab"
        shelvesScreenshot.lifetime = .keepAlways
        add(shelvesScreenshot)

        // Tapping the already-active tab is a no-op while LibriVox is the only registered source
        // (the source menu appears once a second source exists) — it must not navigate away.
        shelvesTab.tap()
        XCTAssertTrue(shelvesTab.exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
