package dev.unpaged.android.library

import android.content.Context
import java.io.ByteArrayInputStream
import java.io.File
import java.time.LocalDate
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import dev.unpaged.android.activity.ReadingSession

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class LibraryBackupTest {
    private fun <T> SQLiteLibraryStore.withStore(block: (SQLiteLibraryStore) -> T): T = try { block(this) } finally { close() }
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private fun fresh(): SQLiteLibraryStore { context.deleteDatabase("library.db"); return SQLiteLibraryStore(context) }
    private val id = "00000000-0000-0000-0000-000000000123"
    private fun doc(bytes: ByteArray = byteArrayOf(1, 2, 3)) = object : ImportDocument {
        override val displayName = "track.wav"
        override fun open() = ByteArrayInputStream(bytes)
    }

    @Test fun v4ToV5RetainsEveryMetadataTableAndFingerprint() {
        val schemas = fresh().withStore { store ->
            store.readableDatabase.rawQuery("SELECT sql FROM sqlite_master WHERE type IN ('table','index') AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'", null).use { r ->
                buildList { while (r.moveToNext()) add(r.getString(0).replace(", is_archived INTEGER NOT NULL DEFAULT 0", "")) }
            }
        }
        context.deleteDatabase("library.db")
        context.openOrCreateDatabase("library.db", 0, null).use { db ->
            schemas.forEach { db.execSQL(it) }
            db.execSQL("INSERT INTO books(id,title,author,is_favorite,current_position_ms,equalizer_json) VALUES('$id','Book','Author',1,12345,'eq')")
            db.execSQL("INSERT INTO tracks(book_id,position,title,original_name,stored_name,duration_ms,fingerprint) VALUES('$id',0,'Track','track.wav','0000.wav',60000,'identity')")
            db.execSQL("INSERT INTO moments(id,book_id,track_index,time_ms,label,notes,categories_json,characters_json,created_at,is_pinned) VALUES('moment','$id',0,1234,'Moment','','[]','[]',1,1)")
            db.execSQL("INSERT INTO reading_sessions VALUES('session','2026-10-07',10,5,'$id','Book','Author',0,100)")
            db.version = 4
        }
        SQLiteLibraryStore(context).withStore { db ->
            val book = db.books().single()
            assertEquals(5, db.readableDatabase.version)
            assertEquals("identity", book.tracks.single().fingerprint)
            assertTrue(book.isFavorite); assertFalse(book.isArchived)
            assertEquals(12345L, book.currentPositionMs); assertEquals("eq", book.equalizerJson)
            assertTrue(db.moments(id).single().isPinned); assertEquals(5, db.readingSessions().single().minutes)
        }
    }

    @Test fun removeFromPhoneKeepsTheCoverThroughAdoption() {
        fresh().withStore { db ->
            val root = File(context.cacheDir, UUID.randomUUID().toString())
            val repo = LocalLibraryRepository(root, db, AudioMetadataReader { AudioMetadata(1000) })
            val book = repo.save(repo.prepare(listOf(doc())), "Book", "Author")
            File(root, "${book.id}/cover.png").writeText("custom")
            repo.removeFromPhone(book)
            assertEquals(listOf("cover.png"), File(root, book.id).list()?.toList())
            val orphan = repo.load().single()
            assertTrue(orphan.isAudioMissing)
            val pending = repo.prepare(listOf(doc()))
            File(root, ".staging/${pending.id}/cover.png").writeText("embedded")
            repo.adopt(pending, orphan)
            assertEquals("custom", File(root, "${book.id}/cover.png").readText())
            assertTrue(repo.load().single().isDownloaded)
            root.deleteRecursively()
        }
    }

    @Test fun failedAdoptionRollsBackTracksAndKeepsPendingRetryable() {
        fresh().withStore { db ->
            val root = File(context.cacheDir, UUID.randomUUID().toString())
            val repo = LocalLibraryRepository(root, db, AudioMetadataReader { AudioMetadata(1000) })
            val book = repo.save(repo.prepare(listOf(doc())), "Book", "Author")
            repo.removeFromPhone(book)
            val orphan = db.books().single()
            val pending = repo.prepare(listOf(doc()))
            db.writableDatabase.execSQL("CREATE TRIGGER reject_track BEFORE INSERT ON tracks BEGIN SELECT RAISE(ABORT, 'failure'); END")
            assertThrows(android.database.sqlite.SQLiteException::class.java) { repo.adopt(pending, orphan) }
            assertEquals(orphan, db.books().single())
            assertTrue(File(root, ".staging/${pending.id}").isDirectory)
            assertFalse(File(root, book.id).exists())
            root.deleteRecursively()
        }
    }

    @Test fun removeDeletesOwnedCopiesAndLoadSweepsLegacyRemovedFolder() {
        fresh().withStore { db ->
            val root = File(context.cacheDir, UUID.randomUUID().toString())
            val repo = LocalLibraryRepository(root, db, AudioMetadataReader { AudioMetadata(1000) })
            val book = repo.save(repo.prepare(listOf(doc())), "Gone", "Author")
            val legacy = File(root, ".removed/${UUID.randomUUID()}").apply { mkdirs(); File(this, "a.wav").writeBytes(byteArrayOf(1)) }
            repo.remove(book)
            assertFalse(File(root, book.id).exists())
            assertTrue(repo.load().isEmpty())
            assertFalse(legacy.exists()); assertFalse(File(root, ".removed").exists())
            root.deleteRecursively()
        }
    }

    @Test fun adoptSucceedsDespiteStaleSwapFolder() {
        fresh().withStore { db ->
            val root = File(context.cacheDir, UUID.randomUUID().toString())
            val repo = LocalLibraryRepository(root, db, AudioMetadataReader { AudioMetadata(1000) })
            val book = repo.save(repo.prepare(listOf(doc())), "Orphan", "Author")
            repo.removeFromPhone(book)
            val orphan = repo.load().single()
            File(root, ".staging/${orphan.id}").apply { mkdirs(); File(this, "stale").writeBytes(byteArrayOf(9)) }
            val pending = repo.prepare(listOf(doc()))
            repo.adopt(pending, orphan)
            assertTrue(File(root, "${orphan.id}/${repo.load().single().tracks.single().storedName}").isFile)
            root.deleteRecursively()
        }
    }

    @Test fun snapshotExhaustionThrowsWithLastFailureAndDeletesPartialFiles() {
        val folder = File(context.cacheDir, UUID.randomUUID().toString()).apply { mkdirs() }
        try {
            val live = File(folder, "library.db").apply { writeText("live") }
            val snapshot = File(folder, "snapshot.db")
            val failures = List(3) { java.io.IOException("No space on attempt ${it + 1}") }
            var attempts = 0
            val thrown = assertThrows(java.io.IOException::class.java) {
                dev.unpaged.android.backup.LibrarySnapshot.prepare(live, snapshot, createSnapshot = { _, target ->
                    target.writeText("partial")
                    File(target.path + "-journal").writeText("partial journal")
                    throw failures[attempts++]
                })
            }
            assertEquals(3, attempts); assertSame(failures.last(), thrown.cause)
            assertFalse(snapshot.exists()); assertFalse(File(snapshot.path + "-journal").exists())
            assertEquals("live", live.readText())
        } finally { folder.deleteRecursively() }
    }

    @Test fun snapshotRetriesThenSucceedsAndMissingLibraryClearsStaleSnapshot() {
        val folder = File(context.cacheDir, UUID.randomUUID().toString()).apply { mkdirs() }
        try {
            val live = File(folder, "library.db").apply { writeText("live") }
            val snapshot = File(folder, "snapshot.db")
            var attempts = 0
            dev.unpaged.android.backup.LibrarySnapshot.prepare(live, snapshot, createSnapshot = { _, target ->
                attempts++
                if (attempts < 3) throw java.io.IOException("Busy")
                target.writeText("complete")
            })
            assertEquals(3, attempts); assertEquals("complete", snapshot.readText())
            live.delete()
            dev.unpaged.android.backup.LibrarySnapshot.prepare(live, snapshot, createSnapshot = { _, _ -> fail("Missing library must not be opened") })
            assertFalse(snapshot.exists())
        } finally { folder.deleteRecursively() }
    }

    @Test fun renamedImportsRestoreOriginalOrderIncludingRepeatedFingerprintsAndReferences() {
        fresh().withStore { db ->
            val root = File(context.cacheDir, UUID.randomUUID().toString())
            try {
                val repo = LocalLibraryRepository(root, db, AudioMetadataReader { AudioMetadata(60000) })
                fun named(name: String, value: Byte) = object : ImportDocument {
                    override val displayName = name
                    override fun open() = ByteArrayInputStream(byteArrayOf(value))
                }
                val book = repo.save(repo.prepare(listOf(named("1-A.wav", 1), named("2-B.wav", 2), named("3-A.wav", 1))), "Book", "Author")
                db.updatePlaybackProgress(book.id, PlaybackProgress(1, 20000, 80000, 1.5))
                book.tracks.indices.forEach { db.saveMoment(LibraryMoment("moment-$it", book.id, it, 1234, "Moment $it")) }
                repo.removeFromPhone(book)
                val orphan = repo.load().single()
                val pending = repo.prepare(listOf(named("1-B.wav", 2), named("2-A.wav", 1), named("3-A.wav", 1)))
                assertTrue(TrackIdentity.matches(pending.tracks, orphan.tracks))
                repo.adopt(pending, orphan)
                val restored = repo.load().single()
                assertEquals(book.tracks.map { it.fingerprint }, restored.tracks.map { it.fingerprint })
                assertEquals(listOf("2-A.wav", "1-B.wav", "3-A.wav"), restored.tracks.map { it.originalName })
                assertEquals(3, restored.tracks.map { it.storedName }.distinct().size)
                assertEquals(1, restored.currentTrackIndex); assertEquals(20000L, restored.currentPositionMs)
                assertEquals(book.tracks[1].fingerprint, restored.tracks[restored.currentTrackIndex].fingerprint)
                db.moments(book.id).forEach { moment ->
                    assertEquals(book.tracks[moment.trackIndex].fingerprint, restored.tracks[moment.trackIndex].fingerprint)
                }
                restored.tracks.forEach { assertTrue(File(root, "${book.id}/${it.storedName}").isFile) }
            } finally { root.deleteRecursively() }
        }
    }

    @Test fun ordinaryImportOverlapRequiresMismatchConfirmationJustLikeLocate() {
        fresh().withStore { db ->
            val root = File(context.cacheDir, UUID.randomUUID().toString())
            try {
                val repo = LocalLibraryRepository(root, db, AudioMetadataReader { AudioMetadata(60000) })
                val book = repo.save(repo.prepare(listOf(doc(), doc(byteArrayOf(4)), doc(byteArrayOf(5)))), "Book", "Author")
                repo.removeFromPhone(book)
                val orphan = repo.load().single()
                val pending = repo.prepare(listOf(doc()))
                assertEquals(orphan.id, repo.findRestoreMatch(pending)?.id)
                val ordinary = LibraryUiState(pending = pending, restoreMatch = orphan)
                assertTrue(ordinary.restoreMismatch)
                assertTrue(ordinary.copy(locateTarget = orphan).restoreMismatch)
                assertThrows(IllegalArgumentException::class.java) { repo.adopt(pending, orphan) }
                assertEquals(orphan, db.books().single())
                assertTrue(File(root, ".staging/${pending.id}").isDirectory)
                repo.adopt(pending, orphan, allowMismatch = true)
                assertEquals(1, repo.load().single().tracks.size)
                val exact = repo.prepare(listOf(doc()), allowDuplicate = true)
                assertFalse(LibraryUiState(pending = exact, restoreMatch = db.books().single()).restoreMismatch)
                assertTrue(LibraryUiState(pending = exact, restoreMatch = orphan.copy(tracks = exact.tracks + exact.tracks)).restoreMismatch)
            } finally { root.deleteRecursively() }
        }
    }

    @Test fun olderBuildOpensNewerDatabaseWithoutCrashing() {
        fresh().withStore { it.insert(LibraryBook(id, "Newer", "Author", emptyList())) }
        context.openOrCreateDatabase("library.db", 0, null).use { it.version = 9 }
        SQLiteLibraryStore(context).withStore { assertEquals("Newer", it.books().single().title) }
    }

    @Test fun largeLibraryFitsAutoBackupQuotaWithoutAudioOrCovers() {
        fresh().withStore { db ->
            // 1,000 books, 20,000 tracks, 20,000 moments and 50,000 history rows.
            db.writableDatabase.beginTransaction()
            try {
                repeat(1000) { index ->
                    val key = "book-$index"
                    val track = LibraryTrack("Chapter title", "chapter.mp3", "0000.mp3", 3600000, "a".repeat(64))
                    db.insert(LibraryBook(key, "A representative audiobook title $index", "A representative author", List(20) { track }))
                    repeat(20) { m -> db.saveMoment(LibraryMoment("$key-$m", key, m, 12345, "A saved moment", notes = "A representative note about this chapter.", quoteLine = "A short sentence from the recording.")) }
                    repeat(50) { h -> db.saveReadingSession(ReadingSession("$key-session-$h", LocalDate.of(2026, 10, 7), h % 24, 5, key, "A representative audiobook title $index", "A representative author", false, 100)) }
                }
                db.writableDatabase.setTransactionSuccessful()
            } finally { db.writableDatabase.endTransaction() }
            db.writableDatabase.rawQuery("PRAGMA wal_checkpoint(FULL)", null).close()
        }
        val bytes = context.getDatabasePath("library.db").length()
        println("Backup size for 1000 books/20000 tracks/20000 moments/50000 sessions: $bytes bytes")
        assertTrue("Metadata size $bytes exceeds Auto Backup quota", bytes < 25 * 1024 * 1024)
    }
}
