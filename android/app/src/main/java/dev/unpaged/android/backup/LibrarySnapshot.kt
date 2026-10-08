package dev.unpaged.android.backup

import android.database.sqlite.SQLiteDatabase
import androidx.core.database.sqlite.transaction
import java.io.File
import java.io.IOException

/**
 * Consistent copy of the live library for Auto Backup. The app keeps running during a full
 * backup, so streaming `library.db` directly could tear if SQLite checkpoints mid-copy. The
 * snapshot is built inside one read transaction on the source and is the only database the
 * backup rules include. `VACUUM INTO` needs SQLite 3.27 (API 30); minSdk is 26, so copy
 * the schema and rows instead.
 */
internal object LibrarySnapshot {
    const val NAME = "library-backup.db"

    /** A library backup must never succeed with preferences alone when a live database exists. */
    fun prepare(live: File, snapshot: File, createSnapshot: (File, File) -> Unit = ::create,
        onFailure: (Int, Exception) -> Unit = { _, _ -> }) {
        if (!live.isFile) { delete(snapshot); return }
        var failure: Exception? = null
        for (attempt in 1..3) {
            try {
                createSnapshot(live, snapshot)
                return
            } catch (error: Exception) {
                failure = error
                onFailure(attempt, error)
            }
        }
        delete(snapshot)
        throw IOException("Could not snapshot the library for backup", failure)
    }

    fun create(live: File, snapshot: File) {
        delete(snapshot)
        SQLiteDatabase.openOrCreateDatabase(snapshot.path, null).use { target ->
            target.execSQL("ATTACH DATABASE ? AS src", arrayOf(live.path))
            val version = target.rawQuery("PRAGMA src.user_version", null).use { it.moveToFirst(); it.getInt(0) }
            target.transaction {
                val objects = target.rawQuery("SELECT type, name, sql FROM src.sqlite_master WHERE sql IS NOT NULL " +
                    "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, rowid", null).use { rows ->
                    buildList { while (rows.moveToNext()) add(Triple(rows.getString(0), rows.getString(1), rows.getString(2))) }
                }
                objects.forEach { (type, name, sql) ->
                    target.execSQL(sql)
                    if (type == "table") target.execSQL("INSERT INTO main.\"${name.replace("\"", "\"\"")}\" SELECT * FROM src.\"${name.replace("\"", "\"\"")}\"")
                }
            }
            target.execSQL("DETACH DATABASE src")
            target.execSQL("PRAGMA user_version = $version")
        }
        // A rollback journal never lingers after a clean close; remove any sidecar to be safe.
        File(snapshot.path + "-journal").delete()
    }

    /** Replaces the live database with a restored snapshot, discarding stale sidecar files. */
    fun install(snapshot: File, live: File) {
        if (!snapshot.isFile) return
        listOf("", "-wal", "-shm", "-journal").forEach { File(live.path + it).delete() }
        if (!snapshot.renameTo(live)) { snapshot.copyTo(live, overwrite = true); snapshot.delete() }
    }

    fun delete(snapshot: File) { listOf("", "-wal", "-shm", "-journal").forEach { File(snapshot.path + it).delete() } }
}
