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
        withStore(context) { assertEquals(2, it.readableDatabase.version); assertEquals(2, it.books().single().tracks.size) }
        folder.deleteRecursively()
    }

    @Test fun favoriteProgressAndMomentCrudPersistAndCascadeWithoutRegressingHighWater() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("library.db")
        val book = LibraryBook("book", "Book", "Author", listOf(LibraryTrack("Stream", "", "", 60000, "", "https://example.com/audio")),
            isDownloaded = false, isFreeBook = true, catalogId = "42", equalizerJson = "{}", storageBytes = 123)
        val moment = LibraryMoment("moment", "book", 0, 10000, "First", categoriesJson = "[\"Plot\"]", quoteLine = "Quote", charactersJson = "[\"A\"]", mood = "Calm", createdAt = 100)
        withStore(context) { store ->
            val repository = LocalLibraryRepository(java.io.File(context.cacheDir, "library-api-test"), store, AudioMetadataReader { AudioMetadata(0) })
            store.insert(book); repository.toggleFavorite("book")
            repository.updatePlaybackProgress("book", PlaybackProgress(0, 30000, 30000, 1.5, playedAt = 200))
            repository.updatePlaybackProgress("book", PlaybackProgress(0, 10000, 10000, 1.5, finished = true, playedAt = 300))
            repository.saveMoment(moment)
            assertEquals(moment, repository.moments("book").single())
            store.saveMoment(moment.copy(label = "Edited", notes = "Notes"))
        }
        withStore(context) { store ->
            val repository = LocalLibraryRepository(java.io.File(context.cacheDir, "library-api-test"), store, AudioMetadataReader { AudioMetadata(0) })
            val loaded = repository.books().single()
            assertFalse(loaded.isDownloaded); assertTrue(loaded.isFreeBook); assertTrue(loaded.isFinished)
            assertEquals(123L, loaded.storageBytes)
            assertTrue(loaded.isFavorite); assertEquals(30000L, loaded.highWaterMarkMs)
            assertEquals(10000L, loaded.currentPositionMs); assertEquals(300L, loaded.lastPlayedAt)
            assertEquals(1.5, loaded.playbackSpeed, 0.0); assertEquals(book.tracks, loaded.tracks)
            assertEquals(1f / 6f, loaded.progress, .0001f)
            assertEquals(book.catalogId, loaded.catalogId); assertEquals(book.equalizerJson, loaded.equalizerJson)
            assertEquals("Edited", store.moments("book").single().label)
            repository.deleteMoment("moment"); assertTrue(store.moments("book").isEmpty())
            repository.saveMoment(moment); store.delete("book"); assertTrue(store.moments("book").isEmpty())
            assertThrows(android.database.sqlite.SQLiteException::class.java) { store.saveMoment(moment) }
        }
    }

}
