package dev.unpaged.android.backup

import android.app.backup.BackupAgent
import android.app.backup.BackupDataInput
import android.app.backup.BackupDataOutput
import android.app.backup.FullBackupDataOutput
import android.database.sqlite.SQLiteDatabase
import android.os.ParcelFileDescriptor
import dev.unpaged.android.UnpagedPreferences

/** Full-file backup only. The OS stops normal app writes before invoking this agent. */
class LibraryBackupAgent : BackupAgent() {
    override fun onBackup(oldState: ParcelFileDescriptor?, data: BackupDataOutput, newState: ParcelFileDescriptor) = Unit
    override fun onRestore(data: BackupDataInput, appVersionCode: Int, newState: ParcelFileDescriptor) = Unit

    override fun onFullBackup(data: FullBackupDataOutput) {
        if (!UnpagedPreferences(this).backupEnabled()) return
        val file = getDatabasePath("library.db")
        if (file.isFile) {
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
                db.rawQuery("PRAGMA wal_checkpoint(FULL)", null).use { result ->
                    check(result.moveToFirst() && result.getInt(0) == 0) { "Library checkpoint is busy" }
                }
            }
        }
        // XML allowlists contain only library.db and unpaged.xml. Never send owned audio,
        // catalog, caches or Keystore-bound credentials. noBackupFilesDir is platform-excluded.
        super.onFullBackup(data)
    }
}
