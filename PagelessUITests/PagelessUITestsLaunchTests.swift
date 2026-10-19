//
//  PagelessUITestsLaunchTests.swift
//  PagelessUITests
//
//  Created by andreibalu on 17.03.2026.
//

import XCTest

final class PagelessUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Each UI configuration includes landscape, and the simulator stays rotated after the run.
    /// E2E runs that follow on the same simulator expect portrait.
    override func tearDownWithError() throws {
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
