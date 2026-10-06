package dev.unpaged.android.shelves

import dev.unpaged.android.library.*
import java.util.UUID

/** Match catalog identity, never title: alternative recordings are distinct books. */
class CatalogLibraryService(private val store: LibraryStore) {
    @Synchronized fun add(book: CatalogBook, tracks: List<CatalogTrack>): LibraryBook {
        identity(book.id)?.let { return it }
        require(tracks.isNotEmpty()) { "No audio tracks are available for this book." }
        val libraryTracks = tracks.map {
            require(java.net.URI(it.url).scheme == "https") { "This recording has an unsupported audio URL." }
            LibraryTrack(it.title, "${it.number}.mp3", "", it.seconds * 1000, "librivox:${book.id}:${it.number}", it.url)
        }
        return LibraryBook(UUID.randomUUID().toString(), book.title, book.author, libraryTracks,
            isFreeBook = true, catalogId = book.id, isDownloaded = false).also(store::insert)
    }
    fun identity(id: String) = store.books().filter { it.isFreeBook && it.catalogId == id }.sortedWith(
        compareByDescending<LibraryBook> { it.isDownloaded }.thenBy { it.dateAdded }.thenBy { it.id }).firstOrNull()
    fun promote(id: String, tracks: List<LibraryTrack>, bytes: Long) = store.promoteDownload(id, tracks, bytes)
}
