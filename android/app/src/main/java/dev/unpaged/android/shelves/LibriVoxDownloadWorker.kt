package dev.unpaged.android.shelves

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.*
import dev.unpaged.android.R
import dev.unpaged.android.library.SQLiteLibraryStore
import kotlinx.coroutines.*
import java.io.File
import java.util.concurrent.TimeUnit

class LibriVoxDownloadWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val catalogID = inputData.getString(KEY) ?: return@withContext Result.failure()
        val store = SQLiteLibraryStore(applicationContext)
        var folder: File? = null
        try {
            val library = CatalogLibraryService(store)
            val row = library.identity(catalogID) ?: return@withContext Result.failure(workDataOf(ERROR to "This book was removed from your library."))
            if (row.isDownloaded) return@withContext Result.success()
            foreground(notification(row.title, 0))
            val staging = File(applicationContext.filesDir, "shelves-downloads/${row.id}")
            folder = staging
            check(staging.mkdirs() || staging.isDirectory)
            val cancelled = File(staging, ".cancelled")
            if (cancelled.exists()) { staging.deleteRecursively(); check(staging.mkdirs()) }
            val final = File(applicationContext.filesDir, "audiobooks/${row.id}")
            val owned = row.tracks.mapIndexed { index, track ->
                val name = "%04d.mp3".format(java.util.Locale.ROOT, index)
                val destination = if (File(final, name).isFile) File(final, name) else File(staging, name)
                // Complete tracks and the rename-before-index crash window are recoverable.
                if (!destination.isFile) {
                    require(CatalogEnvironment.permitsAudio(track.remoteUrl ?: ""))
                    val partial = File(staging, "$name.part")
                    var lastUpdate = 0L
                    val job = currentCoroutineContext()
                    ResumableFile.copy(track.remoteUrl ?: error("No audio URL is available."), partial,
                        { job.ensureActive(); check(!cancelled.exists()) { "Download cancelled." } }) { bytes, total ->
                        val now = android.os.SystemClock.elapsedRealtime()
                        if (now - lastUpdate >= 500 || bytes == total) {
                            lastUpdate = now
                            val fraction = if (total > 0) (bytes.toFloat() / total).coerceIn(0f, 1f) else 0f
                            val percent = ((index + fraction) * 100 / row.tracks.size).toInt()
                            runBlocking {
                                setProgress(workDataOf(PROGRESS to percent, "track" to (index + 1), "total" to row.tracks.size))
                                foreground(notification(row.title, percent))
                            }
                        }
                    }
                    currentCoroutineContext().ensureActive()
                    check(partial.renameTo(destination)) { "Couldn't save the download." }
                    File(partial.path + ".validator").delete()
                }
                track.copy(storedName = name)
            }
            currentCoroutineContext().ensureActive()
            withContext(NonCancellable) {
                check(!File(staging, ".cancelled").exists()) { "Download cancelled." }
                DownloadFiles.finish(staging, final, owned.map { it.storedName })
                library.promote(row.id, owned, final.walkTopDown().filter { it.isFile }.sumOf { it.length() })
            }
            Result.success()
        } catch (cancel: CancellationException) { throw cancel }
        catch (error: Exception) {
            if (DownloadFailures.retryable(error) && runAttemptCount < 4) Result.retry()
            else Result.failure(workDataOf(ERROR to (error.message ?: "Couldn't download this book. Please try again.")))
        } finally {
            if (folder?.let { File(it, ".cancelled").exists() } == true ||
                runCatching { WorkManager.getInstance(applicationContext).getWorkInfoById(id).get()?.state == WorkInfo.State.CANCELLED }.getOrDefault(false)) folder?.deleteRecursively()
            store.close()
        }
    }

    /** Android 12+ refuses foreground starts from a background retry; the download itself continues. */
    private var foregroundAllowed = true
    private suspend fun foreground(info: ForegroundInfo) {
        if (!foregroundAllowed) return
        try { setForeground(info) }
        catch (cancel: CancellationException) { throw cancel }
        catch (_: Exception) { foregroundAllowed = false }
    }

    private fun notification(title: String, percent: Int): ForegroundInfo {
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Audiobook downloads", NotificationManager.IMPORTANCE_LOW))
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL)
            .setSmallIcon(R.drawable.ic_download).setContentTitle(title)
            .setContentText("Downloading · $percent%").setProgress(100, percent, false)
            .setOngoing(true).setOnlyAlertOnce(true)
            .addAction(0, "Cancel", WorkManager.getInstance(applicationContext).createCancelPendingIntent(id))
            .build()
        return if (Build.VERSION.SDK_INT >= 29)
            ForegroundInfo(id.hashCode(), notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else ForegroundInfo(id.hashCode(), notification)
    }
    companion object {
        const val KEY = "catalog"
        const val ERROR = "error"
        const val PROGRESS = "progress"
        const val TAG = "librivox-download"
        private const val CHANNEL = "audiobook-downloads"
        fun name(id: String) = "$TAG:$id"
        fun request(id: String) = OneTimeWorkRequestBuilder<LibriVoxDownloadWorker>()
            .setInputData(workDataOf(KEY to id)).addTag(TAG).addTag(name(id))
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS).build()
    }
}

/** Only transient I/O failures are worth another attempt; logic errors and bad input would fail identically. */
internal object DownloadFailures {
    fun retryable(error: Throwable) = error is java.io.IOException
    fun finishedIds(rows: List<WorkInfo>) = rows.filter { it.state.isFinished }.map { it.id.toString() }
}

/** Merge only audio tracks: a cover edit may have created the final folder mid-download. */
internal object DownloadFiles {
    fun finish(staging: File, final: File, names: List<String>) {
        check(final.mkdirs() || final.isDirectory) { "Couldn't save the download." }
        names.forEach { name ->
            val source = File(staging, name)
            val target = File(final, name)
            if (source.isFile) check(source.renameTo(target)) { "Couldn't save the download." }
        }
        check(names.all { File(final, it).isFile }) { "A downloaded track is missing." }
    }
}
