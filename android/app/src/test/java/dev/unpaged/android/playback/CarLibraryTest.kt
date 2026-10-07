package dev.unpaged.android.playback

import androidx.media3.common.util.UnstableApi
import dev.unpaged.android.LibrarySort
import dev.unpaged.android.UnpagedPreferences
import dev.unpaged.android.library.*
import dev.unpaged.android.shelves.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@androidx.annotation.OptIn(UnstableApi::class)
class CarLibraryTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private fun book(id: String, title: String, favorite: Boolean = false, played: Long? = null) = LibraryBook(id, title, "Author",
        listOf(LibraryTrack("Chapter 1", "1.wav", "1.wav", 120000, id)), isFavorite = favorite, lastPlayedAt = played, dateAdded = 1)
    @Before fun reset() {
        context.deleteDatabase("library.db"); context.deleteDatabase("librivox-catalog.db")
        context.getSharedPreferences("unpaged", 0).edit().clear().commit()
    }
    @Test fun rootTabsOrderMetadataAndUnknownIDs() {
        var loaded = false
        val library = CarLibrary(context, playback = { PlayerState(book = if (loaded) book("root-book", "Loaded") else null) })
        val tabs = library.children(CarLibrary.ROOT)
        assertEquals(listOf("Favorites", "Library", "Shelves"), tabs.map { it.mediaId })
        loaded = true
        val playing = library.children(CarLibrary.ROOT)
        assertEquals(listOf("Favorites", "Library", "Shelves", "chapters"), playing.map { it.mediaId })
        assertEquals("Chapters", playing.last().mediaMetadata.title)
        assertTrue(playing.all { it.mediaMetadata.artworkUri?.scheme == "android.resource" })
        assertTrue(tabs.all { it.mediaMetadata.isBrowsable == true && it.mediaMetadata.isPlayable == false })
        assertNull(library.item("file:///etc/passwd"))
        assertNull(library.item("https://example.com/arbitrary.mp3"))
        assertEquals("Unpaged", library.item(CarLibrary.ROOT)?.mediaMetadata?.title)
    }
    @Test fun chapterRowsRejectIDsFromAnotherBookAndMalformedIndexes() {
        val first = book("one:with separator", "First")
        var state = PlayerState(book = first, chapters = listOf(PlaybackChapter(0, "Chapter", 0, 0, 120000)))
        CarLibrary(context, playback = { state }).use { library ->
            val old = library.children(CarLibrary.CHAPTERS).single()
            assertEquals("chapter:one%3Awith%20separator:0", old.mediaId)
            assertNotNull(library.chapter(old.mediaId))
            assertNotNull(library.item(old.mediaId))
            state = state.copy(book = book("two", "Second"))
            assertNull(library.chapter(old.mediaId)); assertNull(library.item(old.mediaId))
            assertNotEquals(old.mediaId, library.children(CarLibrary.CHAPTERS).single().mediaId)
            for (id in listOf("chapter:0", "chapter:two:-1", "chapter:two:99999999999", "chapter:two:0:extra"))
                assertNull(library.chapter(id))
            state = state.copy(book = null)
            assertTrue(library.children(CarLibrary.CHAPTERS).isEmpty())
        }
    }
    @Test fun folderInvalidationFollowsCommittedPhoneMutationsAcrossStoreInstances() {
        val store = SQLiteLibraryStore(context); val other = SQLiteLibraryStore(context); val catalog = SQLiteCatalogStore(context)
        fun committed(action: () -> Unit) {
            val before = LibraryContentChanges.changes.value
            action(); assertTrue(LibraryContentChanges.changes.value > before)
        }
        try {
            committed { store.insert(book("one", "First")) }
            committed { other.toggleFavorite("one") }
            committed { catalog.seed(listOf(CatalogBook("133", "Jane Eyre", "Author", "", "English", 60))) }
            committed { catalog.commit(listOf(CatalogBook("314", "Sherlock Holmes", "Author", "", "English", 60)), SyncCursor()) }
            val beforeFailure = LibraryContentChanges.changes.value
            assertThrows(android.database.sqlite.SQLiteConstraintException::class.java) { store.insert(book("one", "Duplicate")) }
            assertEquals(beforeFailure, LibraryContentChanges.changes.value)
            committed { other.delete("one") }
        } finally { store.close(); other.close(); catalog.close() }
    }
    @Test fun carListsUseLibrarySortForBothTabsAndDurableSubtitle() {
        val store = SQLiteLibraryStore(context)
        try {
            store.insert(book("a", "Zulu", true, 20)); store.insert(book("b", "Alpha", true, 10)); store.insert(book("c", "Other", false, 30))
            store.updatePlaybackProgress("a", PlaybackProgress(0, 10000, 65000, playedAt = 20))
            UnpagedPreferences(context).setSort("Library", LibrarySort.TITLE)
            UnpagedPreferences(context).setSort("Favorites", LibrarySort.DURATION)
            val library = CarLibrary(context, store)
            assertEquals(listOf("Alpha", "Other", "Zulu"), library.children("Library").map { it.mediaMetadata.title })
            assertEquals(listOf("Alpha", "Zulu"), library.children("Favorites").map { it.mediaMetadata.title })
            val row = library.item("book:a")!!
            assertEquals("Chapter 1 · 01:05", row.mediaMetadata.subtitle)
            assertEquals("content", row.mediaMetadata.artworkUri?.scheme)
            assertNull(row.mediaMetadata.artworkData)
            assertTrue(row.mediaMetadata.isPlayable == true)
        } finally { store.close() }
    }
    @Test fun shelvesOnlyCachedCuratedClassicsInCuratedOrder() {
        val catalog = SQLiteCatalogStore(context)
        try {
            catalog.seed(listOf(CatalogBook("133", "Jane Eyre", "Charlotte Brontë", "", "English", 3600),
                CatalogBook("314", "Sherlock Holmes", "Arthur Conan Doyle", "", "English", 7200),
                CatalogBook("99999", "Uncurated", "Author", "", "English", 0)))
            val rows = CarLibrary(context, catalog = catalog).children("Shelves")
            assertEquals(listOf("catalog:314", "catalog:133"), rows.map { it.mediaId })
            assertEquals("Charlotte Brontë · 1h", rows[1].mediaMetadata.subtitle)
            val store = SQLiteLibraryStore(context)
            try { store.insert(book("added", "Jane Eyre").copy(isFreeBook = true, catalogId = "133")) }
            finally { store.close() }
            assertEquals(listOf("catalog:314"), CarLibrary(context, catalog = catalog).children("Shelves").map { it.mediaId })
        } finally { catalog.close() }
    }
    @Test fun voiceMatchesLibraryBeforeClassicsAndDeduplicatesTitles() {
        val books = listOf(book("local", "Jane Eyre"), book("author", "Poems").copy(author = "Charlotte Brontë"))
        val classics = listOf(CatalogBook("133", "Jane Eyre", "Charlotte Brontë", "", "English", 3600),
            CatalogBook("253", "Another Story", "Charlotte Brontë", "", "English", 3600))
        assertEquals(listOf("book:author", "catalog:133", "catalog:253"), CarLibrary.searchIDs("  bronte  ", books, classics))
        assertEquals(listOf("book:local"), CarLibrary.searchIDs("jane", books, classics))
        assertTrue(CarLibrary.searchIDs("missing", books, classics).isEmpty())
    }
    @Test fun emptyVoiceUsesLatestPlayableAndHandlesEmptyLibrary() {
        val books = listOf(book("old", "Old", played = 100), book("new", "New", played = 200), book("empty", "Empty", played = 300).copy(tracks = emptyList()))
        assertEquals(listOf("book:new"), CarLibrary.searchIDs("", books, emptyList()))
        assertTrue(CarLibrary.searchIDs(" ", emptyList(), emptyList()).isEmpty())
    }
    @Test fun paginationBoundsDoNotOverflow() {
        val items = CarLibrary.tabs.map { CarLibrary.folder(it) }
        assertEquals(listOf("Shelves"), CarLibrary.page(items, 1, 2).map { it.mediaId })
        assertTrue(CarLibrary.page(items, Int.MAX_VALUE, Int.MAX_VALUE).isEmpty())
        assertThrows(IllegalArgumentException::class.java) { CarLibrary.page(items, -1, 1) }
        assertThrows(IllegalArgumentException::class.java) { CarLibrary.page(items, 0, 0) }
    }
    @Test fun carStreamingAdditionReusesIdentityAndNeverDownloads() = kotlinx.coroutines.runBlocking {
        val store = SQLiteLibraryStore(context); val catalog = SQLiteCatalogStore(context)
        try {
            val classic = CatalogBook("133", "Jane Eyre", "Charlotte Bronte", "", "English", 60,
                tracks = listOf(CatalogTrack(1, "Chapter", 60, "https://example.com/one.mp3")))
            catalog.seed(listOf(classic))
            val library = CarLibrary(context, store, catalog) { true }
            val first = library.resolve("catalog:133")
            val second = library.resolve("catalog:133")
            assertEquals(first.id, second.id); assertEquals(1, store.books().size)
            assertFalse(first.isDownloaded); assertTrue(first.isFreeBook)
            assertEquals("https://example.com/one.mp3", first.tracks.single().remoteUrl)
            assertEquals("", first.tracks.single().storedName)
            assertEquals(0L, first.storageBytes)
            val local = first.copy(id = "downloaded", isDownloaded = true,
                tracks = listOf(LibraryTrack("Chapter", "1.wav", "1.wav", 60000, "local")))
            store.insert(local)
            val offline = CarLibrary(context, store, catalog) { false }
            assertEquals("downloaded", offline.resolve("catalog:133").id)
        } finally { store.close(); catalog.close() }
    }
    @Test fun offlineStreamingSelectionFailsBeforeAddingOrChangingLibrary() = kotlinx.coroutines.runBlocking {
        val store = SQLiteLibraryStore(context); val catalog = SQLiteCatalogStore(context)
        try {
            catalog.seed(listOf(CatalogBook("133", "Jane Eyre", "Charlotte Bronte", "", "English", 60)))
            val library = CarLibrary(context, store, catalog) { false }
            try { library.resolve("catalog:133"); fail("Expected offline failure") }
            catch (error: IllegalStateException) { assertEquals("No internet connection", error.message) }
            assertTrue(store.books().isEmpty())
            store.insert(book("remote", "Remote").copy(isDownloaded = false))
            try { library.resolve("book:remote"); fail("Expected offline failure") }
            catch (error: IllegalStateException) { assertEquals("No internet connection", error.message) }
            assertEquals(1, store.books().size)
        } finally { store.close(); catalog.close() }
    }
    @Test fun callerPolicyRefusesUnknownAndAllowsTrustedAndCarPackages() {
        assertFalse(BrowserCallerPolicy.allowed("untrusted", "own", false, false))
        assertTrue(BrowserCallerPolicy.allowed("own", "own", false, false))
        assertTrue(BrowserCallerPolicy.allowed("notification-controller", "own", true, false))
        assertTrue(BrowserCallerPolicy.allowed("com.google.android.projection.gearhead", "own", false, false))
        assertTrue(BrowserCallerPolicy.allowed("com.android.car.media", "own", false, false))
        assertTrue(BrowserCallerPolicy.allowed("test", "own", false, true))
    }
    @Test fun carCommandsSaveOffsetMomentMarkCycleAndPersistSequence() {
        val store = SQLiteLibraryStore(context)
        val preferences = UnpagedPreferences(context)
        preferences.setSeconds("momentBacktrackSeconds", 10)
        preferences.setSeconds("carPlayMomentSequence", 998)
        var rate = PlaybackRules.speeds.last(); var marked = false; var loaded = true
        val title = book("one", "Book")
        try {
            store.insert(title)
            val commands = CarCommands(preferences, { loaded }, {
                LibraryMoment(java.util.UUID.randomUUID().toString(), title.id, 0,
                    PlaybackRules.momentTime(35000, preferences.seconds("momentBacktrackSeconds", 0)), "Saved Moment")
            }, store::saveMoment, { marked = true; store.setProgressMarker(title.id, 35000) }, { rate }, { rate = it })
            assertEquals(0, commands.perform(CarSessionCallback.SAVE_MOMENT).resultCode)
            assertEquals(0, commands.perform(CarSessionCallback.SAVE_MOMENT).resultCode)
            assertEquals(setOf("CarPlay 999", "CarPlay 1"), store.moments(title.id).map { it.label }.toSet())
            assertTrue(store.moments(title.id).all { it.timeMs == 25000L })
            assertEquals(1, UnpagedPreferences(context).seconds("carPlayMomentSequence", 0))
            assertEquals(0, commands.perform(CarSessionCallback.MARK_PROGRESS).resultCode)
            assertTrue(marked); assertEquals(35000L, store.books().single().highWaterMarkMs)
            assertEquals(0, commands.perform(CarSessionCallback.CYCLE_SPEED).resultCode)
            assertEquals(PlaybackRules.speeds.first(), rate)
            assertEquals(androidx.media3.session.SessionError.ERROR_NOT_SUPPORTED, commands.perform("unknown").resultCode)
            loaded = false
            assertEquals(androidx.media3.session.SessionError.ERROR_INVALID_STATE, commands.perform(CarSessionCallback.SAVE_MOMENT).resultCode)
            assertEquals(2, store.moments(title.id).size)
        } finally { store.close() }
        val reopened = SQLiteLibraryStore(context)
        try { assertEquals(2, reopened.moments(title.id).size); assertEquals(35000L, reopened.books().single().highWaterMarkMs) }
        finally { reopened.close() }
    }
    @Test fun artworkProviderServesOnlyGeneratedPngAndRejectsPathsAndWrites() {
        val store = SQLiteLibraryStore(context)
        try { store.insert(book("cover", "Cover Title")) } finally { store.close() }
        val provider = org.robolectric.Robolectric.buildContentProvider(CarArtworkProvider::class.java).create().get()
        val uri = CarArtworkProvider.uri(context, "book:cover")
        val bytes = android.os.ParcelFileDescriptor.AutoCloseInputStream(provider.openFile(uri, "r")).use { it.readBytes() }
        assertTrue(bytes.take(4).toByteArray().contentEquals(byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47)))
        assertThrows(java.io.FileNotFoundException::class.java) { provider.openFile(uri, "w") }
        assertThrows(java.io.FileNotFoundException::class.java) { provider.openFile(CarArtworkProvider.uri(context, "book:unknown"), "r") }
        assertThrows(java.io.FileNotFoundException::class.java) { provider.openFile(uri.buildUpon().appendPath("..").build(), "r") }
    }
    @Test fun customButtonsExposeCarPlayOrderAndDistinctCommands() {
        val buttons = CarSessionCallback.buttons()
        assertEquals(listOf("Playback Rate", "Save Moment", "Mark Progress"), buttons.map { it.displayName })
        assertEquals(CarSessionCallback.actions, buttons.map { it.sessionCommand?.customAction })
        assertEquals(3, buttons.map { it.sessionCommand }.toSet().size)
    }
}
