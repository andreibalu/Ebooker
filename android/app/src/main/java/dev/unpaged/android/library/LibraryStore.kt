package dev.unpaged.android.library

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import androidx.core.database.sqlite.transaction

interface LibraryStore {
    fun books(): List<LibraryBook>
    fun insert(book: LibraryBook)
    fun delete(id: String)
}

/** Versioned, private SQLite store. File ownership stays in LocalLibraryRepository. */
class SQLiteLibraryStore(context: Context) : SQLiteOpenHelper(context, "library.db", null, 1), LibraryStore {
    override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true) }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE books (id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL)")
        db.execSQL("""CREATE TABLE tracks (book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            position INTEGER NOT NULL, title TEXT NOT NULL, original_name TEXT NOT NULL,
            stored_name TEXT NOT NULL, duration_ms INTEGER NOT NULL, fingerprint TEXT NOT NULL,
            PRIMARY KEY(book_id, position))""")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        error("Library migration required from $oldVersion to $newVersion")
    }

    override fun books(): List<LibraryBook> {
        val result = mutableListOf<LibraryBook>()
        readableDatabase.query("books", null, null, null, null, null, "rowid DESC").use { rows ->
            while (rows.moveToNext()) {
                val id = rows.getString(rows.getColumnIndexOrThrow("id"))
                val tracks = mutableListOf<LibraryTrack>()
                readableDatabase.query("tracks", null, "book_id = ?", arrayOf(id), null, null, "position ASC").use { t ->
                    while (t.moveToNext()) {
                        fun text(column: String) = t.getString(t.getColumnIndexOrThrow(column))
                        tracks += LibraryTrack(text("title"), text("original_name"), text("stored_name"),
                            t.getLong(t.getColumnIndexOrThrow("duration_ms")), text("fingerprint"))
                    }
                }
                result += LibraryBook(id, rows.getString(rows.getColumnIndexOrThrow("title")),
                    rows.getString(rows.getColumnIndexOrThrow("author")), tracks)
            }
        }
        return result
    }

    override fun insert(book: LibraryBook) {
        val db = writableDatabase
        db.transaction {
            db.insertOrThrow("books", null, ContentValues().apply {
                put("id", book.id); put("title", book.title); put("author", book.author)
            })
            book.tracks.forEachIndexed { index, track ->
                db.insertOrThrow("tracks", null, ContentValues().apply {
                    put("book_id", book.id); put("position", index); put("title", track.title)
                    put("original_name", track.originalName); put("stored_name", track.storedName)
                    put("duration_ms", track.durationMs); put("fingerprint", track.fingerprint)
                })
            }
        }
    }

    override fun delete(id: String) { writableDatabase.delete("books", "id = ?", arrayOf(id)) }
}
