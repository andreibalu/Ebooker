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

    @Test fun discoveredStreamingDurationUpdatesOnlyItsTrackAndSurvivesReopen() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("library.db")
        val track = LibraryTrack("Stream", "", "", 0, "", "https://example.com/audio")
        withStore(context) { store ->
            store.insert(LibraryBook("stream", "Book", "Author", listOf(track, track), isDownloaded = false))
            store.updateTrackDuration("stream", 1, 300000)
        }
        withStore(context) { store ->
            assertEquals(listOf(0L, 300000L), store.books().single().tracks.map { it.durationMs })
            assertEquals("https://example.com/audio", store.books().single().tracks[1].remoteUrl)
        }
    }

    @Test fun explicitProgressMarkCanMoveBackwardAndSurvivesReopen() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("library.db")
        withStore(context) { store ->
            store.insert(LibraryBook("book", "Book", "Author", listOf(LibraryTrack("Track", "1", "1", 300000, "a"))))
            store.updatePlaybackProgress("book", PlaybackProgress(0, 120000, 120000))
            store.setProgressMarker("book", 30000)
            store.updatePlaybackProgress("book", PlaybackProgress(0, 30000, 30000))
        }
        withStore(context) { store ->
            assertEquals(30000L, store.books().single().highWaterMarkMs)
            assertEquals(30000L, store.books().single().currentPositionMs)
            store.updatePlaybackProgress("book", PlaybackProgress(0, 20000, 20000))
            assertEquals(30000L, store.books().single().highWaterMarkMs)
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
    @Test fun v1MigrationPreservesBooksTracksAndDefaultsAcrossReopen() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("library.db")
        val id = "00000000-0000-0000-0000-000000000123"
        val folder = java.io.File(context.filesDir, "audiobooks/$id").apply { mkdirs() }
        val audio = java.io.File(folder, "0000.wav").apply { writeBytes(byteArrayOf(1, 2, 3, 4, 5, 6, 7)) }
        context.openOrCreateDatabase("library.db", 0, null).use { db ->
            db.execSQL("CREATE TABLE books (id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL)")
            db.execSQL("""CREATE TABLE tracks (book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                position INTEGER NOT NULL, title TEXT NOT NULL, original_name TEXT NOT NULL, stored_name TEXT NOT NULL,
                duration_ms INTEGER NOT NULL, fingerprint TEXT NOT NULL, PRIMARY KEY(book_id, position))""")
            db.execSQL("INSERT INTO books VALUES ('$id', 'Old Book', 'Author')")
            db.execSQL("INSERT INTO tracks VALUES ('$id', 1, 'Second', '2.wav', '0001.wav', 2000, 'b')")
            db.execSQL("INSERT INTO tracks VALUES ('$id', 0, 'First', '1.wav', '0000.wav', 1000, 'a')")
            db.version = 1
        }
        withStore(context) { store ->
            val book = store.books().single()
            assertEquals("Old Book", book.title)
            assertEquals(listOf("First", "Second"), book.tracks.map { it.title })
            assertFalse(book.isFavorite); assertTrue(book.isDownloaded)
            assertNull(book.lastPlayedAt); assertNull(book.catalogId); assertNull(book.equalizerJson)
            assertEquals(0, book.currentTrackIndex); assertEquals(0L, book.currentPositionMs)
            assertEquals(0L, book.highWaterMarkMs); assertEquals(1.0, book.playbackSpeed, 0.0)
            assertFalse(book.isFinished); assertFalse(book.isFreeBook); assertEquals(7L, book.storageBytes)
            assertTrue(audio.isFile)
            assertTrue(book.dateAdded > 0); assertNull(book.tracks.first().remoteUrl)
            assertTrue(store.moments(id).isEmpty())
        }
        withStore(context) { assertEquals(5, it.readableDatabase.version); assertEquals(2, it.books().single().tracks.size) }
        folder.deleteRecursively()
    }

}
