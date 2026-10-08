package dev.unpaged.android.library

import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.UUID

/** All calls are serialized on the ViewModel's IO worker; never use on the UI thread. */
class LocalLibraryRepository(
    private val root: File,
    private val store: LibraryStore,
    private val metadataReader: AudioMetadataReader,
) {
    private val staging = File(root, ".staging")

    fun load(): List<LibraryBook> {
        val books = store.books() // Fail closed: never clean files if the index cannot be read.
        ensureRoot()
        staging.listFiles()?.forEach { it.deleteRecursively() }
        File(root, ".removed").deleteRecursively() // Retired "Remove from App" copies were unreachable.
        val referenced = books.map { it.id }.toSet()
        root.listFiles()?.filter { it.isDirectory && isUUID(it.name) && it.name !in referenced }
            ?.forEach { it.deleteRecursively() }
        for (book in books.filter { it.isDownloaded && it.absItemID == null }) {
            val folder = ownedFolder(root, book.id)
            val hasAudio = book.tracks.any { it.storedName.isNotEmpty() && File(folder, it.storedName).isFile }
            if (!hasAudio) store.setAvailability(book.id, false)
            else book.tracks.forEachIndexed { index, track ->
                if (!track.fingerprint.matches(Regex("[a-f0-9]{64}")) && track.storedName.isNotEmpty()) {
                    val file = File(folder, track.storedName)
                    if (file.isFile) runCatching { TrackIdentity.fingerprint(file, track.durationMs) }.getOrNull()?.let { store.setFingerprint(book.id, index, it) }
                }
            }
        }
        return store.books()
    }

    fun books(): List<LibraryBook> = store.books()
    fun toggleFavorite(id: String) = store.toggleFavorite(id)
    fun updatePlaybackProgress(id: String, progress: PlaybackProgress) = store.updatePlaybackProgress(id, progress)
    fun moments(bookId: String): List<LibraryMoment> = store.moments(bookId)
    fun saveMoment(moment: LibraryMoment) = store.saveMoment(moment)
    fun deleteMoment(id: String) = store.deleteMoment(id)

    fun prepare(documents: List<ImportDocument>, checkCancelled: () -> Unit = {},
                progress: (Int, Int) -> Unit = { _, _ -> }, allowDuplicate: Boolean = false): PendingImport {
        if (documents.isEmpty()) throw ImportProblem(ImportProblem.Reason.EMPTY)
        ensureRoot()
        val id = UUID.randomUUID().toString()
        val folder = File(staging, id)
        if (!folder.mkdir()) throw ImportProblem(ImportProblem.Reason.STORAGE)
        try {
            val sorted = documents.sortedWith { a, b -> NaturalFilenameOrder.compare(a.displayName, b.displayName) }
            val metadata = mutableListOf<AudioMetadata>()
            val tracks = sorted.mapIndexed { index, document ->
                checkCancelled()
                val extension = document.displayName.substringAfterLast('.', "").lowercase(Locale.ROOT)
                if (extension !in setOf("mp3", "m4a", "m4b", "aac", "wav", "ogg", "opus", "flac"))
                    throw ImportProblem(ImportProblem.Reason.INVALID_AUDIO)
                // Provider display names are never used as paths.
                val storedName = "%04d.%s".format(Locale.ROOT, index, extension)
                val file = File(folder, storedName)
                document.open().use { input ->
                    FileOutputStream(file).use { output ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            checkCancelled()
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                        }
                        output.fd.sync()
                    }
                }
                checkCancelled()
                val info = metadataReader.read(file)
                if (info.durationMs <= 0) throw ImportProblem(ImportProblem.Reason.INVALID_AUDIO)
                dev.unpaged.android.playback.Mp4Chapters.cached(file)
                metadata += info
                val track = LibraryTrack(info.title.clean() ?: document.displayName.substringBeforeLast('.'),
                    document.displayName, storedName, info.durationMs, TrackIdentity.fingerprint(file, info.durationMs))
                checkCancelled()
                progress(index + 1, sorted.size)
                track
            }
            if (!allowDuplicate && store.books().any { !it.isAudioMissing && TrackIdentity.matches(tracks, it.tracks) })
                throw ImportProblem(ImportProblem.Reason.DUPLICATE)
            val albums = metadata.mapNotNull { it.album.clean() }.distinct()
            val title = albums.singleOrNull() ?: if (tracks.size == 1) tracks.first().title
                else sorted.first().displayName.substringBeforeLast('.')
            return PendingImport(id, title, metadata.firstNotNullOfOrNull { it.artist.clean() } ?: "", tracks)
        } catch (error: Throwable) {
            folder.deleteRecursively()
            throw error
        }
    }

    fun save(pending: PendingImport, title: String, author: String): LibraryBook {
        if (title.isBlank()) throw ImportProblem(ImportProblem.Reason.TITLE)
        if (store.books().any { !it.isAudioMissing && TrackIdentity.matches(pending.tracks, it.tracks) })
            throw ImportProblem(ImportProblem.Reason.DUPLICATE)
        val source = ownedFolder(staging, pending.id)
        val destination = ownedFolder(root, pending.id)
        if (!source.isDirectory || destination.exists() || !source.renameTo(destination))
            throw ImportProblem(ImportProblem.Reason.STORAGE)
        val book = LibraryBook(pending.id, title.trim(), author.trim(), pending.tracks,
            storageBytes = destination.walkTopDown().filter { it.isFile }.sumOf { it.length() })
        try { store.insert(book) } catch (error: Throwable) {
            // Keep the preview retryable after an index failure; startup cleans abandoned copies.
            if (!destination.renameTo(source)) destination.deleteRecursively()
            throw error
        }
        return book
    }

    fun discard(pending: PendingImport) { ownedFolder(staging, pending.id).deleteRecursively() }

    fun findRestoreMatch(pending: PendingImport): LibraryBook? {
        val identities = pending.tracks.map { it.fingerprint }.filter { it.isNotBlank() }.toSet()
        return store.books().filter { it.isAudioMissing }.map { book ->
            book to book.tracks.map { it.fingerprint }.filter { it.isNotBlank() }.toSet().intersect(identities).size
        }.filter { it.second > 0 }.maxByOrNull { it.second }?.first
    }

    fun adopt(pending: PendingImport, orphan: LibraryBook, allowMismatch: Boolean = false) {
        check(store.books().any { it.id == orphan.id && it.isAudioMissing })
        val exact = TrackIdentity.matches(pending.tracks, orphan.tracks)
        require(exact || allowMismatch) { "Track mismatch requires explicit adoption." }
        val tracks = if (exact) TrackIdentity.orderedLike(pending.tracks, orphan.tracks) else pending.tracks
        val source = ownedFolder(staging, pending.id)
        val destination = ownedFolder(root, orphan.id)
        // Remove from This Phone keeps the cover. As on iOS, it wins over the import's embedded art.
        val previous = ownedFolder(staging, orphan.id)
        previous.deleteRecursively() // A killed earlier run can leave a swap folder that blocks renameTo.
        if (destination.exists() && !destination.renameTo(previous)) throw ImportProblem(ImportProblem.Reason.STORAGE)
        if (!source.renameTo(destination)) {
            previous.renameTo(destination)
            throw ImportProblem(ImportProblem.Reason.STORAGE)
        }
        try {
            store.promoteDownload(orphan.id, tracks, destination.walkTopDown().filter { it.isFile }.sumOf { it.length() })
        } catch (error: Throwable) {
            destination.renameTo(source)
            previous.renameTo(destination)
            throw error
        }
        File(previous, "cover.png").takeIf { it.isFile }?.let { kept ->
            val cover = File(destination, "cover.png")
            if (!cover.exists() || cover.delete()) kept.renameTo(cover)
        }
        previous.deleteRecursively()
    }

    fun removeFromPhone(book: LibraryBook) {
        store.setAvailability(book.id, false, book.isFreeBook)
        // Keep the cover so Backed-up Library and a later restore still show it.
        val folder = ownedFolder(root, book.id)
        folder.listFiles()?.filter { it.name != "cover.png" }?.forEach { it.deleteRecursively() }
        folder.delete() // Only succeeds when no cover was kept.
    }

    fun restoreFree(book: LibraryBook) {
        require(book.isFreeBook && book.tracks.any { it.remoteUrl != null })
        store.setAvailability(book.id, false, false)
    }

    fun remove(book: LibraryBook) {
        // Commit index removal first. A crash or failed cleanup leaves an unreferenced owned
        // directory, recovered on the next load, never a visible row pointing at deleted audio.
        // App-owned audio is always a private copy; provider originals are never modified.
        store.delete(book.id)
        ownedFolder(root, book.id).deleteRecursively()
    }

    private fun ensureRoot() {
        if ((!root.isDirectory && !root.mkdirs()) || (!staging.isDirectory && !staging.mkdir()))
            throw ImportProblem(ImportProblem.Reason.STORAGE)
    }

    private fun ownedFolder(parent: File, id: String): File {
        require(isUUID(id))
        return File(parent, id)
    }

    private fun isUUID(value: String): Boolean = try { UUID.fromString(value).toString() == value }
        catch (_: IllegalArgumentException) { false }

    private fun String?.clean(): String? = this?.trim()?.takeIf { it.isNotEmpty() }
}
