package dev.unpaged.android.e2e

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.UiSelector
import androidx.test.uiautomator.Until
import java.io.File
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.Rule
import org.junit.rules.TestWatcher
import org.junit.runner.Description
import org.junit.runner.RunWith

/** Black-box app and system-picker journeys; no app hooks, repository calls or DB assertions. */
@RunWith(AndroidJUnit4::class)
class LibraryE2ETest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val app = "dev.unpaged.android.development"

    @get:Rule val failureEvidence = object : TestWatcher() {
        override fun failed(error: Throwable, description: Description) {
            runCatching { screenshot("failed-${description.methodName}") }
            runCatching {
                val file = File(captureDirectory(), "failed-${description.methodName}.xml")
                device.dumpWindowHierarchy(file)
                persistCapture(file)
            }
        }
    }

    @Before fun freshLibrary() {
        assertEquals("Use tools/run-e2e.sh on its dedicated emulator", "true",
            InstrumentationRegistry.getArguments().getString("e2eApproved"))
        assertEquals("1", device.executeShellCommand("getprop ro.kernel.qemu").trim())
        assertTrue(device.executeShellCommand("getprop ro.boot.qemu.avd_name").trim().startsWith("Unpaged_E2E_"))
        for (setting in listOf("window_animation_scale", "transition_animation_scale", "animator_duration_scale"))
            device.executeShellCommand("settings put global $setting 0")
        device.executeShellCommand("pm clear $app")
        device.executeShellCommand("cmd uimode night no")
        launch()
        field("tab.Library").click()
    }

    @Test fun libraryUsesIosHeaderAndEmptyState() {
        visible(By.text("My Library"))
        visible(By.text("Your Library Is Empty"))
        screenshot("empty-light")
        device.executeShellCommand("cmd uimode night yes")
        visible(By.text("My Library"))
        screenshot("empty-dark")
        tapText("Browse Shelves")
        field("shelves.placeholder")
        screenshot("shelves-dark")
        device.executeShellCommand("cmd uimode night no")
        field("shelves.placeholder")
        screenshot("shelves-light")
        field("tab.Library").click()
    }

    @Test fun realPickerImportMetadataOrderingAndProcessRelaunch() {
        pick("Chapter 10.wav", "Chapter 2.wav", "Chapter 1.wav")
        field("import.title").setText("E2E The Listening Book")
        field("import.author").setText("Fixture Author")
        tapText("Save")
        tapText("E2E The Listening Book")
        field("book.tracks").click()
        val first = visible(By.text("Chapter 1"))
        val second = visible(By.text("Chapter 2"))
        val tenth = visible(By.text("Chapter 10"))
        assertTrue(first.visibleBounds.top < second.visibleBounds.top)
        assertTrue(second.visibleBounds.top < tenth.visibleBounds.top)
        device.setOrientationLeft()
        visible(By.text("Fixture Author"))
        device.setOrientationNatural()
        device.executeShellCommand("am force-stop $app")
        launch()
        field("tab.Library").click()
        tapText("E2E The Listening Book")
        visible(By.text("Fixture Author"))
        field("book.tracks").click()
        visible(By.text("Chapter 10"))
        screenshot("import-persisted-detail")
    }

    @Test fun cancelPickerAndReviewLeavesLibraryEmpty() {
        tapDescription("Import Audiobook")
        visible(By.pkg("com.android.documentsui"))
        repeat(6) {
            if (!device.hasObject(By.pkg(app))) {
                device.pressBack()
                device.wait(Until.hasObject(By.pkg(app)), 500)
            }
        }
        visible(By.text("Your Library Is Empty"))
        pick("Another.wav")
        tapText("Cancel")
        visible(By.text("Your Library Is Empty"))
        relaunch()
        visible(By.text("Your Library Is Empty"))
    }

    @Test fun duplicateImportRetainsOneBookAfterRelaunch() {
        saveBook("Duplicate Fixture", "Fixture Author", "Another.wav")
        openPicker("Another.wav")
        visible(By.text("This audiobook is already in your library."))
        tapText("OK")
        relaunch()
        visible(By.text("Duplicate Fixture"))
        visible(By.text("1"))
    }

    @Test fun invalidAudioLeavesNoPartialBook() {
        openPicker("Invalid.mp3")
        visible(By.text("Could not complete this step"))
        visible(By.text("Choose readable audiobook files with a valid audio track and duration. Try MP3, M4A, M4B, AAC, WAV, OGG, Opus or FLAC."))
        tapText("OK")
        relaunch()
        visible(By.text("Your Library Is Empty"))
    }

    @Test fun removalRequiresConfirmationAndPreservesProviderOriginal() {
        saveBook("Removal Fixture", "Fixture Author", "Another.wav")
        text("Removal Fixture").longClick()
        tapText("Delete")
        tapText("Cancel")
        visible(By.text("Fixture Author"))
        text("Removal Fixture").longClick()
        tapText("Delete")
        tapText("Also Delete Files")
        visible(By.text("Your Library Is Empty"))
        relaunch()
        visible(By.text("Your Library Is Empty"))
        // Import the same original through the provider again; app deletion did not remove it.
        saveBook("Original Still Available", "Fixture Author", "Another.wav")
        visible(By.text("Original Still Available"))
    }

    @Test fun matchingIosFixturesCaptureLibraryDetailAndReviewInBothThemes() {
        saveBook("E2E The Listening Book", "Fixture Author", "Chapter 2.wav", "Chapter 1.wav")
        tapDescription("Add favorite")
        saveBook("E2E Another Book", "Another Fixture Author", "Another.wav")
        screenshot("library-light")
        field("tab.Favorites").click()
        visible(By.text("E2E The Listening Book"))
        screenshot("favorites-light")
        device.executeShellCommand("cmd uimode night yes")
        visible(By.text("E2E The Listening Book"))
        screenshot("favorites-dark")
        field("tab.Library").click()
        device.executeShellCommand("cmd uimode night yes")
        visible(By.text("E2E Another Book"))
        screenshot("library-dark")
        tapText("E2E The Listening Book")
        visible(By.text("Fixture Author"))
        screenshot("detail-dark")
        device.executeShellCommand("cmd uimode night no")
        visible(By.text("Fixture Author"))
        screenshot("detail-light")
        visible(By.text("Play"))
        visible(By.text("0% · 10m remaining"))
        visible(By.text("0 moments"))
        field("book.moments").click()
        visible(By.text("No saved moments yet"))
        screenshot("detail-moments-empty-light")
        field("book.moments").click()
        assertTrue(device.wait(Until.gone(By.text("No saved moments yet")), 15_000))
        settleLayout()
        field("book.tracks").click()
        visible(By.text("Chapter 1"))
        screenshot("detail-expanded-light")
        device.pressBack()
        visible(By.text("My Library"))
        tapDescription("Settings")
        visible(By.text("Listening preferences."))
        screenshot("settings-light")
        expandSettings()
        screenshot("settings2-light")
        scrollTo("settings.appearance.Dark")
        screenshot("settings3-light")
        device.executeShellCommand("cmd uimode night yes")
        settleLayout()
        visible(By.text("Settings"))
        expandSettings()
        scrollTo("settings.appearance.System")
        screenshot("settings-dark")
        device.executeShellCommand("cmd uimode night no")
        settleLayout()
        visible(By.text("Settings"))
        tapText("Done")
        pick("E2E Import.wav")
        visible(By.desc("Title"))
        visible(By.desc("Author"))
        field("import.author").setText("Rotation Fixture Author")
        device.setOrientationLeft()
        assertEquals("Rotation Fixture Author", field("import.author").text)
        device.setOrientationNatural()
        assertEquals("Rotation Fixture Author", field("import.author").text)
        tapText("Cancel")
        pick("E2E Import.wav")
        visible(By.text("Author"))
        screenshot("review-light")
        tapText("Cancel")
        device.executeShellCommand("cmd uimode night yes")
        visible(By.text("My Library"))
        pick("E2E Import.wav")
        visible(By.text("Author"))
        screenshot("review-dark")
        tapText("Cancel")
    }

    @Test fun favoriteToggleSurvivesForceStopAndCanBeRemoved() {
        field("tab.Favorites").click()
        visible(By.text("No Favorites Yet"))
        screenshot("empty-favorites-light")
        saveBook("Favorite Fixture", "Author", "Another.wav")
        tapDescription("Add favorite")
        field("tab.Favorites").click()
        visible(By.text("Favorite Fixture"))
        device.executeShellCommand("am force-stop $app")
        launch()
        visible(By.text("Favorite Fixture"))
        tapDescription("Remove favorite")
        visible(By.text("No Favorites Yet"))
        relaunch()
        field("tab.Favorites").click()
        visible(By.text("No Favorites Yet"))
    }

    @Test fun sortOrderAndMenuSelectionPersistIndependently() {
        saveBook("Alpha Fixture", "Zulu Author", "Another.wav")
        saveBook("Zulu Fixture", "Alpha Author", "Chapter 10.wav")
        assertTrue(visible(By.text("Zulu Fixture")).visibleBounds.left < visible(By.text("Alpha Fixture")).visibleBounds.left)
        field("tab.Library").click()
        tapText("Title")
        assertTrue(visible(By.text("Alpha Fixture")).visibleBounds.left < visible(By.text("Zulu Fixture")).visibleBounds.left)
        relaunch()
        assertTrue(visible(By.text("Alpha Fixture")).visibleBounds.left < visible(By.text("Zulu Fixture")).visibleBounds.left)
        field("tab.Library").click()
        visible(By.text("Recently Played"))
        tapText("Author")
        assertTrue(visible(By.text("Zulu Fixture")).visibleBounds.left < visible(By.text("Alpha Fixture")).visibleBounds.left)
        // Switching by horizontal swipe uses the same tab state as the picker.
        device.swipe(80, 500, 900, 500, 30)
        visible(By.text("No Favorites Yet"))
    }

    @Test fun settingsIntervalsAppearanceAndLaunchDestinationPersist() {
        tapDescription("Settings")
        expandSettings()
        visible(By.text("Settings"))
        field("settings.picker.On Resume").click()
        field("settings.option.resumeBacktrackSeconds.15").click()
        field("settings.picker.Save Moment Offset").click()
        scrollTo("settings.option.momentBacktrackSeconds.30")
        field("settings.option.momentBacktrackSeconds.30").click()
        field("settings.picker.Skip Backward").click()
        scrollTo("settings.option.skipBackSeconds.45")
        field("settings.option.skipBackSeconds.45").click()
        scrollTo("settings.picker.Skip Forward")
        field("settings.picker.Skip Forward").click()
        scrollTo("settings.option.skipForwardSeconds.15")
        field("settings.option.skipForwardSeconds.15").click()
        scrollTo("settings.appearance.Dark")
        field("settings.appearance.Dark").click()
        assertTheme(dark = true)
        screenshot("settings-preferences-dark")
        tapText("Done")
        device.executeShellCommand("am force-stop $app")
        launch()
        visible(By.text("No Favorites Yet"))
        assertTheme(dark = true)
        screenshot("appearance-persisted-dark")
        tapDescription("Settings")
        expandSettings()
        visible(By.text("Resume 15 seconds earlier"))
        visible(By.text("30 seconds earlier"))
        visible(By.text("45 seconds"))
        scrollTo("settings.picker.Skip Forward")
        visible(By.text("15 seconds"))
        scrollTo("settings.appearance.Light")
        field("settings.appearance.Light").click()
        assertTheme(dark = false)
        screenshot("appearance-light-overrides-system")
        scrollTo("settings.home.Shelves", downward = false)
        field("settings.home.Shelves").click()
        tapText("Done")
        device.executeShellCommand("am force-stop $app")
        launch()
        device.waitForIdle()
        assertFalse(device.hasObject(By.text("No Favorites Yet")))
        field("tab.Shelves")
        tapDescription("Settings")
        expandSettings()
        field("settings.home.Library").click()
        tapText("Done")
        device.executeShellCommand("am force-stop $app")
        launch()
        visible(By.text("No Favorites Yet"))
    }

    @Test fun legalLinksOpenTheirIosDestinationsInTheSystemBrowser() {
        tapDescription("Settings")
        expandSettings()
        scrollTo("settings.legal.Privacy Policy")
        field("settings.legal.Privacy Policy").click()
        visible(By.pkg("org.chromium.webview_shell"))
        visible(By.textContains("gist.github.com/andreibalu/aca2af2e2176cc453175f708b2481262"))
        device.pressBack()
        visible(By.text("Settings"))
        scrollTo("settings.legal.Terms of Use")
        field("settings.legal.Terms of Use").click()
        visible(By.pkg("org.chromium.webview_shell"))
        visible(By.textContains("apple.com/legal/internet-services/itunes/dev/stdeula"))
        device.pressBack()
        visible(By.text("Settings"))
        tapText("Done")
        visible(By.text("My Library"))
    }

    private fun expandSettings() {
        val header = visible(By.text("Settings")).visibleBounds
        device.swipe(header.centerX(), header.centerY(), header.centerX(), 150, 30)
        settleLayout()
        assertTrue("Settings should expand above the screen midpoint", visible(By.text("Settings")).visibleBounds.top < device.displayHeight / 3)
    }

    private fun assertTheme(dark: Boolean) {
        device.waitForIdle()
        val capture = File(captureDirectory(), "theme-check.png")
        assertTrue(device.takeScreenshot(capture))
        val bitmap = android.graphics.BitmapFactory.decodeFile(capture.absolutePath)
        val pixel = bitmap.getPixel(8, bitmap.height / 2)
        val brightness = (android.graphics.Color.red(pixel) + android.graphics.Color.green(pixel) + android.graphics.Color.blue(pixel)) / 3
        bitmap.recycle()
        assertTrue("Rendered background brightness $brightness, expected dark=$dark", if (dark) brightness < 70 else brightness > 160)
    }

    private fun scrollTo(id: String, downward: Boolean = true) {
        repeat(8) {
            val bounds = visible(By.res("settings.scroll")).visibleBounds
            val target = device.findObject(By.res(id))?.visibleBounds
            if (target != null && target.height() >= 60 && target.top >= bounds.top + 8 && target.bottom < bounds.bottom - 8) return
            val top = bounds.top + bounds.height() / 5
            val bottom = bounds.bottom - bounds.height() / 5
            device.swipe(bounds.centerX(), if (downward) bottom else top, bounds.centerX(), if (downward) top else bottom, 30)
        }
        field(id)
    }

    private fun saveBook(title: String, author: String, vararg files: String) {
        pick(*files)
        field("import.title").setText(title)
        field("import.author").setText(author)
        tapText("Save")
        visible(By.text("My Library"))
        visible(By.text(title))
    }

    private fun relaunch() { device.executeShellCommand("am force-stop $app"); launch(); field("tab.Library").click() }

    private fun pick(vararg names: String) {
        openPicker(*names)
        visible(By.res("import.title"))
    }

    private fun openPicker(vararg names: String) {
        tapDescription("Import Audiobook")
        tapDescription("Show roots")
        val root = device.findObject(UiSelector().resourceId("android:id/title").text("Android SDK built for arm64"))
        assertTrue(root.waitForExists(15_000))
        root.click()
        val breadcrumb = device.findObject(UiSelector().resourceId("com.android.documentsui:id/breadcrumb_text").text("Android SDK built for arm64"))
        assertTrue(breadcrumb.waitForExists(15_000))
        breadcrumb.click()
        tapText("Download")
        tapText("Unpaged_E2E")
        if (device.hasObject(By.desc("List view"))) tapDescription("List view")
        if (names.size == 1) tapText(names.single())
        else {
            text(names.first()).longClick()
            names.drop(1).forEach { tapText(it) }
            tapText("Select")
        }
    }

    // UiObject re-resolves its selector for each action. System-picker drawer nodes can
    // report stale UiObject2 references even after idle; never cache those references.
    private fun text(value: String) = device.findObject(UiSelector().text(value)).also {
        assertTrue("Missing text: $value", it.waitForExists(15_000))
    }
    private fun field(id: String) = device.findObject(UiSelector().resourceId(id)).also {
        assertTrue("Missing field: $id", it.waitForExists(15_000))
    }
    private fun tapText(value: String) { device.waitForIdle(); text(value).click() }
    private fun tapDescription(value: String) {
        device.waitForIdle()
        val target = device.findObject(UiSelector().description(value).enabled(true))
        assertTrue("Missing description: $value", target.waitForExists(15_000))
        target.click()
    }

    private fun launch() {
        device.executeShellCommand("am start -W -n $app/dev.unpaged.android.MainActivity")
        visible(By.pkg(app).depth(0))
    }

    private fun visible(selector: BySelector): UiObject2 {
        device.waitForIdle()
        return device.wait(Until.findObject(selector), 15_000) ?: throw AssertionError("Missing UI: $selector")
    }

    private fun captureDirectory() = File(instrumentation.context.getExternalFilesDir(null), "screenshots").apply { mkdirs() }

    // Gradle uninstalls the test APK after connected tests, removing its external files.
    // Copy evidence as the instrumentation shell into this dedicated capture directory.
    private fun persistCapture(file: File) {
        val destination = "/sdcard/Download/Unpaged_E2E_Captures"
        device.executeShellCommand("mkdir -p $destination")
        device.executeShellCommand("cp ${file.absolutePath} $destination/${file.name}")
        assertEquals("Capture copy failed", "", device.executeShellCommand("test -s $destination/${file.name} || echo missing").trim())
    }

    private fun settleLayout() {
        device.waitForIdle()
        // Compose geometry can settle after accessibility idle, even with animator scale 0.
        android.os.SystemClock.sleep(400)
        device.waitForIdle()
    }

    private fun screenshot(name: String) {
        settleLayout()
        val file = File(captureDirectory(), "$name.png")
        assertTrue(device.takeScreenshot(file))
        persistCapture(file)
    }
}
