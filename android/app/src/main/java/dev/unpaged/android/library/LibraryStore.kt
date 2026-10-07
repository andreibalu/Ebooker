package dev.unpaged.android.library

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import androidx.core.database.sqlite.transaction

interface LibraryStore {
    fun readingSessions(): List<dev.unpaged.android.activity.ReadingSession> = emptyList()
    fun saveReadingSession(session: dev.unpaged.android.activity.ReadingSession) { error("Activity unsupported") }
    fun books(): List<LibraryBook>
    fun insert(book: LibraryBook)
    fun promoteDownload(id: String, tracks: List<LibraryTrack>, bytes: Long) { error("Download promotion unsupported") }
    fun delete(id: String)
    fun rename(id: String, title: String) { error("Rename unsupported") }
    fun toggleFavorite(id: String)
    fun updatePlaybackProgress(id: String, progress: PlaybackProgress)
    fun updateTrackDuration(id: String, trackIndex: Int, durationMs: Long)
    fun setProgressMarker(id: String, positionMs: Long)
    fun moments(bookId: String): List<LibraryMoment>
    fun saveMoment(moment: LibraryMoment)
    fun updateEqualizer(id: String, json: String) { error("Equalizer persistence unsupported") }
    fun deleteMoment(id: String)
}

/** Additive schema: v2 library parity, v3 moment pins + historical reading sessions, v4 ABS identity + chapters. Never rebuild user tables. */
class SQLiteLibraryStore(context: Context) : SQLiteOpenHelper(context, "library.db", null, 4), LibraryStore {
    private val audioRoot = java.io.File(context.filesDir, "audiobooks")

    override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true) }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE books (id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL)")
        db.execSQL("""CREATE TABLE tracks (book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            position INTEGER NOT NULL, title TEXT NOT NULL, original_name TEXT NOT NULL,
            stored_name TEXT NOT NULL, duration_ms INTEGER NOT NULL, fingerprint TEXT NOT NULL,
            PRIMARY KEY(book_id, position))""")
        migrateToV2(db)
        migrateToV3(db)
        migrateToV4(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2 && newVersion >= 2) migrateToV2(db)
        if (oldVersion < 3 && newVersion >= 3) migrateToV3(db)
        if (oldVersion < 4 && newVersion >= 4) migrateToV4(db)
    }

    private fun migrateToV4(db: SQLiteDatabase) {
        val columns = db.rawQuery("PRAGMA table_info(books)", null).use { rows ->
            buildSet { while (rows.moveToNext()) add(rows.getString(rows.getColumnIndexOrThrow("name"))) }
        }
        if ("abs_item_id" !in columns) db.execSQL("ALTER TABLE books ADD COLUMN abs_item_id TEXT")
        if ("abs_chapters_json" !in columns) db.execSQL("ALTER TABLE books ADD COLUMN abs_chapters_json TEXT")
    }

    private fun migrateToV3(db: SQLiteDatabase) {
        db.execSQL("ALTER TABLE moments ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0")
        // No foreign key: historical activity must outlive its book.
        db.execSQL("""CREATE TABLE reading_sessions (id TEXT PRIMARY KEY, day_key TEXT NOT NULL,
            hour INTEGER NOT NULL CHECK(hour BETWEEN 0 AND 23), minutes INTEGER NOT NULL CHECK(minutes > 0),
            book_id TEXT NOT NULL, book_title TEXT NOT NULL, book_author TEXT NOT NULL,
            is_free_book INTEGER NOT NULL, created_at INTEGER NOT NULL)""")
        db.execSQL("CREATE INDEX reading_sessions_day ON reading_sessions(day_key, hour)")
    }
    override fun readingSessions(): List<dev.unpaged.android.activity.ReadingSession> = buildList {
        readableDatabase.query("reading_sessions", null, null, null, null, null, "day_key ASC, created_at ASC, id ASC").use { r ->
            while (r.moveToNext()) add(dev.unpaged.android.activity.ReadingSession(r.text("id"),
                java.time.LocalDate.parse(r.text("day_key")), r.long("hour").toInt(), r.long("minutes").toInt(),
                r.text("book_id"), r.text("book_title"), r.text("book_author"), r.bool("is_free_book"), r.long("created_at")))
        }
    }
    override fun saveReadingSession(session: dev.unpaged.android.activity.ReadingSession) {
        require(session.hour in 0..23 && session.minutes > 0)
        writableDatabase.insertOrThrow("reading_sessions", null, ContentValues().apply {
            put("id", session.id); put("day_key", session.day.toString()); put("hour", session.hour)
            put("minutes", session.minutes); put("book_id", session.bookId); put("book_title", session.bookTitle)
            put("book_author", session.bookAuthor); put("is_free_book", session.isFreeBook); put("created_at", session.createdAt)
        })
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
                    r.long("storage_bytes"), r.optional("equalizer_json"), r.long("date_added"), r.optional("abs_item_id"), r.optional("abs_chapters_json"), java.io.File(audioRoot, "$id/cover.png").lastModified())
            }
        }
        return result
    }

    override fun insert(book: LibraryBook) {
        if (book.absItemID != null) {
            require(!book.isDownloaded && !book.isFreeBook && book.tracks.isNotEmpty())
            require(book.tracks.all { it.storedName.isEmpty() && it.remoteUrl != null && !dev.unpaged.android.abs.ABSRules.containsCredential(it.remoteUrl) })
        }
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
                put("abs_item_id", book.absItemID); put("abs_chapters_json", book.absChaptersJson)
            })
            book.tracks.forEachIndexed { index, track ->
                db.insertOrThrow("tracks", null, ContentValues().apply {
                    put("book_id", book.id); put("position", index); put("title", track.title)
                    put("original_name", track.originalName); put("stored_name", track.storedName)
                    put("duration_ms", track.durationMs); put("fingerprint", track.fingerprint); put("remote_url", track.remoteUrl)
                })
            }
        }
        LibraryContentChanges.committed()
    }

    override fun promoteDownload(id: String, tracks: List<LibraryTrack>, bytes: Long) {
        writableDatabase.transaction {
            check(update("books", ContentValues().apply { put("is_downloaded", true); put("storage_bytes", bytes) },
                "id = ?", arrayOf(id)) == 1) { "Book was removed during download" }
            delete("tracks", "book_id = ?", arrayOf(id))
            tracks.forEachIndexed { index, track ->
                insertOrThrow("tracks", null, ContentValues().apply {
                    put("book_id", id); put("position", index); put("title", track.title)
                    put("original_name", track.originalName); put("stored_name", track.storedName)
                    put("duration_ms", track.durationMs); put("fingerprint", track.fingerprint); put("remote_url", track.remoteUrl)
                })
            }
        }
        LibraryContentChanges.committed()
    }

    override fun rename(id: String, title: String) {
        require(title.isNotBlank())
        check(writableDatabase.update("books", ContentValues().apply { put("title", title.trim()) },
            "id = ?", arrayOf(id)) == 1) { "Book was removed." }
        LibraryContentChanges.committed()
    }

    override fun toggleFavorite(id: String) {
        writableDatabase.execSQL("UPDATE books SET is_favorite = 1 - is_favorite WHERE id = ?", arrayOf(id))
        LibraryContentChanges.committed()
    }

    override fun updatePlaybackProgress(id: String, progress: PlaybackProgress) {
        require(progress.trackIndex >= 0 && progress.positionMs >= 0 && progress.highWaterMarkMs >= 0)
        require(progress.speed.isFinite() && progress.speed > 0)
        writableDatabase.execSQL("""UPDATE books SET current_track_index = ?, current_position_ms = ?,
            high_water_mark_ms = MAX(high_water_mark_ms, ?), playback_speed = ?, is_finished = ?, last_played_at = ? WHERE id = ?""",
            arrayOf<Any>(progress.trackIndex, progress.positionMs, progress.highWaterMarkMs, progress.speed,
                if (progress.finished) 1 else 0, progress.playedAt, id))
        // Routine progress writes run every few seconds and never signal car lists; PlayerController
        // signals on user-visible transitions (load, pause, seek) instead.
    }

    /** One-row lookup for artwork and similar callers that must not load the whole library. */
    fun title(id: String): String? = readableDatabase.query("books", arrayOf("title"), "id = ?", arrayOf(id), null, null, null).use {
        if (it.moveToFirst()) it.getString(0) else null
    }

    override fun updateTrackDuration(id: String, trackIndex: Int, durationMs: Long) {
        require(trackIndex >= 0 && durationMs > 0)
        writableDatabase.execSQL("UPDATE tracks SET duration_ms = ? WHERE book_id = ? AND position = ?",
            arrayOf<Any>(durationMs, id, trackIndex))
    }

    override fun setProgressMarker(id: String, positionMs: Long) {
        require(positionMs >= 0)
        writableDatabase.execSQL("UPDATE books SET high_water_mark_ms = ? WHERE id = ?", arrayOf<Any>(positionMs, id))
        LibraryContentChanges.committed()
    }

    override fun moments(bookId: String): List<LibraryMoment> = buildList {
        readableDatabase.query("moments", null, "book_id = ?", arrayOf(bookId), null, null, "created_at DESC, id ASC").use { r ->
            while (r.moveToNext()) add(LibraryMoment(r.text("id"), r.text("book_id"), r.long("track_index").toInt(),
                r.long("time_ms"), r.text("label"), r.text("notes"), r.text("categories_json"), r.optional("quote_line"),
                r.text("characters_json"), r.optional("mood"), r.long("created_at"), r.bool("is_pinned")))
        }
    }

    override fun saveMoment(moment: LibraryMoment) {
        require(moment.trackIndex >= 0 && moment.timeMs >= 0)
        val values = ContentValues().apply {
            put("is_pinned", moment.isPinned); put("id", moment.id); put("book_id", moment.bookId); put("track_index", moment.trackIndex)
            put("time_ms", moment.timeMs); put("label", moment.label); put("notes", moment.notes)
            put("categories_json", moment.categoriesJson); put("quote_line", moment.quoteLine)
            put("characters_json", moment.charactersJson); put("mood", moment.mood); put("created_at", moment.createdAt)
        }
        writableDatabase.transaction {
            if (update("moments", values, "id = ?", arrayOf(moment.id)) == 0) insertOrThrow("moments", null, values)
        }
    }

    override fun updateEqualizer(id: String, json: String) {
        writableDatabase.update("books", ContentValues().apply { put("equalizer_json", json) }, "id = ?", arrayOf(id))
    }

    override fun deleteMoment(id: String) { writableDatabase.delete("moments", "id = ?", arrayOf(id)) }
    override fun delete(id: String) {
        if (writableDatabase.delete("books", "id = ?", arrayOf(id)) > 0) LibraryContentChanges.committed()
    }
}

private fun Cursor.text(column: String): String = getString(getColumnIndexOrThrow(column))
private fun Cursor.optional(column: String): String? = getColumnIndexOrThrow(column).let { if (isNull(it)) null else getString(it) }
private fun Cursor.long(column: String): Long = getLong(getColumnIndexOrThrow(column))
private fun Cursor.optionalLong(column: String): Long? = getColumnIndexOrThrow(column).let { if (isNull(it)) null else getLong(it) }
private fun Cursor.bool(column: String): Boolean = long(column) != 0L
