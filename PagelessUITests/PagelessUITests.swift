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

    /// Guards Apple 3.1.1 reachability: the subscription has to be visible from Settings without
    /// signing in to iCloud first. A prior build was rejected for hiding it.
    @MainActor
    func testSettingsShowsUnpagedPlusCard() throws {
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments += ["-onboardingComplete", "YES"]
        app.launch()

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 15))
        settingsButton.tap()

        let plusHeading = app.staticTexts["Unpaged Plus"]
        let appeared = plusHeading.waitForExistence(timeout: 10)
        // Let the sheet finish presenting so the capture isn't a mid-animation frame.
        Thread.sleep(forTimeInterval: 1.5)

        let cardScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        cardScreenshot.name = "Unpaged Plus Card"
        cardScreenshot.lifetime = .keepAlways
        add(cardScreenshot)

        XCTAssertTrue(appeared, "Settings must show the Unpaged Plus card unconditionally")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
