package dev.unpaged.android.backup

import android.app.backup.BackupAgent
import android.app.backup.BackupDataInput
import android.app.backup.BackupDataOutput
import android.app.backup.FullBackupDataOutput
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import dev.unpaged.android.UnpagedPreferences

/**
 * Full-file backup only. The app process stays live during a full backup, so the live
 * `library.db` is never streamed. A consistent snapshot named [LibrarySnapshot.NAME] is the
 * only database the XML rules include; [onRestoreFinished] moves it into place before the app
 * opens the library.
 */
class LibraryBackupAgent : BackupAgent() {
    override fun onBackup(oldState: ParcelFileDescriptor?, data: BackupDataOutput, newState: ParcelFileDescriptor) = Unit
    override fun onRestore(data: BackupDataInput, appVersionCode: Int, newState: ParcelFileDescriptor) = Unit

    override fun onFullBackup(data: FullBackupDataOutput) {
        // The toggle gates cloud backup only. Device-to-device transfer (API 28+) is the user
        // moving their own phone, so it proceeds regardless.
        val deviceTransfer = Build.VERSION.SDK_INT >= 28 && data.transportFlags and FLAG_DEVICE_TO_DEVICE_TRANSFER != 0
        if (!UnpagedPreferences(this).backupEnabled() && !deviceTransfer) return
        val live = getDatabasePath("library.db")
        val snapshot = getDatabasePath(LibrarySnapshot.NAME)
        LibrarySnapshot.prepare(live, snapshot) { attempt, error ->
            Log.w("LibraryBackupAgent", "Library snapshot attempt $attempt failed", error)
            Thread.sleep(250L * attempt)
        }
        // XML allowlists contain only the snapshot and unpaged.xml. Never send owned audio,
        // catalog, caches or Keystore-bound credentials. noBackupFilesDir is platform-excluded.
        try { super.onFullBackup(data) } finally { LibrarySnapshot.delete(snapshot) }
    }

    override fun onRestoreFinished() {
        LibrarySnapshot.install(getDatabasePath(LibrarySnapshot.NAME), getDatabasePath("library.db"))
        super.onRestoreFinished()
    }
}
