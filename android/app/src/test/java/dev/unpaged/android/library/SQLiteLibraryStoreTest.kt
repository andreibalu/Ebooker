package dev.unpaged.android.library

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class SQLiteLibraryStoreTest {
    private fun withStore(context: android.content.Context, block: (SQLiteLibraryStore) -> Unit) {
        val store = SQLiteLibraryStore(context)
        try { block(store) } finally { store.close() }
    }

    @Test fun booksAndTrackOrderPersistAcrossReopenAndDeleteCascades() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("library.db")
        val id = UUID.randomUUID().toString()
        val tracks = listOf(LibraryTrack("First", "1.mp3", "0000.mp3", 1500, "a"),
            LibraryTrack("Second", "2.mp3", "0001.mp3", 2500, "b"))
        val book = LibraryBook(id, "Title", "Author", tracks)
        withStore(context) { it.insert(book) }
        withStore(context) { store ->
            assertEquals(book, store.books().single())
            store.delete(id)
            assertTrue(store.books().isEmpty())
            store.readableDatabase.rawQuery("SELECT COUNT(*) FROM tracks", null).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(0, cursor.getInt(0))
            }
        }
    }

    @Test fun failedTrackInsertRollsBackBookAndEarlierTracks() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("library.db")
        withStore(context) { store ->
            store.writableDatabase.execSQL("""CREATE TRIGGER reject_second BEFORE INSERT ON tracks
                WHEN NEW.position = 1 BEGIN SELECT RAISE(ABORT, 'injected failure'); END""")
            val track = LibraryTrack("Track", "1.mp3", "0000.mp3", 1000, "a")
            assertThrows(android.database.sqlite.SQLiteException::class.java) {
                store.insert(LibraryBook(UUID.randomUUID().toString(), "Title", "", listOf(track, track)))
            }
            assertTrue(store.books().isEmpty())
            store.readableDatabase.rawQuery("SELECT COUNT(*) FROM tracks", null).use { cursor ->
                cursor.moveToFirst()
                assertEquals(0, cursor.getInt(0))
            }
        }
    }
}
