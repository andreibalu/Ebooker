package dev.unpaged.android.library

import android.content.Context
import org.robolectric.RuntimeEnvironment
import dev.unpaged.android.shelves.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.net.UnknownHostException

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class LibriVoxTest {
    private lateinit var context: Context
    private fun book(id: String, title: String = "Classic") = CatalogBook(id, title, "Author", "About", "English", 3600)
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("librivox-catalog.db"); context.deleteDatabase("library.db")
    }
    @Test fun decodingAcceptsIntegerAndStringIdentifiersAndDurations() {
        val b = LibriVoxClient.decodeBook(JSONObject("""{"id":133,"title":"Jane Eyre","totaltimesecs":"68400","authors":[{"first_name":"Charlotte","last_name":"Brontë"}],"genres":[{"name":"Romance"}]}"""))
        assertEquals("133", b.id); assertEquals("Charlotte Brontë", b.author); assertEquals("19h", b.duration)
        assertEquals(listOf("Romance"), b.genres); assertEquals(547, b.sizeMB)
        assertEquals(3723L, LibriVoxClient.decodeTrack(JSONObject("""{"section_number":"2","playtime":"1:02:03"}""")).seconds)
    }
    @Test fun errorEnvelopeAndNullArraysAreEmpty() {
        for (json in listOf("""{"error":"Audiobooks could not be found"}""", "{}", """{"books":null}"""))
            assertTrue(LibriVoxClient(FeedEngine { FeedResponse(200, json) }).books(emptyList()).isEmpty())
    }
    @Test fun exactCatalog404SentinelIsEmptyButOther404IsFailure() {
        assertTrue(LibriVoxClient(FeedEngine { FeedResponse(404, """{"error":"Audiobooks could not be found"}""") }).books(emptyList()).isEmpty())
        try { LibriVoxClient(FeedEngine { FeedResponse(404, "{}") }).books(emptyList()); fail() }
        catch (error: FeedProblem) { assertEquals(404, error.status) }
    }
    @Test fun httpStatusCheckedBeforeDecoding() {
        try { LibriVoxClient(FeedEngine { FeedResponse(503, "maintenance") }).books(emptyList()); fail() }
        catch (error: FeedProblem) { assertEquals(503, error.status) }
    }
    @Test fun htmlAndInvalidArrayAreTypedFailures() {
        for (json in listOf("<html>Down</html>", """{"books":"wrong"}""", """{"books":[42]}""")) {
            try { LibriVoxClient(FeedEngine { FeedResponse(200, json) }).books(emptyList()); fail() }
            catch (error: FeedProblem) { assertNull(error.status) }
        }
    }
    @Test fun networkFailureRetainsOfflineClassification() {
        val offline = UnknownHostException("offline")
        try { LibriVoxClient(FeedEngine { throw offline }).books(emptyList()); fail() }
        catch (error: UnknownHostException) { assertSame(offline, error); assertTrue(ShelvesViewModel.isOffline(error)) }
    }
    @Test fun queryEscapesDelimitersAndExtendedGenresAreRequested() {
        var captured = ""
        LibriVoxClient(FeedEngine { captured = it; FeedResponse(200, "{}") }).genre("Action & Adventure=+?#")
        assertTrue(captured.contains("extended=1")); assertTrue(captured.contains("genre=Action%20%26%20Adventure%3D%2B%3F%23"))
    }
    @Test fun tracksSortByNumericSection() {
        val client = LibriVoxClient(FeedEngine { FeedResponse(200, """{"sections":[{"section_number":"10","title":"Ten"},{"section_number":2,"title":"Two"}]}""") })
        assertEquals(listOf(2, 10), client.tracks("133").map { it.number })
    }
    @Test fun searchMergesBothEndpointsAndRanksTitlesBeforeAuthors() {
        val client = LibriVoxClient(FeedEngine { url -> FeedResponse(200, if (url.contains("title="))
            """{"books":[{"id":1,"title":"Jane Eyre"}]}""" else """{"books":[{"id":1,"title":"Jane Eyre"},{"id":2,"title":"Other","author":"Jane Author"}]}""") })
        assertEquals(listOf("1", "2"), client.search("Jane").map { it.id })
    }
    @Test fun knownStackedSuffixesFoldWithoutMergingTranslations() {
        assertEquals("pride and prejudice", OtherRecordings.key("Pridé and  Prejudice (version 2) (solo)"))
        assertEquals("text", OtherRecordings.key("Text (version 3 dramatic reading)"))
        assertNotEquals(OtherRecordings.key("Iliad (Pope Translation)"), OtherRecordings.key("Iliad (Butler Translation)"))
    }
    @Test fun alternativesMatchAuthorAndLanguageAndSortOriginalThenNumericVersion() {
        val original = book("1", "Text"); val current = book("2", "Text (version 2)")
        val rows = listOf(book("10", "Text (version 10)"), book("3", "Text (version 3)"), original,
            book("4", "Text (dramatic reading)"), current, original.copy(id = "5", language = "German"), original.copy(id = "6", author = "Other"))
        assertEquals(listOf("1", "3", "10", "4"), OtherRecordings.alternatives(current, rows).map { it.id })
    }
    @Test fun dailyPickUsesOneBasedOrdinalModuloAndLeapYear() {
        assertEquals("253", Classics.pick(1)); assertEquals("510", Classics.pick(279))
        assertEquals(Classics.ids[366 % 8], Classics.pick(366)); assertEquals(Classics.pick(42), Classics.pick(42))
    }
    @Test fun sqlitePageAndCheckpointSurviveReopenAndMetadataPreservesTracks() {
        val tracks = listOf(CatalogTrack(1, "Chapter", 300, "https://example.com/a.mp3"))
        SQLiteCatalogStore(context).withDatabase { it.commit(listOf(book("133").copy(tracks = tracks)), SyncCursor(50, 0, 100, 0, false)) }
        SQLiteCatalogStore(context).withDatabase {
            assertEquals(50, it.cursor().offset); it.seed(listOf(book("133", "Updated")))
            assertEquals(tracks, it.books().single().tracks); assertEquals(50, it.cursor().offset)
        }
    }
    @Test fun fullSyncResumesCommittedPageAndCompletesWithoutDuplicates() = runBlocking {
        SQLiteCatalogStore(context).withDatabase { store ->
            var calls = 0
            val sync = CatalogSync(store, { offset, _ -> calls++; if (offset == 0) (1..50).map { book("$it") } else throw FeedProblem(503) }, { 1000 }, {})
            try { sync.run(); fail() } catch (_: FeedProblem) { }
            assertEquals(4, calls); assertEquals(50, store.cursor().offset); assertEquals(50, store.count())
        }
        SQLiteCatalogStore(context).withDatabase { store ->
            val offsets = mutableListOf<Int>()
            CatalogSync(store, { offset, since -> offsets += offset; assertEquals(0L, since); listOf(book("51")) }, { 2000 }, {}).run()
            assertEquals(listOf(50), offsets); assertEquals(51, store.count()); assertTrue(store.cursor().ready)
            assertEquals(1000L, store.cursor().completed)
        }
    }
    @Test fun retryIsThreeAttemptsWithLinearBackoff() = runBlocking {
        SQLiteCatalogStore(context).withDatabase { store ->
            var calls = 0; val delays = mutableListOf<Long>()
            try { CatalogSync(store, { _, _ -> calls++; throw FeedProblem(503) }, { 1000 }, { delays += it }).run(); fail() }
            catch (_: FeedProblem) { }
            assertEquals(3, calls); assertEquals(listOf(1000L, 2000L), delays); assertEquals(0, store.cursor().offset)
        }
    }
    @Test fun permanentErrorsAndCancellationAreNotRetried() = runBlocking {
        for (problem in listOf(FeedProblem(400), CancellationException())) SQLiteCatalogStore(context).withDatabase { store ->
            var calls = 0
            try { CatalogSync(store, { _, _ -> calls++; throw problem }, { 1000 }, { fail("Unexpected backoff") }).run(); fail() }
            catch (error: Exception) { assertSame(problem, error) }
            assertEquals(1, calls); assertEquals(0, store.count())
        }
    }
    @Test fun refreshWaits24HoursAndUsesLastSuccessfulStartTimestamp() = runBlocking {
        SQLiteCatalogStore(context).withDatabase { store ->
            store.commit(listOf(book("1")), SyncCursor(completed = 1000, ready = true))
            CatalogSync(store, { _, _ -> fail("Not due"); emptyList() }, { 86_400_999 }, {}).run()
            CatalogSync(store, { offset, since -> assertEquals(0, offset); assertEquals(1000L, since); emptyList() }, { 86_401_000 }, {}).run()
            assertEquals(86_401_000L, store.cursor().completed); assertEquals(1, store.count())
        }
    }
    @Test fun catalogIdentityAddsOnceAndDoesNotMergeOtherRecordings() {
        SQLiteLibraryStore(context).withDatabase { store ->
            val service = CatalogLibraryService(store)
            val tracks = listOf(CatalogTrack(1, "One", 300, "https://example.com/a.mp3"))
            val first = service.add(book("133"), tracks)
            assertEquals(first.id, service.add(book("133", "Renamed upstream"), tracks).id)
            service.add(book("134"), tracks)
            assertEquals(2, store.books().size); assertTrue(first.isFreeBook); assertFalse(first.isDownloaded)
            assertEquals("", first.tracks.single().storedName); assertNotNull(first.tracks.single().remoteUrl)
        }
    }
    @Test fun promotionPreservesBookIdentityProgressFavoritesAndMoments() {
        SQLiteLibraryStore(context).withDatabase { store ->
            val service = CatalogLibraryService(store)
            val first = service.add(book("133"), listOf(CatalogTrack(1, "One", 300, "https://example.com/a.mp3")))
            store.toggleFavorite(first.id); store.updatePlaybackProgress(first.id, PlaybackProgress(0, 5000, 8000))
            store.saveMoment(LibraryMoment("moment", first.id, 0, 4000, "Keep"))
            service.promote(first.id, first.tracks.map { it.copy(storedName = "0000.mp3") }, 512)
            val promoted = store.books().single()
            assertEquals(first.id, promoted.id); assertTrue(promoted.isFavorite); assertTrue(promoted.isDownloaded)
            assertEquals(5000L, promoted.currentPositionMs); assertEquals(8000L, promoted.highWaterMarkMs)
            assertEquals(512L, promoted.storageBytes); assertEquals("Keep", store.moments(first.id).single().label)
        }
    }
    @Test fun invalidTrackUrlsAndEmptyTracksCannotCreatePartialRows() {
        SQLiteLibraryStore(context).withDatabase { store ->
            val service = CatalogLibraryService(store)
            for (tracks in listOf(emptyList(), listOf(CatalogTrack(1, "One", 300, "http://example.com/a.mp3")))) {
                try { service.add(book("133"), tracks); fail() } catch (_: IllegalArgumentException) { }
            }
            assertTrue(store.books().isEmpty())
        }
    }
}

private inline fun <T : android.database.sqlite.SQLiteOpenHelper, R> T.withDatabase(block: (T) -> R): R {
    try { return block(this) } finally { close() }
}
