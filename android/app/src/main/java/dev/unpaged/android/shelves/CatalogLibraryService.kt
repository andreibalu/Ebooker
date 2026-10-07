package dev.unpaged.android.shelves

import dev.unpaged.android.library.*
import java.util.UUID

/** Match catalog identity, never title: alternative recordings are distinct books. */
class CatalogLibraryService(private val store: LibraryStore) {
    companion object { private val identityLock = Any() }
    fun add(book: CatalogBook, tracks: List<CatalogTrack>): LibraryBook = synchronized(identityLock) {
        match(book.id)?.let {
            if (it.isArchived) store.setAvailability(it.id, false, false)
            return@synchronized it.copy(isArchived = false)
        }
        require(tracks.isNotEmpty()) { "No audio tracks are available for this book." }
        val libraryTracks = tracks.map {
            require(CatalogEnvironment.permitsAudio(it.url)) { "This recording has an unsupported audio URL." }
            LibraryTrack(it.title, "${it.number}.mp3", "", it.seconds * 1000, "librivox:${book.id}:${it.number}", it.url)
        }
        LibraryBook(UUID.randomUUID().toString(), book.title, book.author, libraryTracks,
            isFreeBook = true, catalogId = book.id, isDownloaded = false).also(store::insert)
    }
    private fun match(id: String) = store.books().filter { it.isFreeBook && it.catalogId == id }.sortedWith(
        compareBy<LibraryBook> { if (it.isArchived) 2 else if (it.isDownloaded) 0 else 1 }
            .thenBy { it.dateAdded }.thenBy { it.id }).firstOrNull()
    fun identity(id: String) = match(id)?.takeUnless { it.isArchived }
    fun promote(id: String, tracks: List<LibraryTrack>, bytes: Long) = store.promoteDownload(id, tracks, bytes)
}
