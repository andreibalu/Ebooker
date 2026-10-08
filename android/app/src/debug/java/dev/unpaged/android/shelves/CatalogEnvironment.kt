package dev.unpaged.android.shelves

import android.content.Context
import android.os.Bundle
import androidx.core.content.edit
import dev.unpaged.android.MainActivity
import org.json.JSONObject

object CatalogEnvironment {
    fun featuredIDs(context: Context, books: List<CatalogBook>): List<String> = if (savedOnly(context)) listOf("133", "381", "2531", "253", "314").filter { id -> books.any { it.id == id } } else featuredCatalogIDs(books)

    fun downloadFixture(context: Context) = context.getSharedPreferences("shelves-debug", Context.MODE_PRIVATE).getBoolean("download", false)
    fun permitsAudio(url: String) = java.net.URI(url).let { it.scheme == "https" || (it.scheme == "http" && it.host == "127.0.0.1" && it.port == 13378) }
    fun savedOnly(context: Context) = context.getSharedPreferences("shelves-debug", Context.MODE_PRIVATE).getBoolean("fixture", false)
    fun heroDay(context: Context, day: Int) = if (savedOnly(context)) 7 else day
    fun seed(context: Context, download: Boolean = false) {
        val rows = JSONObject(context.assets.open("librivox-fixture.json").bufferedReader().use { it.readText() }).getJSONArray("books")
        val store = SQLiteCatalogStore(context)
        try { store.seed((0 until rows.length()).map { LibriVoxClient.decodeBook(rows.getJSONObject(it)).let { book ->
            if (download && book.id == "133") book.copy(tracks = listOf(CatalogTrack(1, "Durable Chapter", 300, "http://127.0.0.1:13378/audio/download.wav")))
            else book
        } }) }
        finally { store.close() }
        context.getSharedPreferences("shelves-debug", Context.MODE_PRIVATE).edit(commit = true) { putBoolean("fixture", true); putBoolean("download", download) }
    }
}
/** Only the debug manifest exposes this explicit fixture entry point. */
class ShelvesFixtureActivity : MainActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent.getBooleanExtra("e2e-shelves-fixture", false)) CatalogEnvironment.seed(this, intent.getBooleanExtra("e2e-download-fixture", false))
        super.onCreate(savedInstanceState)
    }
}
