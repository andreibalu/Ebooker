package dev.unpaged.android.e2e

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.Configurator
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.UiSelector
import androidx.test.uiautomator.UiScrollable
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
        // Continuous playback events can keep the default 10s idle wait busy long
        // enough to miss 2s feedback. Geometry-sensitive actions settle explicitly.
        Configurator.getInstance().waitForIdleTimeout = 100
        assertEquals("Use tools/run-e2e.sh on its dedicated emulator", "true",
            InstrumentationRegistry.getArguments().getString("e2eApproved"))
        assertEquals("1", device.executeShellCommand("getprop ro.kernel.qemu").trim())
        assertTrue(device.executeShellCommand("getprop ro.boot.qemu.avd_name").trim().startsWith("Unpaged_E2E_"))
        for (setting in listOf("window_animation_scale", "transition_animation_scale", "animator_duration_scale"))
            device.executeShellCommand("settings put global $setting 0")
        device.pressHome()
        settleLayout()
        device.executeShellCommand("pm clear $app")
        settleLayout()
        device.executeShellCommand("cmd uimode night no")
        launchFixture()
        completeOnboarding()
        selectLibraryTab()
    }

    private fun completeOnboarding() {
        if (device.wait(Until.hasObject(By.res("onboarding")), 2000)) {
            field("onboarding.choice.My books").click()
            field("onboarding.page.6").click()
            field("onboarding.finish").click()
            field("tab.Library")
        }
    }

    private fun <T> onMediaMain(operation: () -> T): T {
        val value = java.util.concurrent.atomic.AtomicReference<T>()
        instrumentation.runOnMainSync { value.set(operation()) }
        return value.get()
    }
    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private fun browser(listener: androidx.media3.session.MediaBrowser.Listener? = null): androidx.media3.session.MediaBrowser {
        val context = instrumentation.context
        val future = onMediaMain {
            androidx.media3.session.MediaBrowser.Builder(context, androidx.media3.session.SessionToken(context,
                android.content.ComponentName(app, "dev.unpaged.android.playback.PlaybackService")))
                .apply { if (listener != null) setListener(listener) }.buildAsync()
        }
        return future.get(15, java.util.concurrent.TimeUnit.SECONDS)
    }
    private fun <T> mediaResult(future: com.google.common.util.concurrent.ListenableFuture<T>): T =
        future.get(15, java.util.concurrent.TimeUnit.SECONDS)

    @Test @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    fun carBrowserTreePlaybackCommandsOfflineErrorAndMomentPersistence() {
        saveBook("E2E The Listening Book", "Fixture Author", "E2E Chapter 1.wav", "E2E Chapter 2.wav")
        tapDescription("Add favorite")
        val error = java.util.concurrent.atomic.AtomicReference<androidx.media3.session.SessionError>()
        val browser = browser(object : androidx.media3.session.MediaBrowser.Listener {
            override fun onError(controller: androidx.media3.session.MediaController, sessionError: androidx.media3.session.SessionError) { error.set(sessionError) }
        })
        try {
            val root = mediaResult(onMediaMain { browser.getLibraryRoot(null) })
            assertEquals(0, root.resultCode); assertEquals("root", root.value!!.mediaId)
            val tabs = mediaResult(onMediaMain { browser.getChildren("root", 0, 10, null) }).value!!
            assertEquals(listOf("Favorites", "Library", "Shelves"), tabs.map { it.mediaId })
            val rows = mediaResult(onMediaMain { browser.getChildren("Library", 0, 10, null) }).value!!
            assertEquals("E2E The Listening Book", rows.single().mediaMetadata.title.toString())
            val cover = instrumentation.context.contentResolver.openInputStream(rows.single().mediaMetadata.artworkUri!!)!!.use { it.readBytes() }
            assertTrue(cover.take(4).toByteArray().contentEquals(byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47)))
            assertEquals(rows.single().mediaId, mediaResult(onMediaMain { browser.getChildren("Favorites", 0, 10, null) }).value!!.single().mediaId)
            val classics = mediaResult(onMediaMain { browser.getChildren("Shelves", 0, 30, null) }).value!!
            assertTrue(classics.isNotEmpty())
            onMediaMain { browser.setMediaItem(rows.single()); browser.prepare(); browser.play() }
            visible(By.res("miniPlayer.title").text("E2E The Listening Book"))
            field("miniPlayer").click(); field("player.title"); waitForElapsed { it >= 2 }
            onMediaMain { browser.pause(); browser.seekTo(35000) }
            waitForElapsed { it == 35 }
            fun command(action: String): androidx.media3.session.SessionResult = mediaResult(onMediaMain {
                browser.sendCustomCommand(androidx.media3.session.SessionCommand("dev.unpaged.$action", android.os.Bundle.EMPTY), android.os.Bundle.EMPTY)
            })
            assertEquals(0, command("SAVE_MOMENT").resultCode)
            assertEquals(0, command("MARK_PROGRESS").resultCode)
            assertEquals(0, command("CYCLE_SPEED").resultCode)
            visible(By.text("1.25x"))
            assertEquals(listOf("Favorites", "Library", "Shelves", "chapters"),
                mediaResult(onMediaMain { browser.getChildren("root", 0, 10, null) }).value!!.map { it.mediaId })
            val chapters = mediaResult(onMediaMain { browser.getChildren("chapters", 0, 30, null) }).value!!
            assertEquals(2, chapters.size)
            screenshot("auto-player-light")
            device.executeShellCommand("cmd uimode night yes"); field("player.title"); screenshot("auto-player-dark")
            device.executeShellCommand("cmd uimode night no"); field("player.close").click()
            tapText("E2E The Listening Book"); field("book.moments").click()
            visible(By.text("CarPlay 1")); visible(By.text("00:35"))
            screenshot("auto-moments-light")
            device.executeShellCommand("cmd uimode night yes"); visible(By.text("CarPlay 1")); screenshot("auto-moments-dark")
            device.executeShellCommand("cmd uimode night no")
            onMediaMain { browser.setMediaItem(chapters[1]); browser.prepare(); browser.play() }
            field("miniPlayer").click(); visible(By.res("player.title").text("E2E Chapter 2"))
            waitForElapsed { it in 0..5 }; field("player.close").click()
            onMediaMain { browser.setMediaItem(classics.first()); browser.prepare(); browser.play() }
            val deadline = android.os.SystemClock.elapsedRealtime() + 15000
            while (error.get() == null && android.os.SystemClock.elapsedRealtime() < deadline) android.os.SystemClock.sleep(100)
            assertEquals("No internet connection", error.get()?.message)
        } finally { onMediaMain { browser.release() } }
        relaunch(); tapText("E2E The Listening Book"); field("book.moments").click()
        visible(By.text("CarPlay 1")); visible(By.text("00:35")); visible(By.text("1 moment"))
    }

    @Test fun launcherShortcutPlaysLatestAndIsConsumedAcrossRotationAndRelaunch() {
        saveBook("E2E The Listening Book", "Fixture Author", "E2E Chapter 1.wav", "E2E Chapter 2.wav")
        tapText("E2E The Listening Book"); field("book.play").click(); dismissNotificationPrompt()
        waitForElapsed { it >= 2 }; field("player.playPause").click(); field("player.close").click(); device.pressBack()
        saveBook("Unplayed newer import", "Other Author", "Another.wav")
        device.executeShellCommand("am force-stop $app")
        device.executeShellCommand("am start -W -n $app/dev.unpaged.android.MainActivity -a dev.unpaged.android.PLAY_LATEST_BOOK")
        visible(By.res("miniPlayer.title").text("E2E The Listening Book")); visible(By.desc("Pause playback"))
        field("miniPlayer.playPause").click(); visible(By.desc("Play playback"))
        device.setOrientationLeft(); visible(By.desc("Play playback")); device.setOrientationNatural()
        selectLibraryTab()
        screenshot("auto-shortcut-light")
        device.executeShellCommand("cmd uimode night yes"); visible(By.desc("Play playback")); screenshot("auto-shortcut-dark")
        relaunch(); assertFalse(device.hasObject(By.res("miniPlayer")))
    }

    @Test @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    fun voiceIntentAndBrowserSearchChooseLibraryFirstAndEmptyQueryResumesLatest() {
        saveBook("Jane Eyre", "Charlotte Bronte", "Another.wav")
        saveBook("E2E The Listening Book", "Fixture Author", "E2E Chapter 1.wav", "E2E Chapter 2.wav")
        device.executeShellCommand("am start -W -n $app/dev.unpaged.android.MainActivity -a android.media.action.MEDIA_PLAY_FROM_SEARCH --es query Eyre") // No shell here: a quoted space would split the argument.
        visible(By.res("miniPlayer.title").text("Jane Eyre")); visible(By.desc("Pause playback"))
        field("miniPlayer.playPause").click(); visible(By.desc("Play playback"))
        val browser = browser()
        try {
            assertEquals(0, mediaResult(onMediaMain { browser.search("Eyre", null) }).resultCode)
            val results = mediaResult(onMediaMain { browser.getSearchResult("Eyre", 0, 30, null) }).value!!
            assertEquals(1, results.size); assertTrue(results.single().mediaId.startsWith("book:"))
            val request = androidx.media3.common.MediaItem.Builder().setRequestMetadata(
                androidx.media3.common.MediaItem.RequestMetadata.Builder().setSearchQuery("Listening").build()).build()
            onMediaMain { browser.setMediaItem(request); browser.prepare(); browser.play() }
            visible(By.res("miniPlayer.title").text("E2E The Listening Book")); visible(By.desc("Pause playback"))
            field("miniPlayer.playPause").click(); visible(By.desc("Play playback"))
        } finally { onMediaMain { browser.release() } }
        device.executeShellCommand("am force-stop $app")
        device.executeShellCommand("am start -W -n $app/dev.unpaged.android.MainActivity -a android.media.action.MEDIA_PLAY_FROM_SEARCH")
        visible(By.res("miniPlayer.title").text("E2E The Listening Book")); visible(By.desc("Pause playback"))
        selectLibraryTab()
        screenshot("auto-voice-light")
        device.executeShellCommand("cmd uimode night yes"); visible(By.res("miniPlayer.title")); screenshot("auto-voice-dark")
    }

    @Test fun onboardingFirstLaunchPersistsAndResetShowsWelcomeAgain() {
        device.executeShellCommand("am force-stop $app")
        device.executeShellCommand("pm clear $app")
        launch()
        field("onboarding.choice.My books")
        screenshot("onboarding-light")
        device.executeShellCommand("cmd uimode night yes")
        field("onboarding.choice.My books")
        screenshot("onboarding-dark")
        device.executeShellCommand("cmd uimode night no")
        field("onboarding.choice.My books").click()
        field("onboarding.page.1").click()
        field("onboarding.notifications")
        captureOnboardingPage("permissions")
        field("onboarding.page.2").click()
        field("onboarding.skipForwardSeconds.45").click()
        captureOnboardingPage("playback")
        field("onboarding.page.3").click()
        visible(By.text("Imagine your year."))
        captureOnboardingPage("year")
        field("onboarding.page.4").click()
        visible(By.text("Timestamps are saved on your phone. Automatic naming and AI recaps are not available."))
        captureOnboardingPage("moments")
        field("onboarding.page.5").click()
        visible(By.text("Cloud sync is not available. Uninstalling Unpaged removes its local library and activity."))
        captureOnboardingPage("storage")
        field("onboarding.page.6").click()
        visible(By.text("Skip forward: 45s"))
        captureOnboardingPage("done")
        field("onboarding.finish").click()
        visible(By.text("Your Library Is Empty"))
        device.executeShellCommand("am force-stop $app")
        launch()
        assertFalse(device.hasObject(By.res("onboarding")))
        tapDescription("Settings")
        scrollTo("settings.resetOnboarding")
        field("settings.resetOnboarding").click()
        visible(By.text("Reset Onboarding?"))
        field("settings.confirmReset").click()
        field("onboarding.choice.My books")
        device.executeShellCommand("am force-stop $app")
        launch()
        field("onboarding.choice.My books")
    }

    @Test fun seededActivityOpensStatsAndPersistsAcrossRelaunch() {
        saveBook("E2E The Listening Book", "Fixture Author", "Chapter 1.wav", "Chapter 2.wav")
        tapDescription("Add favorite")
        saveBook("E2E Another Book", "Another Fixture Author", "Another.wav")
        device.executeShellCommand("am force-stop $app")
        device.executeShellCommand("am start -W -n $app/dev.unpaged.android.activity.ReadingFixtureActivity --ez e2e-reading-fixture true --ez reference true")
        selectTab("Favorites")
        visible(By.text("ACTIVITY")); visible(By.text("42m"))
        screenshot("activity-light")
        device.executeShellCommand("cmd uimode night yes")
        field("activity.card")
        screenshot("activity-dark")
        field("activity.card").click()
        field("reading.stats")
        visible(By.text("Page by page."))
        screenshot("stats-dark")
        device.executeShellCommand("cmd uimode night no")
        field("reading.stats")
        screenshot("stats-light")
        for (section in listOf("your_best_day", "you_read_most_in_the", "the_book_you_stayed_with", "on_a_roll", "the_shape_of_it", "public_domain,_private_joy")) {
            // UiScrollable stops early on the animated LazyColumn; step with the driver's own swipes.
            scrollTo("stats.eyebrow.$section", scrollId = "reading.stats.scroll")
            screenshot("stats-$section-light")
            device.executeShellCommand("cmd uimode night yes")
            field("reading.stats")
            screenshot("stats-$section-dark")
            device.executeShellCommand("cmd uimode night no")
        }
        screenshot("stats-sections-light")
        scrollTo("reading.stats.backToLibrary", scrollId = "reading.stats.scroll")
        field("reading.stats.backToLibrary").click()
        device.executeShellCommand("am force-stop $app")
        launch()
        selectTab("Favorites")
        visible(By.text("42m"))
        field("activity.card").click()
        field("reading.stats")
    }

    @Test fun libraryUsesIosHeaderAndEmptyState() {
        visible(By.text("My Library"))
        visible(By.text("Your Library Is Empty"))
        screenshot("empty-light")
        device.executeShellCommand("cmd uimode night yes")
        visible(By.text("My Library"))
        screenshot("empty-dark")
        tapText("Browse Shelves")
        field("shelves.screen")
        device.executeShellCommand("cmd uimode night no")
        field("shelves.screen")
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
        selectLibraryTab()
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
        visible(By.text("Something Went Wrong"))
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
        visible(By.text("Tap the bookmark in the player to save a moment"))
        screenshot("detail-moments-empty-light")
        field("book.moments").click()
        visible(By.text("Tap the bookmark in the player to save a moment"))
        settleLayout()
        expandTracks("Chapter 1")
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
        device.waitForIdle(500)
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

    @Test fun playbackAdvancesSkipsChaptersChangesSpeedAndPersistsAfterRealForceStop() {
        saveBook("E2E The Listening Book", "Fixture Author", "E2E Chapter 2.wav", "E2E Chapter 1.wav")
        tapText("E2E The Listening Book")
        field("book.play").click()
        dismissNotificationPrompt()
        visible(By.res("player.title").text("E2E Chapter 1"))
        waitForElapsed { it >= 2 }
        field("player.close").click()
        visible(By.res("miniPlayer.title").text("E2E The Listening Book"))
        field("miniPlayer.playPause").click()
        visible(By.desc("Play playback"))
        val savedPosition = field("book.position").text
        assertFalse(savedPosition == "at 00:00")
        relaunch()
        tapText("E2E The Listening Book")
        visible(By.text("Continue"))
        assertEquals(savedPosition, field("book.position").text)
        // On Resume is once per launch and clamps the short persisted position to 0.
        field("book.play").click()
        visible(By.res("player.title").text("E2E Chapter 1"))
        waitForElapsed { it in 0..5 }
        field("player.playPause").click()
        visible(By.desc("Play playback"))
        val beforeSkip = elapsedSeconds()
        field("player.skipForward").click()
        waitForElapsed { it == beforeSkip + 30 }
        field("player.speed").click()
        field("player.speed.1.5").click()
        visible(By.text("1.5x"))
        field("player.chapters").click()
        visible(By.text("Chapters"))
        field("chapters.row.1").click()
        visible(By.res("player.title").text("E2E Chapter 2"))
        waitForElapsed { it in 0..5 }
        visible(By.desc("Pause playback"))
        assertFalse(field("player.next").isEnabled)
        field("player.close").click()
        field("miniPlayer.playPause").click()
        relaunch()
        tapText("E2E The Listening Book")
        visible(By.text("Continue"))
        field("book.play").click()
        visible(By.res("player.title").text("E2E Chapter 2"))
        visible(By.text("1.5x"))
    }

    @Test fun playerProgressMomentSleepAndLightDarkVisualFixtures() {
        saveBook("E2E The Listening Book", "Fixture Author", "E2E Chapter 2.wav", "E2E Chapter 1.wav")
        tapDescription("Add favorite")
        saveBook("E2E Another Book", "Another Fixture Author", "Another.wav")
        tapText("E2E The Listening Book")
        field("book.play").click()
        dismissNotificationPrompt()
        visible(By.res("player.title").text("E2E Chapter 1"))
        waitForElapsed { it >= 2 }
        field("player.playPause").click()
        visible(By.desc("Play playback"))
        field("player.saveMoment").click()
        field("moment.done").click()
        visible(By.text("Saved!"))
        waitForPillLabel("player.saveMoment", "Save Moment")
        settleLayout()
        visible(By.res("player.saveMoment")).click()
        field("moment.done").click()
        visible(By.text("Saved!"))
        field("player.markProgress").click()
        visible(By.text("This will update your progress marker to the current playback position."))
        field("player.confirmProgress").click()
        visible(By.text("Progress Marked!"))
        field("player.sleep").click()
        tapText("5 minutes")
        assertTrue(device.wait(Until.gone(By.text("Sleep Timer")), 15000))
        field("player.sleep").click()
        tapText("Off")
        visible(By.text("Sleep Timer"))
        waitForPillLabel("player.saveMoment", "Save Moment")
        waitForPillLabel("player.markProgress", "Mark Progress Here")
        // Resume for the reference's playing transport state.
        field("player.playPause").click()
        visible(By.desc("Pause playback"))
        screenshot("player-light")
        field("player.chapters").click()
        screenshot("chapters-light")
        field("chapters.done").click()
        device.executeShellCommand("cmd uimode night yes")
        visible(By.res("player.title"))
        screenshot("player-dark")
        field("player.chapters").click()
        screenshot("chapters-dark")
        field("chapters.done").click()
        field("player.close").click()
        screenshot("detail-miniplayer-dark")
        device.executeShellCommand("cmd uimode night no")
        visible(By.res("miniPlayer.title"))
        screenshot("detail-miniplayer-light")
        visible(By.text("2 moments"))
        device.pressBack()
        visible(By.text("Playing"))
        screenshot("library-miniplayer-light")
        device.executeShellCommand("cmd uimode night yes")
        visible(By.text("Playing"))
        screenshot("library-miniplayer-dark")
        field("miniPlayer.playPause").click()
        assertTrue(device.wait(Until.gone(By.text("Playing")), 15000))
        // Mini player also persists over root tab navigation.
        field("tab.Favorites").click()
        visible(By.res("miniPlayer.title"))
        field("tab.Shelves").click()
        visible(By.res("miniPlayer.title"))
        field("miniPlayer").click()
        visible(By.res("player.title"))
        field("player.close").click()
        relaunch()
        tapText("E2E The Listening Book")
        visible(By.text("2 moments"))
    }

    @Test fun singleTrackPlayerUsesBookTitleAndDisablesChapterNavigation() {
        saveBook("E2E Another Book", "Another Fixture Author", "Another.wav")
        tapText("E2E Another Book")
        field("book.play").click()
        dismissNotificationPrompt()
        visible(By.res("player.title").text("E2E Another Book"))
        waitForElapsed { it >= 2 }
        assertFalse(field("player.previous").isEnabled)
        assertFalse(field("player.next").isEnabled)
        assertFalse(device.hasObject(By.res("player.chapters")))
        field("player.close").click()
        visible(By.res("miniPlayer.title").text("E2E Another Book"))
        assertFalse(device.hasObject(By.text("Another")))
    }

    @Test fun manualMomentMetadataEditFilterPlayAndDeletePersistAcrossRelaunch() {
        saveBook("E2E The Listening Book", "Fixture Author", "E2E Chapter 2.wav", "E2E Chapter 1.wav")
        tapDescription("Add favorite")
        tapText("E2E The Listening Book")
        field("book.play").click()
        dismissNotificationPrompt()
        waitForElapsed { it >= 2 }
        field("player.playPause").click()
        val momentTime = field("player.elapsed").text
        field("player.saveMoment").click()
        field("moment.name").setText("A turning point")
        field("moment.note").setText("A memorable passage")
        dismissKeyboard() // setText may update the field without opening an IME
        scrollTo("moment.quote", scrollId = "moment.scroll")
        field("moment.quote").setText("The story begins")
        dismissKeyboard()
        scrollTo("moment.addCategory", scrollId = "moment.scroll")
        field("moment.addCategory").click(); tapText("Action")
        scrollTo("moment.addMood", scrollId = "moment.scroll")
        field("moment.addMood").click(); tapText("Dramatic")
        scrollTo("moment.character", scrollId = "moment.scroll")
        field("moment.character").setText("Alice")
        field("moment.addCharacter").click()
        dismissKeyboard()
        screenshot("save-moment-light")
        field("moment.done").click()
        visible(By.text("Saved!"))
        field("player.close").click()
        relaunch()
        tapText("E2E The Listening Book")
        field("book.moments").click()
        visible(By.text("A turning point")); visible(By.text("A memorable passage")) // Rows omit categories, as on iOS.
        screenshot("moments-light")
        field("moment.filter").click(); screenshot("moment-filters-light"); tapText("Dramatic"); tapText("Done")
        visible(By.text("1 moment · filtered"))
        field("moment.filter").click()
        scrollTo("moment.clearFilters", scrollId = "moment.filterScroll")
        field("moment.clearFilters").click(); tapText("Done")
        tapDescription("Pin moment")
        visible(By.desc("Unpin moment"))
        tapDescription("Edit moment")
        scrollTo("moment.quote", scrollId = "moment.scroll")
        assertEquals("The story begins", field("moment.quote").text)
        scrollTo("moment.addCategory", scrollId = "moment.scroll"); visible(By.text("Action"))
        scrollTo("moment.name", downward = false, scrollId = "moment.scroll")
        field("moment.name").setText("Edited turning point")
        field("moment.done").click()
        relaunch(); tapText("E2E The Listening Book"); field("book.moments").click()
        visible(By.text("Edited turning point")); visible(By.desc("Unpin moment"))
        tapDescription("Play from this moment")
        visible(By.res("player.title"))
        val savedSeconds = momentTime.split(":").let { it[0].toInt() * 60 + it[1].toInt() }
        waitForElapsed { it in savedSeconds..(savedSeconds + 2) }
        field("player.playPause").click(); field("player.close").click()
        device.executeShellCommand("cmd uimode night yes")
        visible(By.text("Edited turning point")); screenshot("moments-dark")
        field("moment.filter").click(); screenshot("moment-filters-dark"); tapText("Done")
        tapDescription("Edit moment"); screenshot("edit-moment-dark"); tapText("Cancel")
        val rowBounds = visible(By.res(java.util.regex.Pattern.compile("moment\\.row\\..*"))).visibleBounds
        device.swipe(rowBounds.right - 20, rowBounds.centerY(), rowBounds.right - rowBounds.width() / 3, rowBounds.centerY(), 25)
        tapText("Delete")
        visible(By.text("Tap the bookmark in the player to save a moment"))
        relaunch(); tapText("E2E The Listening Book"); field("book.moments").click()
        visible(By.text("Tap the bookmark in the player to save a moment"))
    }

    @Test fun momentOffsetClampsAndCancelledOrBlankEditsDoNotSave() {
        saveBook("E2E The Listening Book", "Fixture Author", "E2E Chapter 2.wav", "E2E Chapter 1.wav")
        tapDescription("Settings"); expandSettings()
        field("settings.picker.Save Moment Offset").click()
        scrollTo("settings.option.momentBacktrackSeconds.30")
        field("settings.option.momentBacktrackSeconds.30").click()
        tapText("Done")
        assertTrue(device.wait(Until.gone(By.res("settings.scroll")), 5000))
        tapText("E2E The Listening Book"); field("book.play").click(); dismissNotificationPrompt()
        waitForElapsed { it >= 2 }; field("player.playPause").click()
        field("player.saveMoment").click()
        field("moment.name").setText("   ")
        // setText returns before recomposition; wait for the blank-name state to disable Done.
        assertTrue(visible(By.res("moment.done")).wait(Until.enabled(false), 5_000))
        tapText("Cancel")
        field("player.saveMoment").click(); field("moment.name").setText("Offset moment"); field("moment.done").click()
        visible(By.text("Saved!")); field("player.close").click()
        relaunch(); tapText("E2E The Listening Book"); field("book.moments").click()
        visible(By.text("1 moment")); visible(By.text("Offset moment")); visible(By.text("00:00"))
    }

    @Test fun equalizerPresetBoostAndPerBookIsolationPersistAfterRelaunch() {
        saveBook("E2E The Listening Book", "Fixture Author", "E2E Chapter 2.wav", "E2E Chapter 1.wav")
        tapDescription("Add favorite")
        saveBook("E2E Another Book", "Another Fixture Author", "Another.wav")
        tapText("E2E The Listening Book"); field("book.play").click(); dismissNotificationPrompt()
        waitForElapsed { it >= 2 }; field("player.playPause").click()
        field("player.equalizer").click()
        screenshot("eq-light")
        field("equalizer.enabled").click()
        val boostBounds = visible(By.res("equalizer.preamp")).visibleBounds
        device.click(boostBounds.centerX(), boostBounds.centerY())
        visible(By.text("+6 dB"))
        scrollTo("equalizer.preset.voiceBoost", scrollId = "equalizer.scroll", edgeSwipe = true)
        field("equalizer.preset.voiceBoost").click()
        assertTrue(visible(By.res("equalizer.preset.voiceBoost")).wait(Until.checked(true), 5_000))
        field("equalizer.done").click(); field("player.close").click()
        relaunch(); tapText("E2E The Listening Book"); field("book.play").click()
        visible(By.res("player.title")); field("player.equalizer").click()
        assertTrue(visible(By.res("equalizer.enabled")).wait(Until.checked(true), 5_000))
        visible(By.text("+6 dB"))
        scrollTo("equalizer.preset.voiceBoost", scrollId = "equalizer.scroll", edgeSwipe = true)
        assertTrue(visible(By.res("equalizer.preset.voiceBoost")).wait(Until.checked(true), 5_000))
        device.executeShellCommand("cmd uimode night yes")
        visible(By.text("Equalizer")); screenshot("eq-dark")
        scrollTo("equalizer.reset", scrollId = "equalizer.scroll", edgeSwipe = true); field("equalizer.reset").click()
        scrollTo("equalizer.preset.flat", downward = false, scrollId = "equalizer.scroll", edgeSwipe = true)
        assertTrue(visible(By.res("equalizer.preset.flat")).wait(Until.checked(true), 5_000))
        field("equalizer.done").click(); field("player.close").click(); device.pressBack()
        tapText("E2E Another Book"); field("book.play").click()
        visible(By.res("player.title")); field("player.equalizer").click()
        assertTrue(visible(By.res("equalizer.enabled")).wait(Until.checked(false), 5_000))
        scrollTo("equalizer.preset.flat", scrollId = "equalizer.scroll", edgeSwipe = true)
        assertTrue(visible(By.res("equalizer.preset.flat")).wait(Until.checked(true), 5_000))
    }

    private fun dismissNotificationPrompt() {
        val deny = device.wait(Until.findObject(By.res("com.android.permissioncontroller:id/permission_deny_button")), 2000)
        deny?.click()
        visible(By.res("player.title"))
    }

    private fun elapsedSeconds(): Int {
        val parts = field("player.elapsed").text.split(":").map { it.toInt() }
        return parts.fold(0) { value, part -> value * 60 + part }
    }

    private fun waitForElapsed(predicate: (Int) -> Boolean) {
        val deadline = android.os.SystemClock.elapsedRealtime() + 15000
        while (android.os.SystemClock.elapsedRealtime() < deadline) {
            if (predicate(elapsedSeconds())) return
            android.os.SystemClock.sleep(250)
        }
        fail("Playback position did not reach the expected visible time")
    }

    private fun expandSettings() {
        val header = visible(By.text("Settings")).visibleBounds
        device.swipe(header.centerX(), header.centerY(), header.centerX(), 150, 30)
        settleLayout()
        assertTrue("Settings should expand above the screen midpoint", visible(By.text("Settings")).visibleBounds.top < device.displayHeight / 3)
    }

    private fun assertTheme(dark: Boolean) {
        device.waitForIdle(500)
        val capture = File(captureDirectory(), "theme-check.png")
        assertTrue(device.takeScreenshot(capture))
        val bitmap = android.graphics.BitmapFactory.decodeFile(capture.absolutePath)
        val pixel = bitmap.getPixel(8, bitmap.height / 2)
        val brightness = (android.graphics.Color.red(pixel) + android.graphics.Color.green(pixel) + android.graphics.Color.blue(pixel)) / 3
        bitmap.recycle()
        assertTrue("Rendered background brightness $brightness, expected dark=$dark", if (dark) brightness < 70 else brightness > 160)
    }

    // edgeSwipe keeps the gesture off content that consumes vertical drags (EQ band sliders).
    private fun scrollTo(id: String, downward: Boolean = true, scrollId: String = "settings.scroll", edgeSwipe: Boolean = false) {
        repeat(8) {
            val bounds = visible(By.res(scrollId)).visibleBounds
            val target = device.findObject(By.res(id))?.visibleBounds
            if (target != null && target.height() >= 60 && target.top >= bounds.top + 8 && target.bottom < bounds.bottom - 8) return
            val top = bounds.top + bounds.height() / 5
            val bottom = bounds.bottom - bounds.height() / 5
            val x = if (edgeSwipe) bounds.left + 30 else bounds.centerX()
            device.swipe(x, if (downward) bottom else top, x, if (downward) top else bottom, 30)
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

    private fun relaunch() { device.executeShellCommand("am force-stop $app"); launch(); selectLibraryTab() }

    private fun selectLibraryTab() {
        selectTab("Library")
        visible(By.text("My Library"))
    }

    private fun captureOnboardingPage(page: String) {
        screenshot("onboarding-$page-light")
        device.executeShellCommand("cmd uimode night yes")
        field("onboarding")
        screenshot("onboarding-$page-dark")
        device.executeShellCommand("cmd uimode night no")
        field("onboarding")
    }

    private fun dismissKeyboard() {
        settleLayout()
        if (device.hasObject(By.pkg(java.util.regex.Pattern.compile(".*inputmethod.*")))) {
            device.pressBack()
            settleLayout()
        }
    }

    private fun selectTab(label: String) {
        val tab = visible(By.res("tab.$label"))
        if (!tab.isSelected) field("tab.$label").click()
        settleLayout()
    }

    private fun pick(vararg names: String) {
        openPicker(*names)
        visible(By.res("import.title"))
    }

    private fun openPicker(vararg names: String) {
        tapDescription("Import Audiobook")
        selectPickerFiles(*names)
    }

    private fun selectPickerFiles(vararg names: String) {
        visible(By.pkg("com.android.documentsui"))
        settleLayout()
        tapDescription("Show roots")
        settleLayout()
        visible(By.res("android:id/title").text("Android SDK built for arm64")).click()
        settleLayout()
        visible(By.res("com.android.documentsui:id/breadcrumb_text").text("Android SDK built for arm64")).click()
        settleLayout()
        tapText("Download")
        settleLayout()
        tapText("Unpaged_E2E")
        settleLayout()
        if (device.hasObject(By.desc("List view"))) tapDescription("List view")
        if (names.size == 1) pickerFile(names.single()).click()
        else {
            pickerFile(names.first()).longClick()
            names.drop(1).forEach { pickerFile(it).click() }
            tapText("Select")
        }
    }

    private fun tapMenuText(label: String) {
        settleLayout()
        repeat(10) {
            refreshAccessibility()
            val target = device.findObject(By.text(label))
            val menu = device.findObject(By.scrollable(true))?.visibleBounds
            val bounds = target?.visibleBounds
            if (bounds != null && bounds.height() >= 40 &&
                (menu == null || bounds.top > menu.top + 12 && bounds.bottom < menu.bottom - 12)) {
                target.click()
                return
            }
            checkNotNull(menu) { "Menu option not visible: $label" }
            val top = menu.top + menu.height() / 5
            val bottom = menu.bottom - menu.height() / 5
            val clearing = label.startsWith("All ")
            device.swipe(menu.centerX(), if (clearing) top else bottom,
                menu.centerX(), if (clearing) bottom else top, 30)
            settleLayout()
        }
        throw AssertionError("Menu option not found: $label")
    }

    private fun pickerFile(name: String): androidx.test.uiautomator.UiObject {
        val selector = UiSelector().resourceId("android:id/title").text(name)
        val list = UiScrollable(UiSelector().resourceId("com.android.documentsui:id/dir_list"))
        assertTrue("Picker file not found: $name", list.scrollIntoView(selector))
        // scrollIntoView can accept a clipped node beneath the system taskbar.
        repeat(8) {
            val file = device.findObject(selector)
            val bounds = file.visibleBounds
            if (bounds.height() >= 40 && bounds.bottom < device.displayHeight - 160) return file
            list.scrollForward()
        }
        throw AssertionError("Picker file not fully visible: $name")
    }

    private fun expandTracks(firstTitle: String) {
        settleLayout()
        field("book.tracks").click()
        // Refresh geometry before a single retry if Compose moved the row during the tap.
        if (!device.wait(Until.hasObject(By.text(firstTitle)), 2000)) {
            settleLayout()
            field("book.tracks").click()
        }
        visible(By.text(firstTitle))
    }

    private fun waitForPillLabel(id: String, label: String) {
        val deadline = android.os.SystemClock.uptimeMillis() + 15_000
        do {
            // Re-query the tagged action after discarding cached Compose semantics.
            // Do not reuse the transient Saved! child across recompositions.
            val pill = field(id)
            if (pill.getChild(UiSelector().text(label)).exists()) return
            android.os.SystemClock.sleep(100)
        } while (android.os.SystemClock.uptimeMillis() < deadline)
        throw AssertionError("Missing pill label: $id / $label")
    }

    // UiObject re-resolves its selector for each action. System-picker drawer nodes can
    // report stale UiObject2 references even after idle; never cache those references.
    private fun text(value: String) = device.findObject(UiSelector().text(value)).also {
        assertTrue("Missing text: $value", it.waitForExists(15_000))
    }
    private fun field(id: String): androidx.test.uiautomator.UiObject {
        val deadline = android.os.SystemClock.uptimeMillis() + 15_000
        do {
            refreshAccessibility()
            val target = device.findObject(UiSelector().resourceId(id))
            if (target.exists()) return target
            android.os.SystemClock.sleep(100)
        } while (android.os.SystemClock.uptimeMillis() < deadline)
        throw AssertionError("Missing field: $id")
    }
    private fun tapText(value: String) { device.waitForIdle(500); refreshAccessibility(); text(value).click() }
    private fun tapDescription(value: String) {
        device.waitForIdle(500)
        refreshAccessibility()
        val target = device.findObject(UiSelector().description(value).enabled(true))
        assertTrue("Missing description: $value", target.waitForExists(15_000))
        target.click()
    }

    private fun launchFixture() {
        val command = "am start -W -n $app/dev.unpaged.android.shelves.ShelvesFixtureActivity --ez e2e-shelves-fixture true"
        val result = device.executeShellCommand(command)
        if (result.contains("Status: timeout")) device.executeShellCommand(command)
        visible(By.pkg(app).depth(0))
    }

    @Test fun embeddedM4bChaptersSurviveRelaunchAndNavigate() {
        saveBook("Embedded Book", "Fixture Author", "Embedded Chapters.m4b")
        tapText("Embedded Book")
        field("book.play").click()
        dismissNotificationPrompt()
        field("player.chapters").click()
        visible(By.text("Opening"))
        visible(By.text("The Journey"))
        visible(By.text("Home Again"))
        screenshot("embedded-chapters-light")
        device.executeShellCommand("cmd uimode night yes")
        field("chapters.row.2")
        screenshot("embedded-chapters-dark")
        field("chapters.row.2").click()
        waitForElapsed { it >= 60 }
        field("player.playPause").click()
        field("player.saveMoment").click()
        field("moment.name").setText("Embedded chapter moment")
        dismissKeyboard()
        field("moment.done").click()
        visible(By.text("Saved!"))
        relaunch()
        tapText("Embedded Book")
        field("book.moments").click()
        tapDescription("Play from this moment")
        field("player.chapters").click()
        visible(By.text("Home Again"))
        assertEquals(3, device.findObjects(By.res(java.util.regex.Pattern.compile("chapters.row.[0-9]+"))).size)
    }

    @Test fun renameContextMenuActionsAndResetCancellationPersist() {
        saveBook("Rename Me", "Fixture Author", "Another.wav")
        device.findObject(By.text("Rename Me")).longClick()
        field("book.menu.rename")
        screenshot("book-menu-light")
        device.executeShellCommand("cmd uimode night yes")
        field("book.menu.rename")
        screenshot("book-menu-dark")
        field("book.menu.rename").click()
        field("book.rename.title").setText("Renamed Book")
        screenshot("rename-dark")
        device.executeShellCommand("cmd uimode night no")
        field("book.rename.title")
        screenshot("rename-light")
        field("book.rename.save").click()
        relaunch()
        visible(By.text("Renamed Book"))
        assertFalse(device.hasObject(By.text("Rename Me")))
        device.findObject(By.text("Renamed Book")).longClick()
        field("book.menu.favorite").click()
        field("tab.Favorites").click()
        visible(By.text("Renamed Book"))
        device.findObject(By.text("Renamed Book")).longClick()
        field("book.menu.resume").click()
        dismissNotificationPrompt()
        field("player.playPause")
        tapDescription("Close player")
        visible(By.res(java.util.regex.Pattern.compile("book\\.card\\..*"))).longClick()
        field("book.menu.rename").click()
        field("book.rename.title").setText("Active Renamed Book")
        field("book.rename.save").click()
        visible(By.res("miniPlayer.title").text("Active Renamed Book"))
        field("miniPlayer").click()
        visible(By.res("player.title").text("Active Renamed Book"))
        field("player.close").click()
        tapDescription("Settings")
        scrollTo("settings.resetOnboarding")
        field("settings.resetOnboarding").click()
        visible(By.text("Reset Onboarding?"))
        screenshot("reset-confirmation-light")
        device.executeShellCommand("cmd uimode night yes")
        visible(By.text("Reset Onboarding?"))
        screenshot("reset-confirmation-dark")
        tapText("Cancel")
        assertFalse(device.hasObject(By.res("onboarding")))
        scrollTo("settings.resetOnboarding"); field("settings.resetOnboarding") // Night mode recreates the sheet at half height.
    }

    @Test fun coverPhotoCropCancelPersistAndRemove() {
        saveBook("Cover Book", "Fixture Author", "Another.wav")
        tapText("Cover Book")
        field("book.cover").click()
        selectPickerFiles("Cover.png")
        field("cover.confirm")
        screenshot("cover-crop-light")
        device.executeShellCommand("cmd uimode night yes")
        field("cover.crop")
        screenshot("cover-crop-dark")
        device.executeShellCommand("cmd uimode night no")
        field("cover.cancel").click()
        field("book.cover")
        assertFalse(device.hasObject(By.res("cover.crop")))
        field("book.cover").click()
        selectPickerFiles("Cover.png")
        field("cover.crop").swipeLeft(5)
        field("cover.confirm").click()
        settleLayout()
        screenshot("cover-detail-light")
        device.executeShellCommand("cmd uimode night yes")
        field("book.cover")
        screenshot("cover-detail-dark")
        relaunch()
        tapText("Cover Book")
        field("book.cover").longClick()
        field("book.cover.remove")
        screenshot("cover-remove-dark")
        device.executeShellCommand("cmd uimode night no")
        field("book.cover.remove")
        screenshot("cover-remove-light")
        field("book.cover.remove").click()
        settleLayout()
        field("book.cover").longClick()
        assertFalse(device.hasObject(By.res("book.cover.remove")))
        device.pressBack()
        relaunch()
        tapText("Cover Book")
        field("book.cover").longClick()
        assertFalse(device.hasObject(By.res("book.cover.remove")))
    }

    @Test fun durableDownloadResumesPartialFileAfterForceStop() {
        absRequest("/_test/reset", "POST")
        device.executeShellCommand("am force-stop $app")
        device.executeShellCommand("am start -W -n $app/dev.unpaged.android.shelves.ShelvesFixtureActivity --ez e2e-shelves-fixture true --ez e2e-download-fixture true")
        field("tab.Shelves").click()
        field("shelves.book.133").click()
        scrollTo("shelves.download", scrollId = "shelves.detail")
        field("shelves.download").click()
        visible(By.text("Cancel Download"))
        android.os.SystemClock.sleep(1800)
        screenshot("download-light")
        device.executeShellCommand("cmd uimode night yes")
        visible(By.text("Cancel Download"))
        screenshot("download-dark")
        device.executeShellCommand("am force-stop $app")
        launch()
        field("tab.Shelves").click()
        field("shelves.book.133").click()
        val deadline = android.os.SystemClock.uptimeMillis() + 100_000
        do {
            val ranges = absRequest("/_test/state").getJSONArray("download_ranges")
            if (ranges.length() >= 2 && ranges.getLong(ranges.length() - 1) > 0) break
            android.os.SystemClock.sleep(300)
        } while (android.os.SystemClock.uptimeMillis() < deadline)
        val ranges = absRequest("/_test/state").getJSONArray("download_ranges")
        assertTrue("Relaunch must issue a nonzero HTTP Range", (0 until ranges.length()).any { ranges.getLong(it) > 0 })
        do {
            refreshAccessibility()
            if (!device.hasObject(By.text("Cancel Download"))) break
            android.os.SystemClock.sleep(500)
        } while (android.os.SystemClock.uptimeMillis() < deadline)
        assertFalse("Download should finish", device.hasObject(By.text("Cancel Download")))
        tapText("View in Library")
        field("book.play")
        assertFalse(device.hasObject(By.text("Streaming")))
        screenshot("download-complete-dark")
        device.executeShellCommand("cmd uimode night no")
        screenshot("download-complete-light")
        relaunch()
        tapText("Jane Eyre")
        field("book.play").click()
        dismissNotificationPrompt()
        waitForElapsed { it >= 1 }
    }

    @Test fun shelvesFixtureRendersHeroCollectionsAndClassics() {
        saveBook("E2E The Listening Book", "Fixture Author", "Chapter 1.wav", "Chapter 2.wav")
        tapDescription("Add favorite")
        saveBook("E2E Another Book", "Another Fixture Author", "Another.wav")
        field("tab.Shelves").click()
        field("shelves.hero")
        visible(By.text("TODAY'S PICK · 16H"))
        visible(By.text("Tale of Two Cities"))
        visible(By.text("Offline — showing saved books."))
        visible(By.text("Collections"))
        visible(By.text("Popular Classics"))
        field("shelves.book.133")
        screenshot("shelves-light")
        device.executeShellCommand("cmd uimode night yes")
        field("shelves.hero")
        screenshot("shelves-dark")
        device.executeShellCommand("cmd uimode night no")
        field("shelves.hero").click()
        field("shelves.detail")
        visible(By.text("About"))
        visible(By.text("London, Paris and the Revolution."))
        screenshot("shelves-detail-light")
        device.executeShellCommand("cmd uimode night yes")
        field("shelves.detail")
        screenshot("shelves-detail-dark")
    }

    @Test fun shelvesSearchFiltersAndCollection() {
        field("tab.Shelves").click()
        field("shelves.search").setText("Jane")
        field("shelves.book.133")
        field("shelves.filter.LANGUAGE").click()
        tapMenuText("German")
        visible(By.text("Nothing on this shelf."))
        field("shelves.search").setText("")
        field("shelves.book.1203")
        field("shelves.filter.LENGTH").click()
        tapMenuText("< 1 hr")
        visible(By.text("Nothing on this shelf."))
        field("shelves.filter.LENGTH").click()
        tapMenuText("Any Length")
        field("shelves.book.1203")
        field("shelves.filter.LANGUAGE").click()
        tapMenuText("All Languages")
        field("shelves.filter.GENRE").click()
        tapMenuText("Romance")
        field("shelves.book.133")
        field("shelves.filter.GENRE").click()
        tapMenuText("All Genres")
        repeat(8) {
            refreshAccessibility()
            if (!device.hasObject(By.res("shelves.hero"))) {
                val list = field("shelves.list").visibleBounds
                device.swipe(list.centerX(), list.top + 100, list.centerX(), list.bottom - 100, 30)
                settleLayout()
            }
        }
        field("shelves.hero")
        field("shelves.collection.gothic-horror").click()
        field("shelves.collection")
        visible(By.text("Vampires, monsters & haunted minds"))
        field("shelves.book.271")
        screenshot("shelves-collection-light")
        device.executeShellCommand("cmd uimode night yes")
        field("shelves.collection")
        screenshot("shelves-collection-dark")
    }

    @Test fun shelvesOfflineActionsDescriptionsAlternativesAndCollapsePersist() {
        field("tab.Shelves").click()
        assertFalse(field("shelves.sample.133").isEnabled)
        field("shelves.retry").click()
        visible(By.text("Offline — showing saved books."))
        tapDescription("Toggle collections")
        settleLayout()
        assertFalse(device.hasObject(By.res("shelves.collection.ancient-wisdom")))
        relaunch()
        field("tab.Shelves").click()
        field("shelves.hero")
        assertFalse(device.hasObject(By.res("shelves.collection.ancient-wisdom")))
        tapDescription("Toggle collections")
        field("shelves.collection.ancient-wisdom")
        field("shelves.hero").click()
        assertFalse(field("shelves.sample.detail").isEnabled)
        tapText("Show more")
        visible(By.text("Show less"))
        field("shelves.download").click()
        visible(By.text("You're offline. Connect to download this book."))
        tapText("OK")
        device.pressBack()
        field("shelves.search").setText("Pride and Prejudice")
        field("shelves.book.253").click()
        field("shelves.detail")
        settleLayout()
        // Wait for navigation before querying the detail list, then bring the
        // alternative row fully above the taskbar rather than only its header.
        repeat(8) {
            refreshAccessibility()
            val list = field("shelves.detail").visibleBounds
            val row = device.findObject(By.res("shelves.book.2531"))?.visibleBounds
            if (row != null && row.height() >= 44 && row.bottom < list.bottom - 20) return@repeat
            device.swipe(list.centerX(), list.bottom - 120, list.centerX(), list.top + 120, 30)
            settleLayout()
        }
        visible(By.text("Other Recordings"))
        field("shelves.book.2531").click()
        visible(By.text("A second full-cast recording."))
    }

    @Test fun shelvesAddStreamingIdentitySurvivesRelaunch() {
        field("tab.Shelves").click()
        field("shelves.hero").click()
        field("shelves.add").click()
        visible(By.text("Added to Your Library"))
        tapText("View in Library")
        visible(By.text("Streaming"))
        device.pressBack()
        // View in Library already selected this tab; tapping it again opens Sort.
        visible(By.text("Tale of Two Cities"))
        relaunch()
        visible(By.text("Tale of Two Cities"))
        field("tab.Shelves").click()
        field("shelves.hero").click()
        visible(By.text("Added to Your Library"))
        assertFalse(device.hasObject(By.res("shelves.add")))
        tapText("View in Library")
        visible(By.text("Streaming"))
    }

    private fun absRequest(path: String, method: String = "GET"): org.json.JSONObject {
        val connection = java.net.URL("http://127.0.0.1:13378/$path").openConnection() as java.net.HttpURLConnection
        connection.connectTimeout = 5000; connection.readTimeout = 5000; connection.requestMethod = method
        return try { org.json.JSONObject(connection.inputStream.bufferedReader().use { it.readText() }) } finally { connection.disconnect() }
    }

    private fun setABSTheme(dark: Boolean) {
        device.executeShellCommand("cmd uimode night ${if (dark) "yes" else "no"}")
        settleLayout()
    }

    private fun openABSConnect() {
        selectTab("Shelves")
        field("tab.Shelves").click()
        field("shelves.source.audiobookshelf").click()
        field("abs.connect.server")
    }

    private fun fillABSLogin(password: String) {
        field("abs.connect.server").setText("http://127.0.0.1:13378")
        field("abs.connect.username").setText("reader")
        field("abs.connect.password").setText(password)
        dismissKeyboard() // Only dismiss an actual input-method window.
        field("abs.connect.submit").click()
    }

    @Test fun absBadPasswordShowsInlineError() {
        absRequest("_test/reset", "POST")
        openABSConnect(); fillABSLogin("wrong")
        field("abs.connect.error")
        visible(By.text("That username and password didn't work. Check them and try again."))
        assertEquals(1, absRequest("_test/state").getInt("bad_password"))
        assertEquals(0, absRequest("_test/state").getInt("authorize"))
    }

    @Test fun absLoginBrowseAddStreamPersistenceAndDisconnect() {
        absRequest("_test/reset", "POST")
        selectTab("Shelves"); field("tab.Shelves").click()
        visible(By.text("Catalog source")); visible(By.text("Connect your server"))
        screenshot("abs-contract-source-menu-light")
        setABSTheme(true); settleLayout(); field("tab.Shelves").click(); field("shelves.source.audiobookshelf"); screenshot("abs-contract-source-menu-dark")
        setABSTheme(false); settleLayout(); field("tab.Shelves").click(); field("shelves.source.audiobookshelf").click()
        field("abs.connect.server")
        screenshot("abs-contract-connect-light")
        setABSTheme(true)
        field("abs.connect.server"); screenshot("abs-contract-connect-dark")
        setABSTheme(false)
        fillABSLogin("password")
        field("abs.book.fixture-book")
        visible(By.text("All Books")); visible(By.text("Continue Listening"))
        screenshot("abs-contract-browse-light")
        setABSTheme(true)
        field("abs.book.fixture-book"); screenshot("abs-contract-browse-dark")
        setABSTheme(false)
        field("abs.search").setText("The Server")
        dismissKeyboard()
        field("abs.book.fixture-book")
        assertFalse(device.hasObject(By.res("abs.book.fixture-other")))
        field("abs.search").setText("")
        dismissKeyboard()
        field("abs.libraryPicker").click(); tapText("Second Library")
        visible(By.text("This shelf is empty."))
        field("abs.libraryPicker").click(); tapText("My Audiobooks")
        field("abs.book.fixture-book").click()
        field("abs.detail"); visible(By.text("20% listened"))
        screenshot("abs-contract-detail-light")
        setABSTheme(true)
        field("abs.detail"); screenshot("abs-contract-detail-dark")
        setABSTheme(false)
        scrollTo("abs.add", scrollId = "abs.detail")
        field("abs.add").click(); field("abs.added")
        scrollTo("abs.viewLibrary", scrollId = "abs.detail")
        field("abs.viewLibrary").click()
        visible(By.text("Streaming")); field("book.play").click()
        dismissNotificationPrompt()
        field("player.playPause")
        val deadline = android.os.SystemClock.uptimeMillis() + 15000
        var server = absRequest("_test/state")
        while ((server.getInt("tokenized_streams") == 0 || server.getJSONArray("progress").length() == 0) && android.os.SystemClock.uptimeMillis() < deadline) {
            android.os.SystemClock.sleep(200); server = absRequest("_test/state")
        }
        assertTrue("Server must see a tokenized stream", server.getInt("tokenized_streams") > 0)
        assertTrue("Server must see a progress update", server.getJSONArray("progress").length() > 0)
        assertTrue("Cover requests must authenticate", server.getInt("covers") > 0)
        assertEquals(1, server.getInt("login"))
        val progress = server.getJSONArray("progress").getJSONObject(0)
        assertEquals(60.0, progress.getDouble("duration"), .01)
        field("player.playPause").click()
        device.pressBack(); device.pressBack()
        visible(By.text("The Server Book"))
        screenshot("abs-library-light")
        setABSTheme(true)
        visible(By.text("The Server Book")); screenshot("abs-library-dark")
        setABSTheme(false)
        device.executeShellCommand("am force-stop $app"); launch()
        selectTab("Shelves"); field("abs.book.fixture-book").click()
        field("abs.added")
        assertFalse(device.hasObject(By.res("abs.add")))
        field("abs.back").click()
        field("abs.browse")
        tapDescription("Settings")
        field("settings.audiobookshelf"); screenshot("abs-contract-settings-light")
        setABSTheme(true); field("settings.audiobookshelf"); screenshot("abs-contract-settings-dark")
        setABSTheme(false)
        field("settings.audiobookshelf").click()
        visible(By.text("reader")); screenshot("abs-contract-server-settings-light")
        setABSTheme(true); field("abs.settings"); screenshot("abs-contract-server-settings-dark")
        setABSTheme(false)
        field("abs.settings.disconnect").click(); field("abs.settings.disconnect.confirm").click()
        device.pressBack()
        field("tab.Shelves").click(); field("shelves.source.librivox"); device.pressBack()
        device.executeShellCommand("am force-stop $app"); launch(); selectTab("Shelves")
        field("tab.Shelves").click(); field("shelves.source.librivox"); device.pressBack()
        // The local streaming row remains after disconnect.
        selectTab("Library"); visible(By.text("The Server Book"))
    }

    @Test fun absVisualParityAndDetailBackNavigation() {
        absRequest("_test/visual", "POST")
        try {
            selectTab("Shelves"); field("tab.Shelves").click()
            visible(By.text("Catalog source")); visible(By.text("Connect your server"))
            screenshot("abs-source-menu-light")
            setABSTheme(true); settleLayout(); field("tab.Shelves").click(); field("shelves.source.audiobookshelf"); screenshot("abs-source-menu-dark")
            setABSTheme(false); settleLayout(); field("tab.Shelves").click(); field("shelves.source.audiobookshelf").click()
            field("abs.connect.server"); screenshot("abs-connect-light")
            setABSTheme(true); field("abs.connect.server"); screenshot("abs-connect-dark")
            setABSTheme(false); fillABSLogin("password")
            field("abs.book.fixture-book"); visible(By.text("E2E Shelf")); visible(By.text("Continue Listening")); assertTrue(device.wait(Until.gone(By.res("abs.loading")), 15000)); screenshot("abs-browse-light")
            setABSTheme(true); settleLayout(); visible(By.text("Continue Listening")); assertTrue(device.wait(Until.gone(By.res("abs.loading")), 15000)); screenshot("abs-browse-dark")
            setABSTheme(false); field("abs.book.fixture-book").click()
            visible(By.text("40% listened")); field("abs.back")
            assertFalse("Detail hides shell tabs", device.hasObject(By.res("tab.Shelves")))
            screenshot("abs-detail-light")
            setABSTheme(true); settleLayout(); visible(By.text("40% listened")); visible(By.text("Resume")); screenshot("abs-detail-dark")
            setABSTheme(false); field("abs.add").click()
            field("abs.added"); assertFalse(device.hasObject(By.res("abs.add"))); screenshot("abs-detail-added-light")
            field("abs.back").click(); field("abs.browse")
            field("abs.book.fixture-book").click(); field("abs.added")
            device.pressBack(); field("abs.browse")
            visible(By.text("Continue Listening")); assertTrue(device.wait(Until.gone(By.res("abs.loading")), 15000))
            tapDescription("Settings"); field("settings.audiobookshelf"); screenshot("abs-settings-light")
            setABSTheme(true); settleLayout(); field("settings.audiobookshelf"); screenshot("abs-settings-dark")
            setABSTheme(false); field("settings.audiobookshelf").click()
            field("abs.settings"); screenshot("abs-server-settings-light")
            setABSTheme(true); field("abs.settings"); screenshot("abs-server-settings-dark")
            setABSTheme(false)
            device.pressBack(); tapText("Done"); field("abs.browse")
            field("abs.book.fixture-book").click(); field("abs.added")
            field("abs.play").click(); dismissNotificationPrompt()
            field("player.playPause").click(); field("player.close").click()
            field("abs.detail"); field("abs.added")
            assertFalse("Returning from player keeps pushed detail", device.hasObject(By.res("tab.Shelves")))
            field("abs.back").click(); field("abs.browse")
        } finally { absRequest("_test/reset", "POST") }
    }

    private fun launch() {
        device.executeShellCommand("am start -W -n $app/dev.unpaged.android.MainActivity")
        visible(By.pkg(app).depth(0))
    }

    private fun visible(selector: BySelector): UiObject2 {
        val deadline = android.os.SystemClock.uptimeMillis() + 15_000
        do {
            refreshAccessibility()
            device.findObject(selector)?.let { return it }
            android.os.SystemClock.sleep(100)
        } while (android.os.SystemClock.uptimeMillis() < deadline)
        throw AssertionError("Missing UI: $selector")
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

    private fun refreshAccessibility() {
        // The API35 accessibility cache can retain a prior Compose semantics tree
        // after timed labels or layout changes; fresh queries must read the screen.
        if (android.os.Build.VERSION.SDK_INT >= 33) instrumentation.uiAutomation.clearCache()
    }

    private fun settleLayout() {
        device.waitForIdle(500)
        // Compose geometry can settle after accessibility idle, even with animator scale 0.
        android.os.SystemClock.sleep(400)
        device.waitForIdle(500)
    }

    private fun screenshot(name: String) {
        settleLayout()
        val file = File(captureDirectory(), "$name.png")
        assertTrue(device.takeScreenshot(file))
        persistCapture(file)
    }
}
