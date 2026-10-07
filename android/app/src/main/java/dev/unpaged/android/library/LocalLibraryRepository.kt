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
        val referenced = books.map { it.id }.toSet()
        root.listFiles()?.filter { it.isDirectory && isUUID(it.name) && it.name !in referenced }
            ?.forEach { it.deleteRecursively() }
        return books
    }

    fun books(): List<LibraryBook> = store.books()
    fun toggleFavorite(id: String) = store.toggleFavorite(id)
    fun updatePlaybackProgress(id: String, progress: PlaybackProgress) = store.updatePlaybackProgress(id, progress)
    fun moments(bookId: String): List<LibraryMoment> = store.moments(bookId)
    fun saveMoment(moment: LibraryMoment) = store.saveMoment(moment)
    fun deleteMoment(id: String) = store.deleteMoment(id)

    fun prepare(documents: List<ImportDocument>, checkCancelled: () -> Unit = {},
                progress: (Int, Int) -> Unit = { _, _ -> }): PendingImport {
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
            if (store.books().any { TrackIdentity.matches(tracks, it.tracks) })
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
        if (store.books().any { TrackIdentity.matches(pending.tracks, it.tracks) })
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

    fun remove(book: LibraryBook) {
        // Commit index removal first. A crash or failed cleanup leaves an unreferenced owned
        // directory, recovered on the next load, never a visible row pointing at deleted audio.
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
