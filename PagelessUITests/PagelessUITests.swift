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

        // Tapping the already-active tab opens the catalog-source menu (LibriVox + Audiobookshelf)
        // rather than navigating away.
        shelvesTab.tap()
        // SwiftUI menu items don't surface their accessibility identifiers, so match by label.
        let audiobookshelfSource = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH 'Audiobookshelf'"))
            .firstMatch
        XCTAssertTrue(audiobookshelfSource.waitForExistence(timeout: 5))
        XCTAssertTrue(shelvesTab.exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    /// Marketing screenshot capture for the 1.4.0 App Store set. Not part of the regular suite's
    /// intent — it seeds a throwaway public-domain library (see `ScreenshotSeeder`, DEBUG-only,
    /// gated on UITEST_SEED_SCREENSHOTS) and walks six real screens, attaching a full-screen
    /// XCTAttachment at each stop. Run in isolation:
    /// xcodebuild test -only-testing:PagelessUITests/PagelessUITests/testCaptureMarketingScreenshots
    @MainActor
    func testCaptureMarketingScreenshots() throws {
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments += ["-onboardingComplete", "YES"]
        app.launchEnvironment["UITEST_SEED_SCREENSHOTS"] = "1"
        app.launch()

        func snap(_ name: String, settle: TimeInterval = 1.2) {
            Thread.sleep(forTimeInterval: settle)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
        }

        // SwiftUI often flattens a Text() nested inside a Button/Menu into the parent's single
        // accessibility element (type .button), so it never shows up in app.staticTexts[...].
        // Scanning all descendants by label (regardless of element type) is what actually works
        // for the tab picker and other button-wrapped labels.
        func element(labeled label: String, exact: Bool = true) -> XCUIElement {
            let format = exact ? "label ==[c] %@" : "label CONTAINS[c] %@"
            let predicate = NSPredicate(format: format, label)
            return app.descendants(matching: .any).matching(predicate).firstMatch
        }

        func tap(labeled label: String, exact: Bool = true, timeout: TimeInterval = 10) {
            let el = element(labeled: label, exact: exact)
            XCTAssertTrue(el.waitForExistence(timeout: timeout), "Never found element labeled '\(label)'")
            el.tap()
        }

        // The tab picker is a horizontally-swipeable page host, not a native TabView — all three
        // tabs' content stays mounted side by side (just scrolled offscreen on the X axis), so a
        // plain staticTexts["X"] lookup can resolve to an invisible duplicate on a different tab's
        // page (e.g. "Pride and Prejudice" is both our seeded library book AND, coincidentally, a
        // real LibriVox catalog title on the Shelves page). `isHittable` isn't the right filter —
        // the on-screen instance may still need a *vertical* scroll-into-view, which only a real
        // `.tap()` call performs. Instead, pick by X origin: the current page's content sits within
        // [0, screen width); an offscreen sibling page sits a full screen-width to either side.
        //
        // A second trap: the seeded book is marked `playedRecently`, so it becomes the "now
        // playing" book and the mini-player bar (docked near the bottom of every tab, always
        // on-screen) also shows its title as a plain StaticText. That docked title sits inside
        // [0, screen width] just like the real grid card, so a bare label match on the Library
        // page can resolve to the mini player instead — tapping it opens the full-screen Player,
        // not the book's detail screen. Target the grid card's Button (whose accessibility label
        // is the whole card, e.g. "Playing, Pride and Prejudice, Jane Austen, …") and additionally
        // exclude anything sitting in the mini player's bottom strip.
        func tapHittable(_ label: String, timeout: TimeInterval = 15) {
            let deadline = Date().addingTimeInterval(timeout)
            let screenWidth = app.frame.width
            let screenHeight = app.frame.height
            let miniPlayerTop = screenHeight - 100 // mini player docks in the bottom ~100pt strip
            while Date() < deadline {
                let matches = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label))
                var onScreenCard: XCUIElement?
                for i in 0..<matches.count {
                    let candidate = matches.element(boundBy: i)
                    guard candidate.exists else { continue }
                    let frame = candidate.frame
                    if frame.midX >= 0 && frame.midX <= screenWidth && frame.midY < miniPlayerTop {
                        onScreenCard = candidate
                        break
                    }
                }
                if let onScreenCard {
                    onScreenCard.tap()
                    return
                }
                Thread.sleep(forTimeInterval: 0.3)
            }
            XCTFail("Never found an on-screen grid card labeled '\(label)'")
        }

        // Seeding (silent-audio synthesis + real import + optional ABS sign-in) runs async on
        // launch — give it generous room before touching anything. "Pride and Prejudice" is the
        // last book seeded, so waiting on it (rather than the first-seeded "Meditations") ensures
        // the whole library — including the favorites used by later slides — is fully in place.
        let seedAnchor = app.staticTexts["Pride and Prejudice"]
        XCTAssertTrue(seedAnchor.waitForExistence(timeout: 180), "Screenshot seeding did not finish in time")

        // --- Slide 1: Shelves (LibriVox) ---
        tap(labeled: "Shelves")
        XCTAssertTrue(app.staticTexts["LANGUAGE"].waitForExistence(timeout: 30))
        // Wait for the curated classics; the full offline index can take several minutes.
        XCTAssertTrue(app.staticTexts["Popular Classics"].waitForExistence(timeout: 30))
        snap("01-shelves-librivox")

        // --- Slide 5: Shelves (Audiobookshelf), only if a server was actually configured ---
        // Tapping "Shelves" while it's already the active tab opens the catalog-source menu
        // (see testShelvesIsTheHomeTabWhenChosen) rather than switching pages. Only do that
        // second tap when we know ABS creds were forwarded — otherwise it just opens a menu
        // that nothing dismisses on purpose, and the *next* tap (meant for "Library") ends up
        // dismissing the menu instead of switching tabs, leaving the whole rest of the run
        // stuck on the Shelves page.
        let credentials: [String: String]? = {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/shots140/abs.json")) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: String]
        }()
        if let credentials, let server = credentials["url"],
           let username = credentials["username"], let password = credentials["password"] {
            tap(labeled: "Shelves") // reopen the source menu
            let absSource = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Audiobookshelf'")).firstMatch
            if absSource.waitForExistence(timeout: 10) {
                absSource.tap()
                let serverField = app.textFields["abs.connect.server"]
                XCTAssertTrue(serverField.waitForExistence(timeout: 10))
                serverField.tap(); serverField.typeText(server)
                let userField = app.textFields["abs.connect.username"]
                userField.tap(); userField.typeText(username)
                let passField = app.secureTextFields["abs.connect.password"]
                passField.tap(); passField.typeText(password)
                app.buttons["Connect"].tap()
                if app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Frankenstein'")).firstMatch.waitForExistence(timeout: 30) {
                    snap("05-shelves-audiobookshelf")
                }
            }
        }

        // --- Slide 2: Library ---
        tap(labeled: "Library")
        XCTAssertTrue(app.staticTexts["Walden"].waitForExistence(timeout: 15), "Library tab never showed seeded books")
        snap("02-library")

        // --- Slide 4: Moments (on the Pride and Prejudice detail screen) ---
        tapHittable("Pride and Prejudice")
        let momentsDisclosure = element(labeled: "moments", exact: false)
        XCTAssertTrue(momentsDisclosure.waitForExistence(timeout: 15))
        app.swipeUp()
        if momentsDisclosure.exists {
            momentsDisclosure.tap()
        }
        snap("04-moments")

        // --- Slide 3: Player ---
        // Scroll back up so the Continue button (near the top of the detail screen) is reachable.
        app.swipeDown()
        app.swipeDown()
        let continueButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Continue'")).firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        continueButton.tap()
        _ = app.staticTexts["Pride and Prejudice"].waitForExistence(timeout: 10)
        snap("03-player")

        // --- Slide 6: Essentials (Equalizer) ---
        tap(labeled: "EQ")
        _ = app.staticTexts["Equalizer"].waitForExistence(timeout: 10)
        app.swipeUp()
        snap("06-essentials-eq")
    }

    /// Fresh, light-appearance captures for the marketing website. The extra fixture data is
    /// enabled only for this test; normal screenshot captures keep their existing library.
    @MainActor
    func testCaptureSiteScreenshots() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingComplete", "YES", "-forceDarkMode", "NO"]
        app.launchEnvironment["UITEST_SEED_SCREENSHOTS"] = "1"
        app.launchEnvironment["UITEST_SITE_SCREENSHOTS"] = "1"
        app.launch()

        func snap(_ name: String) {
            Thread.sleep(forTimeInterval: 2)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        func scrollUntilHittable(_ element: XCUIElement, attempts: Int = 8) {
            for _ in 0..<attempts {
                if element.isHittable { return }
                app.swipeUp()
            }
            XCTAssertTrue(element.isHittable, "Could not scroll to \(element.label)")
        }

        // The final imported book is the launch-seeding anchor. Reading sessions and the
        // catalog versions are inserted before the seeder returns.
        XCTAssertTrue(app.staticTexts["Pride and Prejudice"].waitForExistence(timeout: 180))

        let activity = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'ACTIVITY'")).firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 20), "Seeded reading activity was not shown")
        activity.tap()
        XCTAssertTrue(app.staticTexts["Page by page."].waitForExistence(timeout: 15))
        snap("stats")

        app.buttons["Library"].tap()
        app.buttons.matching(NSPredicate(format: "label ==[c] 'Library'")).firstMatch.tap()
        let prideCards = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Pride and Prejudice'"))
        XCTAssertTrue(prideCards.firstMatch.waitForExistence(timeout: 15))
        let prideCard = (0..<prideCards.count).map { prideCards.element(boundBy: $0) }
            .first { $0.frame.midY < app.frame.height - 100 && $0.frame.midX >= 0 && $0.frame.midX <= app.frame.width }
        XCTAssertNotNil(prideCard, "Seeded library card was not on screen")
        prideCard?.tap()
        let recap = app.staticTexts["Where Was I?"]
        XCTAssertTrue(recap.waitForExistence(timeout: 15), "Seeded recap was not displayed")
        scrollUntilHittable(recap)
        snap("recap")

        let version = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Version 2'")).firstMatch
        scrollUntilHittable(version)
        version.tap()
        let recordings = app.staticTexts["Other Recordings"]
        XCTAssertTrue(recordings.waitForExistence(timeout: 15))
        scrollUntilHittable(recordings)
        snap("recordings")
    }
}
