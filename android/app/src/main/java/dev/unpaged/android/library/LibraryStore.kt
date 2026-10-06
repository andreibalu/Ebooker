package dev.unpaged.android.library

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import androidx.core.database.sqlite.transaction

interface LibraryStore {
    fun books(): List<LibraryBook>
    fun insert(book: LibraryBook)
    fun delete(id: String)
    fun toggleFavorite(id: String)
    fun updatePlaybackProgress(id: String, progress: PlaybackProgress)
    fun moments(bookId: String): List<LibraryMoment>
    fun saveMoment(moment: LibraryMoment)
    fun deleteMoment(id: String)
}

/** Schema v2 adds parity state without replacing any existing book or track. */
class SQLiteLibraryStore(context: Context) : SQLiteOpenHelper(context, "library.db", null, 2), LibraryStore {
    private val audioRoot = java.io.File(context.filesDir, "audiobooks")

    override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true) }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE books (id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL)")
        db.execSQL("""CREATE TABLE tracks (book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            position INTEGER NOT NULL, title TEXT NOT NULL, original_name TEXT NOT NULL,
            stored_name TEXT NOT NULL, duration_ms INTEGER NOT NULL, fingerprint TEXT NOT NULL,
            PRIMARY KEY(book_id, position))""")
        migrateToV2(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2 && newVersion >= 2) migrateToV2(db)
    }

    private fun migrateToV2(db: SQLiteDatabase) {
        listOf("is_favorite INTEGER NOT NULL DEFAULT 0", "last_played_at INTEGER",
            "current_track_index INTEGER NOT NULL DEFAULT 0", "current_position_ms INTEGER NOT NULL DEFAULT 0",
            "high_water_mark_ms INTEGER NOT NULL DEFAULT 0", "playback_speed REAL NOT NULL DEFAULT 1.0",
            "is_finished INTEGER NOT NULL DEFAULT 0", "is_free_book INTEGER NOT NULL DEFAULT 0", "catalog_id TEXT",
            "is_downloaded INTEGER NOT NULL DEFAULT 1", "storage_bytes INTEGER NOT NULL DEFAULT 0",
            "equalizer_json TEXT", "date_added INTEGER NOT NULL DEFAULT 0").forEach {
            db.execSQL("ALTER TABLE books ADD COLUMN $it")
        }
        // v1 had no insertion timestamp; rowid retains its stable newest-first ordering.
        db.execSQL("UPDATE books SET date_added = rowid")
        db.query("books", arrayOf("id"), null, null, null, null, null).use { rows ->
            while (rows.moveToNext()) {
                val id = rows.getString(0)
                if (runCatching { java.util.UUID.fromString(id).toString() == id }.getOrDefault(false)) {
                    val folder = java.io.File(audioRoot, id)
                    val bytes = if (folder.isDirectory) folder.walkTopDown().filter { it.isFile }.sumOf { it.length() } else 0L
                    db.update("books", ContentValues().apply { put("storage_bytes", bytes) }, "id = ?", arrayOf(id))
                }
            }
        }
        db.execSQL("ALTER TABLE tracks ADD COLUMN remote_url TEXT")
        // Empty stored_name means no local file for a streaming track. Never construct a file for it.
        db.execSQL("""CREATE TABLE moments (id TEXT PRIMARY KEY,
            book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            track_index INTEGER NOT NULL, time_ms INTEGER NOT NULL, label TEXT NOT NULL,
            notes TEXT NOT NULL, categories_json TEXT NOT NULL, quote_line TEXT,
            characters_json TEXT NOT NULL, mood TEXT, created_at INTEGER NOT NULL)""")
        db.execSQL("CREATE INDEX moments_book ON moments(book_id, created_at)")
    }

    override fun books(): List<LibraryBook> {
        val result = mutableListOf<LibraryBook>()
        readableDatabase.query("books", null, null, null, null, null, "date_added DESC, rowid DESC").use { r ->
            while (r.moveToNext()) {
                val id = r.text("id")
                val tracks = mutableListOf<LibraryTrack>()
                readableDatabase.query("tracks", null, "book_id = ?", arrayOf(id), null, null, "position ASC").use { t ->
                    while (t.moveToNext()) tracks += LibraryTrack(t.text("title"), t.text("original_name"), t.text("stored_name"),
                        t.long("duration_ms"), t.text("fingerprint"), t.optional("remote_url"))
                }
                result += LibraryBook(id, r.text("title"), r.text("author"), tracks,
                    r.bool("is_favorite"), r.optionalLong("last_played_at"), r.long("current_track_index").toInt(),
                    r.long("current_position_ms"), r.long("high_water_mark_ms"), r.getDouble(r.getColumnIndexOrThrow("playback_speed")),
                    r.bool("is_finished"), r.bool("is_free_book"), r.optional("catalog_id"), r.bool("is_downloaded"),
                    r.long("storage_bytes"), r.optional("equalizer_json"), r.long("date_added"))
            }
        }
        return result
    }

    override fun insert(book: LibraryBook) {
        val db = writableDatabase
        db.transaction {
            db.insertOrThrow("books", null, ContentValues().apply {
                put("id", book.id); put("title", book.title); put("author", book.author)
                put("is_favorite", book.isFavorite); put("last_played_at", book.lastPlayedAt)
                put("current_track_index", book.currentTrackIndex); put("current_position_ms", book.currentPositionMs)
                put("high_water_mark_ms", book.highWaterMarkMs); put("playback_speed", book.playbackSpeed)
                put("is_finished", book.isFinished); put("is_free_book", book.isFreeBook); put("catalog_id", book.catalogId)
                put("is_downloaded", book.isDownloaded); put("storage_bytes", book.storageBytes)
                put("equalizer_json", book.equalizerJson); put("date_added", book.dateAdded)
            })
            book.tracks.forEachIndexed { index, track ->
                db.insertOrThrow("tracks", null, ContentValues().apply {
                    put("book_id", book.id); put("position", index); put("title", track.title)
                    put("original_name", track.originalName); put("stored_name", track.storedName)
                    put("duration_ms", track.durationMs); put("fingerprint", track.fingerprint); put("remote_url", track.remoteUrl)
                })
            }
        }
    }

    override fun toggleFavorite(id: String) {
        writableDatabase.execSQL("UPDATE books SET is_favorite = 1 - is_favorite WHERE id = ?", arrayOf(id))
    }

    override fun updatePlaybackProgress(id: String, progress: PlaybackProgress) {
        require(progress.trackIndex >= 0 && progress.positionMs >= 0 && progress.highWaterMarkMs >= 0)
        require(progress.speed.isFinite() && progress.speed > 0)
        writableDatabase.execSQL("""UPDATE books SET current_track_index = ?, current_position_ms = ?,
            high_water_mark_ms = MAX(high_water_mark_ms, ?), playback_speed = ?, is_finished = ?, last_played_at = ? WHERE id = ?""",
            arrayOf<Any>(progress.trackIndex, progress.positionMs, progress.highWaterMarkMs, progress.speed,
                if (progress.finished) 1 else 0, progress.playedAt, id))
    }

    override fun moments(bookId: String): List<LibraryMoment> = buildList {
        readableDatabase.query("moments", null, "book_id = ?", arrayOf(bookId), null, null, "created_at DESC, id ASC").use { r ->
            while (r.moveToNext()) add(LibraryMoment(r.text("id"), r.text("book_id"), r.long("track_index").toInt(),
                r.long("time_ms"), r.text("label"), r.text("notes"), r.text("categories_json"), r.optional("quote_line"),
                r.text("characters_json"), r.optional("mood"), r.long("created_at")))
        }
    }

    override fun saveMoment(moment: LibraryMoment) {
        require(moment.trackIndex >= 0 && moment.timeMs >= 0)
        val values = ContentValues().apply {
            put("id", moment.id); put("book_id", moment.bookId); put("track_index", moment.trackIndex)
            put("time_ms", moment.timeMs); put("label", moment.label); put("notes", moment.notes)
            put("categories_json", moment.categoriesJson); put("quote_line", moment.quoteLine)
            put("characters_json", moment.charactersJson); put("mood", moment.mood); put("created_at", moment.createdAt)
        }
        writableDatabase.transaction {
            if (update("moments", values, "id = ?", arrayOf(moment.id)) == 0) insertOrThrow("moments", null, values)
        }
    }

    override fun deleteMoment(id: String) { writableDatabase.delete("moments", "id = ?", arrayOf(id)) }
    override fun delete(id: String) { writableDatabase.delete("books", "id = ?", arrayOf(id)) }
}

private fun Cursor.text(column: String): String = getString(getColumnIndexOrThrow(column))
private fun Cursor.optional(column: String): String? = getColumnIndexOrThrow(column).let { if (isNull(it)) null else getString(it) }
private fun Cursor.long(column: String): Long = getLong(getColumnIndexOrThrow(column))
private fun Cursor.optionalLong(column: String): Long? = getColumnIndexOrThrow(column).let { if (isNull(it)) null else getLong(it) }
private fun Cursor.bool(column: String): Boolean = long(column) != 0L
