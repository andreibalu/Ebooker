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
    private val playback: () -> PlayerState = { PlayerController.get(context).state.value },
    private val connected: () -> Boolean = { ShelvesSession.get(context).connected() }) : java.io.Closeable {
    companion object {
        const val ROOT = "root"
        val tabs = listOf("Favorites", "Library", "Shelves")
        const val CHAPTERS = "chapters"
        fun chapterID(bookId: String, index: Int) = "chapter:${android.net.Uri.encode(bookId)}:$index"
        fun chapterIndex(id: String, bookId: String): Int? = id.removePrefix("chapter:${android.net.Uri.encode(bookId)}:")
            .takeIf { id.startsWith("chapter:${android.net.Uri.encode(bookId)}:") }?.toIntOrNull()?.takeIf { it >= 0 }
        fun latest(books: List<LibraryBook>) = books.filter { it.tracks.isNotEmpty() }
            .maxByOrNull { it.lastPlayedAt ?: 0L }
        private val fillerTokens = setOf("by", "the", "a", "an", "and", "of", "from", "audiobook", "book")
        /** Folds case, diacritics, apostrophes and punctuation so "Alices adventures" meets "Alice's Adventures". */
        fun searchFold(text: String): String = fold(text).replace(Regex("['\u2019`]"), "")
            .replace(Regex("[^\\p{L}\\p{N}]+"), " ").trim()
        fun searchTokens(query: String): List<String> {
            val all = searchFold(query).split(' ').filter { it.isNotEmpty() }
            return all.filter { it !in fillerTokens }.ifEmpty { all }
        }
        fun searchIDs(query: String, books: List<LibraryBook>, classics: List<CatalogBook>): List<String> {
            val phrase = searchFold(query); val tokens = searchTokens(query)
            if (tokens.isEmpty()) return listOfNotNull(latest(books)?.let { "book:${it.id}" })
            fun exact(title: String, author: String) = searchFold(title).contains(phrase) || searchFold(author).contains(phrase)
            fun loose(title: String, author: String) = "${searchFold(title)} ${searchFold(author)}".let { text -> tokens.all { it in text } }
            val library = books.filter { loose(it.title, it.author) }.sortedByDescending { exact(it.title, it.author) }
            val titles = library.map { fold(it.title) }.toSet()
            return (library.map { "book:${it.id}" } + classics.filter { fold(it.title) !in titles && loose(it.title, it.author) }
                .sortedByDescending { exact(it.title, it.author) }
                .distinctBy { fold(it.title) }.map { "catalog:${it.id}" }).take(30)
        }
        /** Cheap identity of a car list: ids, titles and subtitles; artwork URIs follow the id. */
        fun signature(items: List<MediaItem>): Int = items.map {
            Triple(it.mediaId, it.mediaMetadata.title?.toString(), it.mediaMetadata.subtitle?.toString())
        }.hashCode()
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
                    else -> dev.unpaged.android.R.drawable.car_shelves }.toString()).build()
            else if (item.mediaId == CHAPTERS) android.net.Uri.Builder().scheme("android.resource").authority(context.packageName)
                .appendPath(dev.unpaged.android.R.drawable.car_chapters.toString()).build() else null
        return item.buildUpon().setMediaMetadata(item.mediaMetadata.buildUpon().setArtworkUri(uri).build()).build()
    }
    fun children(parent: String): List<MediaItem> = when (parent) {
        // Car hosts cannot open a list from a now-playing button, so chapters are a browse tab while a book is loaded.
        ROOT -> tabs.map { folder(it) } + listOfNotNull(if (playback().book != null) folder(CHAPTERS, "Chapters") else null)
        "Favorites", "Library" -> sortedBooks(store.books().filter { parent != "Favorites" || it.isFavorite },
            UnpagedPreferences(context).sort("Library")).map(::bookItem)
        "Shelves" -> {
            val inLibrary = store.books().mapNotNull { it.catalogId }.toSet()
            classics().filter { it.id !in inLibrary }.map(::catalogItem)
        }
        CHAPTERS -> playback().let { state -> state.book?.let { book -> state.chapters.map {
            item(chapterID(book.id, it.index), it.title, trackDuration(it.durationMs), true)
        } }.orEmpty() }
        else -> throw IllegalArgumentException("Unknown list")
    }.map(::withArtwork)
    fun chapter(id: String): PlaybackChapter? = playback().let { state ->
        state.book?.let { book -> chapterIndex(id, book.id)?.let { index -> state.chapters.firstOrNull { it.index == index } } }
    }
    fun search(query: String): List<MediaItem> {
        val books = store.books(); val cached = classics()
        return searchIDs(query, books, cached).mapNotNull { id ->
            books.firstOrNull { "book:${it.id}" == id }?.let(::bookItem)
                ?: cached.firstOrNull { "catalog:${it.id}" == id }?.let(::catalogItem)
        }.map(::withArtwork)
    }
    fun item(id: String): MediaItem? = when {
        id == ROOT -> folder(ROOT, "Unpaged")
        id in tabs -> folder(id)
        id == CHAPTERS -> folder(CHAPTERS, "Chapters")
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
