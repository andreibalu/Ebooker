package dev.unpaged.android.playback

import androidx.media3.common.util.UnstableApi
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
    @Test fun voiceSearchToleratesFillerWordOrderAndPunctuation() {
        val books = listOf(book("pp", "Pride and Prejudice").copy(author = "Jane Austen"),
            book("alice", "Alice's Adventures in Wonderland").copy(author = "Lewis Carroll"),
            book("pride", "Pride of Lions").copy(author = "Someone"))
        assertEquals("book:pp", CarLibrary.searchIDs("Pride and Prejudice by Jane Austen", books, emptyList()).first())
        assertEquals(listOf("book:pp"), CarLibrary.searchIDs("Austen Pride", books, emptyList()))
        assertEquals(listOf("book:alice"), CarLibrary.searchIDs("Alices adventures", books, emptyList()))
        assertEquals(listOf("book:alice"), CarLibrary.searchIDs("alice\u2019s, adventures!", books, emptyList()))
        assertEquals("book:pp", CarLibrary.searchIDs("prejudice pride", books, emptyList()).single())
        assertEquals(listOf("pride", "prejudice"), CarLibrary.searchTokens("the Pride by Prejudice"))
        assertEquals(listOf("the"), CarLibrary.searchTokens("the"))
        assertTrue(CarLibrary.searchIDs("Pride by Dickens", books, emptyList()).isEmpty())
    }
    @Test fun exactPhraseOutranksTokenOnlyMatches() {
        val loose = book("loose", "Wonder Alice").copy(author = "A")
        val exact = book("exact", "Alice Wonder").copy(author = "B")
        assertEquals(listOf("book:exact", "book:loose"), CarLibrary.searchIDs("alice wonder", listOf(loose, exact), emptyList()))
    }
    @Test fun subscribingDuringDebouncePreservesExistingBrowsersBaseline() {
        val filter = ChildrenChangeFilter()
        val before = listOf(CarLibrary.bookItem(book("a", "Alpha")))
        val after = before + CarLibrary.bookItem(book("b", "Beta"))
        filter.subscribe("Library", before)
        filter.subscribe("Library", after)
        assertTrue(filter.changed("Library", after))
        assertFalse(filter.changed("Library", after))
        filter.subscribe("Favorites", emptyList())
        assertFalse(filter.changed("Favorites", emptyList()))
    }

}
