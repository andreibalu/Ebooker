package dev.unpaged.android.activity

import dev.unpaged.android.library.*
import dev.unpaged.android.UnpagedPreferences
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.time.LocalDate

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class ReadingMigrationTest {
    private fun withStore(context: android.content.Context, block: (SQLiteLibraryStore) -> Unit) {
        val store = SQLiteLibraryStore(context)
        try { block(store) } finally { store.close() }
    }
    @Test fun upgradeV2PreservesPlaybackMomentsAudioAndActivitySurvivesBookDeletion() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("library.db")
        val book = LibraryBook("existing", "Existing", "Author", listOf(LibraryTrack("Track", "1", "1.wav", 300000, "fingerprint")), isFavorite = true, currentPositionMs = 120000)
        val folder = java.io.File(context.filesDir, "audiobooks/existing").apply { mkdirs() }
        val audio = java.io.File(folder, "1.wav").apply { writeText("owned file") }
        val moment = LibraryMoment("moment", book.id, 0, 1000, "Saved")
        withStore(context) { store ->
            store.insert(book); store.saveMoment(moment)
            store.writableDatabase.execSQL("DROP TABLE reading_sessions")
            // Model the v2 moments table (no is_pinned); this SQLite predates DROP COLUMN.
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
        val session = ReadingSession(day = LocalDate.of(2026, 10, 6), hour = 23, minutes = 5, bookId = book.id, bookTitle = book.title, bookAuthor = book.author, isFreeBook = false)
        withStore(context) { store ->
            assertEquals(3, store.readableDatabase.version)
            assertEquals(book, store.books().single()); assertEquals(moment, store.moments(book.id).single()); assertTrue(audio.exists())
            store.saveReadingSession(session); store.delete(book.id)
        }
        withStore(context) { store -> assertEquals(session, store.readingSessions().single()); assertTrue(store.books().isEmpty()) }
        folder.deleteRecursively()
    }
    @Test fun onboardingGateAndChoicesSurviveNewWrapperAndReset() {
        val context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("unpaged", 0).edit().clear().commit()
        val prefs = UnpagedPreferences(context)
        assertFalse(prefs.onboardingComplete())
        prefs.setShelvesFirst(true); prefs.setSeconds("skipForwardSeconds", 45); prefs.setOnboardingComplete(true)
        val reopened = UnpagedPreferences(context)
        assertTrue(reopened.onboardingComplete()); assertTrue(reopened.shelvesFirst()); assertEquals(45, reopened.seconds("skipForwardSeconds", 30))
        reopened.setOnboardingComplete(false)
        assertFalse(UnpagedPreferences(context).onboardingComplete()); assertTrue(reopened.shelvesFirst())
    }
}
