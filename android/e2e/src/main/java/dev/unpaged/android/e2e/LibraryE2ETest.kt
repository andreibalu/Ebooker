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
    }

    @Test fun libraryUsesIosHeaderAndEmptyState() {
        visible(By.text("My Library"))
        visible(By.text("Your Library Is Empty"))
        screenshot("empty-light")
        device.executeShellCommand("cmd uimode night yes")
        visible(By.text("My Library"))
        screenshot("empty-dark")
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
        tapText("Removal Fixture")
        tapText("Remove from library")
        tapText("Cancel")
        visible(By.text("Fixture Author"))
        tapText("Remove from library")
        tapText("Remove")
        visible(By.text("Your Library Is Empty"))
        relaunch()
        visible(By.text("Your Library Is Empty"))
        // Import the same original through the provider again; app deletion did not remove it.
        saveBook("Original Still Available", "Fixture Author", "Another.wav")
        visible(By.text("Original Still Available"))
    }

    @Test fun matchingIosFixturesCaptureLibraryDetailAndReviewInBothThemes() {
        saveBook("E2E The Listening Book", "Fixture Author", "Chapter 2.wav", "Chapter 1.wav")
        saveBook("E2E Another Book", "Another Fixture Author", "Another.wav")
        screenshot("library-light")
        device.executeShellCommand("cmd uimode night yes")
        visible(By.text("E2E Another Book"))
        screenshot("library-dark")
        tapText("E2E The Listening Book")
        visible(By.text("Fixture Author"))
        screenshot("detail-dark")
        device.executeShellCommand("cmd uimode night no")
        visible(By.text("Fixture Author"))
        screenshot("detail-light")
        device.pressBack()
        visible(By.text("My Library"))
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

    private fun saveBook(title: String, author: String, vararg files: String) {
        pick(*files)
        field("import.title").setText(title)
        field("import.author").setText(author)
        tapText("Save")
        visible(By.text("My Library"))
        visible(By.text(title))
    }

    private fun relaunch() { device.executeShellCommand("am force-stop $app"); launch() }

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

    private fun screenshot(name: String) {
        device.waitForIdle()
        val file = File(captureDirectory(), "$name.png")
        assertTrue(device.takeScreenshot(file))
        persistCapture(file)
    }
}
