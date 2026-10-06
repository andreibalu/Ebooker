package dev.unpaged.android.moments

import dev.unpaged.android.library.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class MomentMetadataTest {
    private fun withStore(context: android.content.Context, block: (SQLiteLibraryStore) -> Unit) {
        val store = SQLiteLibraryStore(context)
        try { block(store) } finally { store.close() }
    }
    @Test fun filtersUnionWithinDimensionsIntersectAcrossDimensionsAndPinFirst() {
        val a = LibraryMoment("a", "book", 0, 0, "A", categoriesJson = "[\"action\",\"tension\"]", charactersJson = "[\"Alice\"]", mood = "tense", createdAt = 3)
        val b = a.copy(id = "b", isPinned = true, createdAt = 1, categoriesJson = "[\"dialogue\"]")
        val c = a.copy(id = "c", mood = "peaceful", createdAt = 4)
        assertEquals(listOf(b, c, a), MomentFilters().apply(listOf(a, b, c)))
        assertEquals(listOf(b, a), MomentFilters(setOf("action", "dialogue"), setOf("tense"), setOf("alice")).apply(listOf(a, b, c)))
        assertTrue(MomentFilters(moods = setOf("sad")).apply(listOf(a)).isEmpty())
    }
    @Test fun characterAdditionTrimsAndRejectsCaseInsensitiveDuplicates() {
        assertEquals(listOf("Alice"), addCharacter(emptyList(), " Alice \n"))
        assertEquals(listOf("Alice"), addCharacter(listOf("Alice"), "ALICE"))
        assertEquals(emptyList<String>(), addCharacter(emptyList(), "  "))
    }
    @Test fun v2UpgradePreservesMomentMetadataAudioAndEqualizerThenPersistsPin() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("library.db")
        val moment = LibraryMoment("moment", "book", 0, 1000, "Name", "Note", "[\"action\"]", "quote", "[\"Alice\"]", "tense", 12)
        withStore(context) { store ->
            store.insert(LibraryBook("book", "Book", "Author", listOf(LibraryTrack("Track", "source", "track.wav", 10000, "fingerprint")), equalizerJson = "saved"))
            store.saveMoment(moment)
            // Rebuild only the table in this test fixture to model the previous schema.
            store.writableDatabase.execSQL("ALTER TABLE moments RENAME TO moments_v3")
            store.writableDatabase.execSQL("""CREATE TABLE moments (id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                track_index INTEGER NOT NULL, time_ms INTEGER NOT NULL, label TEXT NOT NULL,
                notes TEXT NOT NULL, categories_json TEXT NOT NULL, quote_line TEXT,
                characters_json TEXT NOT NULL, mood TEXT, created_at INTEGER NOT NULL)""")
            store.writableDatabase.execSQL("INSERT INTO moments SELECT id,book_id,track_index,time_ms,label,notes,categories_json,quote_line,characters_json,mood,created_at FROM moments_v3")
            store.writableDatabase.execSQL("DROP TABLE moments_v3")
            store.writableDatabase.version = 2
        }
        withStore(context) { store ->
            assertEquals(moment, store.moments("book").single())
            assertEquals("track.wav", store.books().single().tracks.single().storedName)
            assertEquals("saved", store.books().single().equalizerJson)
            store.saveMoment(moment.copy(isPinned = true))
        }
        withStore(context) { assertTrue(it.moments("book").single().isPinned) }
    }
}
