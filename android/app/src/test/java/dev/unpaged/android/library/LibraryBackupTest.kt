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
import dev.unpaged.android.backup.BackupBucket
import dev.unpaged.android.shelves.CatalogLibraryService
import dev.unpaged.android.UnpagedPreferences

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

    @Test fun missingFilesBackfillMatchingAndAdoptionPreserveIdentityAndMetadata() {
        fresh().withStore { db ->
            val root = File(context.cacheDir, UUID.randomUUID().toString())
            val repo = LocalLibraryRepository(root, db, AudioMetadataReader { AudioMetadata(60000) })
            val book = repo.save(repo.prepare(listOf(doc())), "Original", "Author")
            db.toggleFavorite(book.id); db.updateEqualizer(book.id, "eq")
            db.updatePlaybackProgress(book.id, PlaybackProgress(0, 20000, 25000, 1.5))
            db.saveMoment(LibraryMoment("moment", book.id, 0, 1234, "Remember"))
            db.saveReadingSession(ReadingSession("session", LocalDate.of(2026, 10, 7), 10, 5, book.id, "Original", "Author", false, 100))
            db.setFingerprint(book.id, 0, "")
            assertTrue(repo.load().single().tracks.single().fingerprint.matches(Regex("[a-f0-9]{64}")))
            val fingerprint = db.books().single().tracks.single().fingerprint
            File(root, book.id).deleteRecursively()
            val orphan = repo.load().single()
            assertTrue(orphan.isAudioMissing); assertFalse(orphan.isStreamingOnly)
            assertEquals(BackupBucket.MISSING, BackupBucket.of(orphan))
            assertNull(repo.findRestoreMatch(repo.prepare(listOf(doc(byteArrayOf(9))))).also { /* different bytes */ })
            val pending = repo.prepare(listOf(doc(), doc()))
            assertEquals(book.id, repo.findRestoreMatch(pending)?.id)
            assertFalse(TrackIdentity.matches(pending.tracks, orphan.tracks)) // multiplicity matters for Locate
            repo.discard(pending)
            val exact = repo.prepare(listOf(doc()))
            repo.adopt(exact, orphan)
            val restored = repo.load().single()
            assertEquals(book.id, restored.id); assertTrue(restored.isDownloaded)
            assertEquals("Original", restored.title); assertEquals(fingerprint, restored.tracks.single().fingerprint)
            assertTrue(restored.isFavorite); assertEquals("eq", restored.equalizerJson)
            assertEquals(20000L, restored.currentPositionMs); assertEquals(25000L, restored.highWaterMarkMs)
            assertEquals(1.5, restored.playbackSpeed, 0.0)
            assertEquals("Remember", db.moments(book.id).single().label)
            assertEquals(book.id, db.readingSessions().single().bookId)
            root.deleteRecursively()
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

    @Test fun completedDownloadCannotReviveRemovedStreamingBook() {
        fresh().withStore { db ->
            val root = File(context.cacheDir, UUID.randomUUID().toString())
            val repo = LocalLibraryRepository(root, db, AudioMetadataReader { AudioMetadata(1000) })
            val stream = LibraryTrack("Track", "1.mp3", "", 1000, "free", "https://example.com/1.mp3")
            val free = LibraryBook(id, "Free", "Author", listOf(stream), isFreeBook = true,
                catalogId = "42", isDownloaded = false)
            db.insert(free)
            db.saveMoment(LibraryMoment("moment", id, 0, 1, "Remember"))
            repo.removeFromPhone(free)
            val removed = db.books().single()
            assertThrows(IllegalStateException::class.java) {
                db.promoteDownload(id, listOf(stream.copy(storedName = "0000.mp3")), 123)
            }
            assertEquals(removed, db.books().single())
            assertEquals("Remember", db.moments(id).single().label)
            // Explicit restoration makes a later requested download eligible again.
            repo.restoreFree(removed)
            db.promoteDownload(id, listOf(stream.copy(storedName = "0000.mp3")), 123)
            assertTrue(db.books().single().isDownloaded)
            assertFalse(db.books().single().isArchived)
            root.deleteRecursively()
        }
    }

    @Test fun archivedFreeRowStreamsInPlaceAndAbsNeverBecomesAnOrphan() {
        fresh().withStore { db ->
            val root = File(context.cacheDir, UUID.randomUUID().toString())
            val repo = LocalLibraryRepository(root, db, AudioMetadataReader { AudioMetadata(1000) })
            val free = LibraryBook(id, "Free", "Author", listOf(LibraryTrack("Track", "1.mp3", "", 1000, "free", "https://example.com/1.mp3")), isFreeBook = true, catalogId = "42", isDownloaded = false)
            db.insert(free); db.saveMoment(LibraryMoment("moment", id, 0, 1, "Remember"))
            repo.removeFromPhone(free)
            assertEquals(BackupBucket.REMOVED, BackupBucket.of(db.books().single()))
            assertNull(CatalogLibraryService(db).identity("42"))
            val added = CatalogLibraryService(db).add(dev.unpaged.android.shelves.CatalogBook("42", "New title", "New author", "", "English", 1), emptyList())
            assertEquals(id, added.id); assertEquals("Free", added.title); assertFalse(added.isArchived)
            assertEquals(1, db.books().size)
            repo.removeFromPhone(added)
            repo.restoreFree(db.books().single())
            assertEquals(id, db.books().single().id)
            assertEquals(BackupBucket.STREAMING, BackupBucket.of(db.books().single()))
            assertEquals("Remember", db.moments(id).single().label)
            val abs = free.copy(id = UUID.randomUUID().toString(), isFreeBook = false, absItemID = "abs")
            db.insert(abs)
            assertTrue(repo.load().first { it.absItemID != null }.isStreamingOnly)
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

    @Test fun snapshotIsConsistentAndRestoresIntoLivePath() {
        val live = fresh().also { it.insert(LibraryBook(id, "Snap", "Author", emptyList())) }
        try {
            val snapshot = context.getDatabasePath(dev.unpaged.android.backup.LibrarySnapshot.NAME)
            dev.unpaged.android.backup.LibrarySnapshot.create(context.getDatabasePath("library.db"), snapshot)
            live.close(); context.deleteDatabase("library.db")
            dev.unpaged.android.backup.LibrarySnapshot.install(snapshot, context.getDatabasePath("library.db"))
            assertFalse(snapshot.exists())
            SQLiteLibraryStore(context).withStore { restored ->
                assertEquals(5, restored.readableDatabase.version)
                assertEquals("Snap", restored.books().single().title)
            }
        } finally { live.close() }
    }

    @Test fun olderBuildOpensNewerDatabaseWithoutCrashing() {
        fresh().withStore { it.insert(LibraryBook(id, "Newer", "Author", emptyList())) }
        context.openOrCreateDatabase("library.db", 0, null).use { it.version = 9 }
        SQLiteLibraryStore(context).withStore { assertEquals("Newer", it.books().single().title) }
    }

    @Test fun backupDefaultsOnAndToggleSurvivesNewPreferenceOwner() {
        context.getSharedPreferences("unpaged", 0).edit().clear().commit()
        assertTrue(UnpagedPreferences(context).backupEnabled())
        UnpagedPreferences(context).setBackupEnabled(false)
        assertFalse(UnpagedPreferences(context).backupEnabled())
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
