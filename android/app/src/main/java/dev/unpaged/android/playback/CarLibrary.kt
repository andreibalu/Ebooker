package dev.unpaged.android.playback

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import dev.unpaged.android.UnpagedPreferences
import dev.unpaged.android.library.*
import dev.unpaged.android.shelves.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** IDs describe app-owned books only. Controllers cannot inject arbitrary file/network URIs. */
@androidx.annotation.OptIn(UnstableApi::class)
class CarLibrary(private val context: Context, private val store: LibraryStore = SQLiteLibraryStore(context),
    private val catalog: CatalogStore = SQLiteCatalogStore(context),
    private val connected: () -> Boolean = { ShelvesSession.get(context).connected() }) : java.io.Closeable {
    companion object {
        const val ROOT = "root"
        val tabs = listOf("Favorites", "Library", "Shelves")
        const val CHAPTERS = "chapters"
        fun latest(books: List<LibraryBook>) = books.filter { it.tracks.isNotEmpty() }
            .maxByOrNull { it.lastPlayedAt ?: 0L }
        fun searchIDs(query: String, books: List<LibraryBook>, classics: List<CatalogBook>): List<String> {
            val needle = fold(query.trim())
            if (needle.isEmpty()) return listOfNotNull(latest(books)?.let { "book:${it.id}" })
            val library = books.filter { fold(it.title).contains(needle) || fold(it.author).contains(needle) }
            val titles = library.map { fold(it.title) }.toSet()
            return (library.map { "book:${it.id}" } + classics.filter {
                fold(it.title) !in titles && (fold(it.title).contains(needle) || fold(it.author).contains(needle))
            }.distinctBy { fold(it.title) }.map { "catalog:${it.id}" }).take(30)
        }
        fun page(items: List<MediaItem>, page: Int, size: Int): List<MediaItem> {
            require(page >= 0 && size > 0)
            val from = (page.toLong() * size).coerceAtMost(items.size.toLong()).toInt()
            return items.subList(from, (from.toLong() + size).coerceAtMost(items.size.toLong()).toInt())
        }
        fun folder(id: String, title: String = id) = item(id, title, "", false)
        private fun item(id: String, title: String, subtitle: String, playable: Boolean): MediaItem =
            MediaItem.Builder().setMediaId(id).setMediaMetadata(MediaMetadata.Builder()
                .setTitle(title).setSubtitle(subtitle).setArtist(subtitle).setIsBrowsable(!playable)
                .setIsPlayable(playable).setMediaType(if (playable) MediaMetadata.MEDIA_TYPE_AUDIO_BOOK else MediaMetadata.MEDIA_TYPE_FOLDER_MIXED)
                .build()).build()
        fun bookItem(book: LibraryBook): MediaItem {
            val marker = dev.unpaged.android.abs.ABSRules.position(book.highWaterMarkMs, book.tracks.map { it.durationMs })
            val subtitle = if (book.highWaterMarkMs > 0) {
                "${book.tracks.getOrNull(marker.first)?.title ?: "Track"} · ${trackDuration(marker.second)}"
            } else book.author.ifBlank { "Unknown Author" }
            return item("book:${book.id}", book.title, subtitle, true)
        }
        fun catalogItem(book: CatalogBook) = item("catalog:${book.id}", book.title, "${book.author} · ${book.duration}", true)
    }
    override fun close() {
        (store as? SQLiteLibraryStore)?.close()
        (catalog as? SQLiteCatalogStore)?.close()
    }
    private fun classics() = catalog.books().filter { it.id in Classics.ids }
        .sortedBy { Classics.ids.indexOf(it.id) }
    private fun withArtwork(item: MediaItem): MediaItem {
        val uri = if (item.mediaMetadata.isPlayable == true && !item.mediaId.startsWith("chapter:")) CarArtworkProvider.uri(context, item.mediaId)
            else if (item.mediaId in tabs) android.net.Uri.Builder().scheme("android.resource").authority(context.packageName)
                .appendPath(when (item.mediaId) { "Favorites" -> dev.unpaged.android.R.drawable.car_favorites
                    "Library" -> dev.unpaged.android.R.drawable.car_library
                    else -> dev.unpaged.android.R.drawable.car_shelves }.toString()).build() else null
        return item.buildUpon().setMediaMetadata(item.mediaMetadata.buildUpon().setArtworkUri(uri).build()).build()
    }
    fun children(parent: String): List<MediaItem> = when (parent) {
        ROOT -> tabs.map { folder(it) }
        "Favorites", "Library" -> sortedBooks(store.books().filter { parent != "Favorites" || it.isFavorite },
            UnpagedPreferences(context).sort("Library")).map(::bookItem)
        "Shelves" -> {
            val inLibrary = store.books().mapNotNull { it.catalogId }.toSet()
            classics().filter { it.id !in inLibrary }.map(::catalogItem)
        }
        CHAPTERS -> PlayerController.get(context).state.value.chapters.map {
            item("chapter:${it.index}", it.title, trackDuration(it.durationMs), true)
        }
        else -> throw IllegalArgumentException("Unknown list")
    }.map(::withArtwork)
    fun search(query: String): List<MediaItem> {
        val books = store.books(); val cached = classics()
        return searchIDs(query, books, cached).mapNotNull { id ->
            books.firstOrNull { "book:${it.id}" == id }?.let(::bookItem)
                ?: cached.firstOrNull { "catalog:${it.id}" == id }?.let(::catalogItem)
        }.map(::withArtwork)
    }
    fun item(id: String): MediaItem? = when {
        id == ROOT -> folder(ROOT, "Unpaged")
        id in tabs || id == CHAPTERS -> folder(id)
        id.startsWith("book:") -> store.books().firstOrNull { "book:${it.id}" == id }?.let(::bookItem)
        id.startsWith("catalog:") -> classics().firstOrNull { "catalog:${it.id}" == id }?.let(::catalogItem)
        id.startsWith("chapter:") -> children(CHAPTERS).firstOrNull { it.mediaId == id }
        else -> null
    }?.let(::withArtwork)
    suspend fun resolve(id: String): LibraryBook = withContext(Dispatchers.IO) {
        val existing = if (id.startsWith("book:")) store.books().firstOrNull { "book:${it.id}" == id }
            else if (id.startsWith("catalog:")) CatalogLibraryService(store).identity(id.removePrefix("catalog:")) else null
        if (existing != null) {
            require(existing.tracks.isNotEmpty()) { "This book has no available tracks." }
            if (!existing.isDownloaded && !connected()) error("No internet connection")
            return@withContext existing
        }
        val book = classics().firstOrNull { "catalog:${it.id}" == id } ?: error("This book is no longer available.")
        if (!connected()) error("No internet connection")
        val tracks = book.tracks.ifEmpty { LibriVoxClient().tracks(book.id).also { catalog.seed(listOf(book.copy(tracks = it))) } }
        CatalogLibraryService(store).add(book, tracks)
    }
}
