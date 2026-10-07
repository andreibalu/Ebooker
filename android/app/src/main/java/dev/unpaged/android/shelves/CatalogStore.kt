package dev.unpaged.android.shelves

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import androidx.core.database.sqlite.transaction
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import org.json.JSONObject
import java.io.IOException

/** Cursor and page commit together: a killed process replays at most the uncommitted page. */
data class SyncCursor(val offset: Int = 0, val since: Long = 0, val started: Long = 0,
    val completed: Long = 0, val ready: Boolean = false)
interface CatalogStore {
    fun books(): List<CatalogBook>
    fun count(): Int = books().size
    fun seed(books: List<CatalogBook>)
    fun cursor(): SyncCursor
    fun commit(books: List<CatalogBook>, cursor: SyncCursor)
}
class SQLiteCatalogStore(context: Context) : SQLiteOpenHelper(context, "librivox-catalog.db", null, 1), CatalogStore {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE catalog (id TEXT PRIMARY KEY, json TEXT NOT NULL)")
        db.execSQL("CREATE TABLE sync (singleton INTEGER PRIMARY KEY CHECK(singleton=1), offset INTEGER NOT NULL, since INTEGER NOT NULL, started INTEGER NOT NULL, completed INTEGER NOT NULL, ready INTEGER NOT NULL)")
        db.execSQL("INSERT INTO sync VALUES (1,0,0,0,0,0)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // v1: future versions must add explicit migrations; never discard this cache to mask an upgrade.
        check(oldVersion == newVersion) { "Unsupported catalog migration" }
    }
    override fun books(): List<CatalogBook> = buildList {
        readableDatabase.rawQuery("SELECT json FROM catalog ORDER BY rowid", null).use { rows ->
            while (rows.moveToNext()) add(LibriVoxClient.decodeBook(JSONObject(rows.getString(0))))
        }
    }
    fun title(id: String): String? = readableDatabase.rawQuery("SELECT json FROM catalog WHERE id = ?", arrayOf(id)).use {
        if (it.moveToFirst()) LibriVoxClient.decodeBook(JSONObject(it.getString(0))).title else null
    }
    override fun count(): Int = readableDatabase.rawQuery("SELECT COUNT(*) FROM catalog", null).use { it.moveToFirst(); it.getInt(0) }
    override fun cursor(): SyncCursor = readableDatabase.rawQuery("SELECT offset,since,started,completed,ready FROM sync WHERE singleton=1", null).use {
        check(it.moveToFirst()); SyncCursor(it.getInt(0), it.getLong(1), it.getLong(2), it.getLong(3), it.getInt(4) == 1)
    }
    private fun write(db: SQLiteDatabase, books: List<CatalogBook>) {
        books.filter { it.id.isNotBlank() }.forEach { book ->
            // Preserve cached tracks when metadata-only pages revisit a row.
            val prior = db.rawQuery("SELECT json FROM catalog WHERE id=?", arrayOf(book.id)).use {
                if (it.moveToFirst()) LibriVoxClient.decodeBook(JSONObject(it.getString(0))) else null
            }
            val stored = if (book.tracks.isEmpty() && prior != null) book.copy(tracks = prior.tracks) else book
            db.insertWithOnConflict("catalog", null, ContentValues().apply {
                put("id", stored.id); put("json", LibriVoxClient.encodeBook(stored))
            }, SQLiteDatabase.CONFLICT_REPLACE)
        }
    }
    override fun seed(books: List<CatalogBook>) {
        writableDatabase.transaction { write(this, books) }
        if (books.isNotEmpty()) dev.unpaged.android.library.LibraryContentChanges.committed()
    }
    override fun commit(books: List<CatalogBook>, cursor: SyncCursor) {
        writableDatabase.transaction {
            write(this, books)
            execSQL("UPDATE sync SET offset=?,since=?,started=?,completed=?,ready=? WHERE singleton=1",
                arrayOf<Any>(cursor.offset, cursor.since, cursor.started, cursor.completed, if (cursor.ready) 1 else 0))
        }
        if (books.isNotEmpty()) dev.unpaged.android.library.LibraryContentChanges.committed()
    }
}

class CatalogSync(private val store: CatalogStore, private val fetch: (Int, Long) -> List<CatalogBook>,
    private val now: () -> Long = System::currentTimeMillis,
    private val backoff: suspend (Long) -> Unit = { delay(it) }) {
    suspend fun run(progress: (Int) -> Unit = {}) {
        var cursor = store.cursor()
        if (cursor.started == 0L && cursor.completed > 0 && now() - cursor.completed < 86_400_000) return
        if (cursor.started == 0L) {
            cursor = cursor.copy(offset = 0, since = cursor.completed, started = now())
            store.commit(emptyList(), cursor)
        }
        while (true) {
            currentCoroutineContext().ensureActive()
            val page = retry { fetch(cursor.offset, cursor.since) }
            currentCoroutineContext().ensureActive()
            val done = page.size < 50
            cursor = if (done) cursor.copy(offset = 0, completed = cursor.started, started = 0, ready = true)
                else cursor.copy(offset = cursor.offset + page.size)
            store.commit(page, cursor)
            progress(store.count())
            if (done) return
        }
    }
    private suspend fun <T> retry(operation: () -> T): T {
        repeat(3) { attempt ->
            try { return operation() } catch (cancel: CancellationException) { throw cancel }
            catch (error: Exception) {
                val transient = error is IOException || error is FeedProblem && (error.status == null || error.status == 429 || error.status >= 500)
                if (attempt == 2 || !transient) throw error
                backoff((attempt + 1) * 1000L)
            }
        }
        error("Unreachable")
    }
}
