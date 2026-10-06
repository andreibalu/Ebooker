package dev.unpaged.android.library

import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class LocalLibraryRepositoryTest {
    @get:Rule val temporary = TemporaryFolder()
    private val root get() = File(temporary.root, "audiobooks")
    private val store = FakeStore()
    private val metadata = AudioMetadataReader { AudioMetadata(1234, album = " A book ", artist = " Author ") }
    private fun repository(reader: AudioMetadataReader = metadata) = LocalLibraryRepository(root, store, reader)
    private fun document(name: String, data: ByteArray = name.toByteArray()) = object : ImportDocument {
        override val displayName = name
        override fun open() = ByteArrayInputStream(data)
    }

    @Test fun naturalOrderingAndMetadataSurviveSave() {
        val repo = repository()
        repo.load()
        val pending = repo.prepare(listOf(document("10.mp3"), document("2.mp3"), document("1.mp3")))
        assertEquals(listOf("1.mp3", "2.mp3", "10.mp3"), pending.tracks.map { it.originalName })
        assertEquals("A book", pending.suggestedTitle)
        assertEquals("Author", pending.suggestedAuthor)
        assertTrue(repo.books().isEmpty())
        val saved = repo.save(pending, "  Chosen title ", " Editor ")
        assertEquals("Chosen title", saved.title)
        assertEquals(3702L, saved.durationMs)
        assertEquals("Editor", saved.author)
        assertEquals(saved, repo.load().single())
        assertTrue(saved.tracks.all { File(File(root, saved.id), it.storedName).isFile })
    }

    @Test fun failedCopyLeavesNeitherLibraryRowNorPartialFiles() {
        val broken = object : ImportDocument {
            override val displayName = "2.mp3"
            override fun open(): InputStream = throw IOException("provider gone")
        }
        val repo = repository()
        assertThrows(IOException::class.java) { repo.prepare(listOf(document("1.mp3"), broken)) }
        assertTrue(store.books().isEmpty())
        assertTrue(File(root, ".staging").listFiles()!!.isEmpty())
    }

    @Test fun cancellationDuringCopyCleansStaging() {
        val repo = repository()
        var checks = 0
        assertThrows(CancellationException::class.java) {
            repo.prepare(listOf(document("1.mp3", ByteArray(200_000))), checkCancelled = {
                if (++checks == 3) throw CancellationException()
            })
        }
        assertTrue(File(root, ".staging").listFiles()!!.isEmpty())
    }

    @Test fun invalidAudioAfterFirstTrackRollsBackWholeSelection() {
        val repo = repository(AudioMetadataReader { file ->
            AudioMetadata(if (file.name.startsWith("0001")) 0 else 1000)
        })
        assertThrows(ImportProblem::class.java) { repo.prepare(listOf(document("1.mp3"), document("2.mp3"))) }
        assertTrue(store.books().isEmpty())
        assertTrue(File(root, ".staging").listFiles()!!.isEmpty())
    }

    @Test fun duplicateDetectionPreservesRepeatedTrackMultiplicity() {
        val repo = repository()
        val a = document("a.mp3", byteArrayOf(1))
        val b = document("b.mp3", byteArrayOf(2))
        repo.save(repo.prepare(listOf(a, a, b)), "First", "")
        val different = repo.prepare(listOf(a, b, b))
        repo.save(different, "Different", "")
        val error = assertThrows(ImportProblem::class.java) { repo.prepare(listOf(b, a, a)) }
        assertEquals(ImportProblem.Reason.DUPLICATE, error.reason)
        assertEquals(2, store.books().size)
        assertTrue(File(root, ".staging").listFiles()!!.isEmpty())
    }

    @Test fun failedDatabaseCommitKeepsPreviewRetryable() {
        val repo = repository()
        val pending = repo.prepare(listOf(document("1.mp3")))
        store.failInsert = true
        assertThrows(IOException::class.java) { repo.save(pending, "Title", "") }
        assertFalse(File(root, pending.id).exists())
        assertTrue(File(File(root, ".staging"), pending.id).isDirectory)
        store.failInsert = false
        assertEquals("Title", repo.save(pending, "Title", "").title)
    }

    @Test fun removalTouchesOwnedCopiesAndPreservesSource() {
        val source = temporary.newFile("source.mp3").apply { writeBytes(byteArrayOf(1, 2)) }
        val doc = object : ImportDocument {
            override val displayName = source.name
            override fun open() = source.inputStream()
        }
        val repo = repository()
        val book = repo.save(repo.prepare(listOf(doc)), "Title", "")
        repo.remove(book)
        assertTrue(repo.books().isEmpty())
        assertFalse(File(root, book.id).exists())
        assertArrayEquals(byteArrayOf(1, 2), source.readBytes())
    }

    @Test fun failedIndexRemovalNeverDeletesAudio() {
        val repo = repository()
        val book = repo.save(repo.prepare(listOf(document("1.mp3"))), "Title", "")
        store.failDelete = true
        assertThrows(IOException::class.java) { repo.remove(book) }
        assertTrue(File(root, book.id).isDirectory)
        assertEquals(book, store.books().single())
    }

    @Test fun startupRecoversAbandonedPreparationPromotionAndRemoval() {
        val repo = repository()
        val book = repo.save(repo.prepare(listOf(document("1.mp3"))), "Keep", "")
        val abandoned = repo.prepare(listOf(document("2.mp3")))
        val unreferenced = File(root, UUID.randomUUID().toString()).apply { mkdir(); resolve("audio").writeText("orphan") }
        val unrelated = File(root, "unrelated").apply { mkdir(); resolve("keep").writeText("keep") }
        assertEquals(listOf(book), repo.load())
        assertFalse(File(File(root, ".staging"), abandoned.id).exists())
        assertFalse(unreferenced.exists())
        assertTrue(File(root, book.id).isDirectory)
        assertTrue(unrelated.isDirectory)
    }

    @Test fun failedIndexReadNeverRunsRecovery() {
        val repo = repository()
        repo.prepare(listOf(document("1.mp3")))
        val orphan = File(root, UUID.randomUUID().toString()).apply { mkdir() }
        store.failRead = true
        assertThrows(IOException::class.java) { repo.load() }
        assertTrue(orphan.exists())
        assertEquals(1, File(root, ".staging").listFiles()!!.size)
    }

    @Test fun providerNameCannotEscapeOwnedDirectory() {
        val repo = repository()
        val pending = repo.prepare(listOf(document("../../outside.mp3")))
        assertEquals("0000.mp3", pending.tracks.single().storedName)
        assertFalse(File(temporary.root, "outside.mp3").exists())
        val saved = repo.save(pending, "Safe", "")
        assertTrue(File(File(root, saved.id), "0000.mp3").isFile)
        assertThrows(IllegalArgumentException::class.java) { repo.discard(pending.copy(id = "../outside")) }
    }

    @Test fun emptyTitleDoesNotPromoteFiles() {
        val repo = repository()
        val pending = repo.prepare(listOf(document("1.mp3")))
        assertThrows(ImportProblem::class.java) { repo.save(pending, "  ", "") }
        assertTrue(File(File(root, ".staging"), pending.id).isDirectory)
        assertTrue(store.books().isEmpty())
        repo.discard(pending)
        assertTrue(File(root, ".staging").listFiles()!!.isEmpty())
    }

    @Test fun fingerprintMatchesIndependentLittleEndianFixtureAndIgnoresMiddleOfLargeFile() {
        val short = temporary.newFile().apply { writeBytes(byteArrayOf(1, 2, 3)) }
        val expected = MessageDigest.getInstance("SHA-256").apply {
            update(byteArrayOf(1, 2, 3))
            update(ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN).putLong(3).putLong(1234).array())
        }.digest().joinToString("") { "%02x".format(it) }
        assertEquals(expected, TrackIdentity.fingerprint(short, 1234))
        val a = temporary.newFile().apply { writeBytes(ByteArray(3 * 1024 * 1024) { 7 }) }
        val b = temporary.newFile().apply { writeBytes(a.readBytes().apply { this[1024 * 1024 + 1] = 9 }) }
        assertEquals(TrackIdentity.fingerprint(a, 1234), TrackIdentity.fingerprint(b, 1234))
        assertNotEquals(TrackIdentity.fingerprint(a, 1234), TrackIdentity.fingerprint(b, 1235))
    }

    @Test fun naturalNumbersDoNotOverflowAndLeadingZeroTiesStayStable() {
        val names = listOf("Chapter 10.mp3", "Chapter 2.mp3", "Chapter 9999999999999999999999.mp3", "Chapter 1.mp3")
        assertEquals(listOf(names[3], names[1], names[0], names[2]), names.sortedWith(NaturalFilenameOrder))
        assertEquals(listOf("02.mp3", "2.mp3"), listOf("02.mp3", "2.mp3").sortedWith(NaturalFilenameOrder))
    }

    private class FakeStore : LibraryStore {
        val rows = mutableListOf<LibraryBook>()
        var failInsert = false
        var failDelete = false
        var failRead = false
        override fun toggleFavorite(id: String) { val i = rows.indexOfFirst { it.id == id }; rows[i] = rows[i].copy(isFavorite = !rows[i].isFavorite) }
        override fun updatePlaybackProgress(id: String, progress: PlaybackProgress) = Unit
        override fun moments(bookId: String): List<LibraryMoment> = emptyList()
        override fun saveMoment(moment: LibraryMoment) = Unit
        override fun deleteMoment(id: String) = Unit
        override fun books(): List<LibraryBook> {
            if (failRead) throw IOException()
            return rows.toList()
        }
        override fun insert(book: LibraryBook) {
            if (failInsert) throw IOException()
            rows += book
        }
        override fun delete(id: String) {
            if (failDelete) throw IOException()
            rows.removeAll { it.id == id }
        }
    }
}
