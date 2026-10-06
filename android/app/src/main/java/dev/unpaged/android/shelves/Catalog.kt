package dev.unpaged.android.shelves

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.text.Normalizer
import java.util.Locale
import kotlin.math.roundToInt

/** No remote covers: the product deliberately uses generated lettering covers. */
data class CatalogBook(val id: String, val title: String, val author: String, val description: String,
    val language: String, val seconds: Int, val genres: List<String> = emptyList(),
    val tracks: List<CatalogTrack> = emptyList()) {
    val sizeMB: Int get() = (seconds * .008).roundToInt().coerceAtLeast(1)
    val duration: String get() {
        val minutes = seconds / 60
        return when { seconds <= 0 -> "Unknown length"; minutes < 60 -> "${minutes}m"
            minutes % 60 == 0 -> "${minutes / 60}h"; else -> "${minutes / 60}h ${minutes % 60}m" }
    }
}
data class CatalogTrack(val number: Int, val title: String, val seconds: Long, val url: String)

class FeedProblem(val status: Int? = null) : Exception(if (status == null)
    "LibriVox returned an unexpected response. Please try again in a moment."
    else "LibriVox is temporarily unavailable. Please try again in a moment.")
data class FeedResponse(val status: Int, val body: String)
fun interface FeedEngine { fun get(url: String): FeedResponse }

object HttpFeedEngine : FeedEngine {
    override fun get(url: String): FeedResponse {
        val connection = URI(url).toURL().openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000; connection.readTimeout = 20_000
        try {
            val status = connection.responseCode
            val body = (if (status in 200..299) connection.inputStream else connection.errorStream)
                ?.bufferedReader()?.use { it.readText() }.orEmpty()
            return FeedResponse(status, body)
        } finally { connection.disconnect() }
    }
}

class LibriVoxClient(private val engine: FeedEngine = HttpFeedEngine,
    private val base: String = "https://librivox.org/api/feed") {
    fun url(path: String, parameters: List<Pair<String, String>>): String = "$base/$path?" +
        parameters.joinToString("&") { (k, v) -> "${encode(k)}=${encode(v)}" }
    private fun encode(value: String) = URLEncoder.encode(value, "UTF-8").replace("+", "%20")
    private fun envelope(path: String, params: List<Pair<String, String>>, key: String): JSONArray {
        val response = engine.get(url(path, listOf("format" to "json") + params))
        val json = runCatching { JSONObject(response.body) }.getOrNull()
        if (response.status == 404 && path == "audiobooks" && json?.optString("error") == "Audiobooks could not be found") return JSONArray()
        if (response.status !in 200..299) throw FeedProblem(response.status)
        if (json == null) throw FeedProblem()
        if (!json.has(key) || json.isNull(key)) return JSONArray()
        return json.optJSONArray(key) ?: throw FeedProblem()
    }
    fun books(params: List<Pair<String, String>>): List<CatalogBook> {
        val rows = envelope("audiobooks", listOf("extended" to "1") + listOf("id", "title", "description", "totaltimesecs", "authors", "language", "url_librivox", "url_iarchive", "url_rss", "coverart_thumbnail", "genres").map { "fields[]" to it } + params, "books")
        return try { (0 until rows.length()).map { decodeBook(rows.getJSONObject(it)) } }
        catch (_: org.json.JSONException) { throw FeedProblem() }
    }
    fun book(id: String) = books(listOf("id" to id)).firstOrNull()
    fun page(offset: Int, since: Long) = books(listOf("limit" to "50", "offset" to "$offset") +
        if (since > 0) listOf("since" to "${since / 1000}") else emptyList())
    fun search(query: String): List<CatalogBook> = (books(listOf("title" to query, "limit" to "50")) +
        books(listOf("author" to query, "limit" to "50"))).distinctBy { it.id }.sortedWith(
        compareBy<CatalogBook> { val t = fold(it.title); val q = fold(query)
            when { t.startsWith(q) -> 0; t.contains(q) -> 1; fold(it.author).contains(q) -> 2; else -> 3 } }.thenBy { fold(it.title) }.thenBy { it.id })
    fun genre(genre: String) = books(listOf("genre" to genre, "limit" to "100"))
    fun tracks(id: String): List<CatalogTrack> {
        val rows = envelope("audiotracks", listOf("project_id" to id), "sections")
        return try { (0 until rows.length()).map { decodeTrack(rows.getJSONObject(it)) }.sortedBy { it.number } }
        catch (_: org.json.JSONException) { throw FeedProblem() }
    }
    companion object {
        fun decodeBook(row: JSONObject): CatalogBook {
            val authors = row.optJSONArray("authors") ?: JSONArray()
            val author = (0 until authors.length()).map { authors.getJSONObject(it) }.map {
                listOf(it.optString("first_name"), it.optString("last_name")).filter { s -> s.isNotBlank() }.joinToString(" ")
            }.filter { it.isNotBlank() }.joinToString(", ").ifBlank { row.optString("author", "Unknown Author") }
            val genres = row.optJSONArray("genres") ?: JSONArray()
            val tracks = row.optJSONArray("sections") ?: JSONArray()
            return CatalogBook(row.optString("id"), row.optString("title"), author, row.optString("description"),
                row.optString("language"), row.optInt("totaltimesecs").coerceAtLeast(0),
                (0 until genres.length()).map { genres.getJSONObject(it).optString("name") }.filter { it.isNotBlank() },
                (0 until tracks.length()).map { decodeTrack(tracks.getJSONObject(it)) }.sortedBy { it.number })
        }
        fun decodeTrack(row: JSONObject): CatalogTrack {
            val seconds = row.optString("playtime", "0").split(':').fold(0L) { total, part -> total * 60 + (part.toDoubleOrNull()?.toLong() ?: 0) }
            return CatalogTrack(row.optInt("section_number"), row.optString("title"), seconds.coerceAtLeast(0), row.optString("listen_url"))
        }
        fun encodeBook(book: CatalogBook): String = JSONObject().apply {
            put("id", book.id); put("title", book.title); put("author", book.author); put("description", book.description)
            put("language", book.language); put("totaltimesecs", book.seconds)
            put("genres", JSONArray(book.genres.map { JSONObject().put("name", it) }))
            put("sections", JSONArray(book.tracks.map { JSONObject().put("section_number", it.number).put("title", it.title)
                .put("playtime", it.seconds.toString()).put("listen_url", it.url) }))
        }.toString()
    }
}

fun fold(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFD)
    .replace(Regex("\\p{M}+"), "").lowercase(Locale.ROOT)
object Classics {
    val ids = listOf("314", "253", "133", "381", "271", "449", "436", "510")
    fun pick(dayOfYear: Int) = ids[Math.floorMod(dayOfYear, ids.size)]
}
object OtherRecordings {
    private val suffix = Regex("\\s*\\((version\\s*\\d+(?:\\s+dramatic\\s+reading)?|dramatic\\s+reading|abridged|unabridged|solo|group)\\)\\s*$", RegexOption.IGNORE_CASE)
    fun key(title: String): String {
        var value = title
        while (true) { val next = value.replace(suffix, ""); if (next == value) break; value = next }
        return fold(value).trim().replace(Regex("\\s+"), " ")
    }
    fun label(title: String): String? = suffix.find(title)?.groupValues?.get(1)
    fun alternatives(book: CatalogBook, books: List<CatalogBook>): List<CatalogBook> = books.filter {
        it.id != book.id && it.author == book.author && it.language == book.language && key(it.title) == key(book.title)
    }.sortedWith(compareBy<CatalogBook> { val l = label(it.title); when { l == null -> 0; l.startsWith("version", true) -> 1; else -> 2 } }
        .thenBy { Regex("\\d+").find(label(it.title).orEmpty())?.value?.toIntOrNull() ?: 0 }.thenBy { it.title })
}

data class BookCollection(val id: String, val title: String, val subtitle: String, val ids: List<String>)
object Collections {
    val all = listOf(
        BookCollection("ancient-wisdom", "Ancient Wisdom", "Stoics, strategy & the examined life", listOf("12252", "15279", "1358", "18903", "119")),
        BookCollection("gothic-horror", "Gothic & Horror", "Vampires, monsters & haunted minds", listOf("271", "381", "365", "417", "431", "977")),
        BookCollection("detective-mystery", "Detective & Mystery", "Whodunits and master sleuths", listOf("314", "901", "966", "424", "635")),
        BookCollection("grand-adventures", "Grand Adventures", "Treasure, travel & daring escapes", listOf("449", "714", "158", "544", "120", "47")),
        BookCollection("love-society", "Love & Society", "Romance, manners & sharp wit", listOf("253", "133", "661", "620", "86", "911")),
        BookCollection("short-listens", "Short Listens", "Finished in an afternoon", listOf("15279", "119", "18903", "1126", "140", "417")))
}

/** iOS picks five classics once per visit; fixture order is supplied only by the debug variant. */
fun featuredCatalogIDs(books: List<CatalogBook>): List<String> {
    val curated = books.filter { it.id in Classics.ids }
    if (curated.size >= 5) return curated.shuffled().take(5).map { it.id }
    val titles = listOf("The Art of War", "The Adventures of Sherlock Holmes", "Pride and Prejudice", "Jane Eyre",
        "Adventures of Huckleberry Finn", "Frankenstein", "The Picture of Dorian Gray", "The Scarlet Pimpernel", "Dracula",
        "The Count of Monte Cristo", "Treasure Island", "The War of the Worlds", "The Invisible Man", "The Wonderful Wizard of Oz",
        "Gulliver's Travels", "Our Mutual Friend", "A Tale of Two Cities", "The Woman in White", "Crime and Punishment",
        "Anna Karenina", "Black Beauty", "Persuasion", "Barnaby Rudge", "Three Men in a Boat", "Twenty Years After",
        "Incidents in the Life of a Slave Girl", "The Mysterious Affair at Styles", "Common Sense", "The Dhammapada", "The Iliad", "The Odyssey")
    return (curated + books.filter { b -> titles.any { fold(b.title).contains(fold(it)) } }).distinctBy { it.id }.shuffled().take(5).map { it.id }
}
