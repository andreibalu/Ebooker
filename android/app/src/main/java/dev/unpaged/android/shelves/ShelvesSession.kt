package dev.unpaged.android.shelves

import androidx.core.content.edit
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import dev.unpaged.android.library.SQLiteLibraryStore
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.io.File
import androidx.work.*

data class DownloadEntry(val progress: Float = 0f, val error: String? = null, val complete: Boolean = false, val title: String = "", val currentTrack: Int = 0, val totalTracks: Int = 0, val workID: String = "")
data class ShelvesSessionState(val downloads: Map<String, DownloadEntry> = emptyMap(), val sampleId: String? = null,
    val sampleLoading: Boolean = false, val error: String? = null, val libraryRevision: Int = 0)

/** App-session UI owner observes durable unique work across navigation and relaunch. */
class ShelvesSession private constructor(private val context: android.app.Application) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val store = SQLiteLibraryStore(context)
    private val library = CatalogLibraryService(store)
    private val catalog = SQLiteCatalogStore(context)
    private val client = LibriVoxClient()
    private val dismissed = context.getSharedPreferences("dismissed-downloads", Context.MODE_PRIVATE)
    private val work = WorkManager.getInstance(context)
    private val mutable = MutableStateFlow(ShelvesSessionState())
    val state = mutable.asStateFlow()
    private val sampleAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val sampleFocus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        .setAudioAttributes(sampleAttributes).setOnAudioFocusChangeListener { if (it < 0) stopSample() }.build()
    private var sampleHasFocus = false
    private var sample: MediaPlayer? = null
    private var sampleJob: Job? = null
    private var sampleTimer: Job? = null
    private val downloadRoot = File(context.filesDir, "shelves-downloads")
    private val downloadUpdates = DownloadUpdates(catalog::title)
    init {
        scope.launch {
            work.getWorkInfosByTagFlow(LibriVoxDownloadWorker.TAG).collect { infos ->
                val update = withContext(Dispatchers.IO) { downloadUpdates.observe(infos) }
                val titles = update.titles
                val entries = infos.groupBy { info ->
                    info.tags.firstOrNull { it.startsWith(LibriVoxDownloadWorker.TAG + ":") }?.substringAfter(":")
                }.mapNotNull { (id, rows) ->
                    if (id == null) return@mapNotNull null
                    val active = rows.firstOrNull { !it.state.isFinished }
                    val chosen = active ?: rows.firstOrNull { it.state == WorkInfo.State.SUCCEEDED }
                        ?: rows.firstOrNull { it.state == WorkInfo.State.FAILED }
                    if (chosen == null || dismissed.getBoolean(chosen.id.toString(), false)) null else id to DownloadEntry(
                        chosen.progress.getInt(LibriVoxDownloadWorker.PROGRESS, 0) / 100f,
                        if (chosen.state == WorkInfo.State.FAILED) chosen.outputData.getString(LibriVoxDownloadWorker.ERROR) else null,
                        chosen.state == WorkInfo.State.SUCCEEDED, titles[id] ?: "Audiobook",
                        chosen.progress.getInt("track", 0), chosen.progress.getInt("total", 0), chosen.id.toString())
                }.toMap()
                mutable.update { it.copy(downloads = entries, libraryRevision = it.libraryRevision + if (update.finishedChanged) 1 else 0) }
            }
        }
    }
    fun connected(): Boolean {
        if (CatalogEnvironment.downloadFixture(context)) return true
        if (CatalogEnvironment.savedOnly(context)) return false
        val manager = context.getSystemService(ConnectivityManager::class.java)
        return manager.getNetworkCapabilities(manager.activeNetwork)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
    }
    private fun tracks(book: CatalogBook): List<CatalogTrack> {
        val cached = catalog.books().firstOrNull { it.id == book.id }?.tracks.orEmpty()
        if (cached.isNotEmpty()) return cached
        check(connected()) { "You're offline. Connect to download this book." }
        val tracks = client.tracks(book.id)
        catalog.seed(listOf(book.copy(tracks = tracks)))
        return tracks
    }
    fun identity(id: String) = library.identity(id)
    suspend fun add(book: CatalogBook) = withContext(Dispatchers.IO) {
        val prior = library.identity(book.id)
        val added = library.add(book, tracks(book))
        mutable.update { it.copy(libraryRevision = it.libraryRevision + if (prior == null) 1 else 0, downloads = if (!added.isDownloaded && it.downloads[book.id]?.complete == true) it.downloads - book.id else it.downloads) }
        added
    }
    fun dismissError() { mutable.update { it.copy(error = null) } }
    fun download(book: CatalogBook) {
        if (!connected()) { mutable.update { it.copy(error = "You're offline. Connect to download this book.") }; return }
        scope.launch {
            try {
                add(book)
                // Older finished rows must not resurface once this attempt is replaced or cancelled.
                withContext(Dispatchers.IO) {
                    val rows = work.getWorkInfosForUniqueWork(LibriVoxDownloadWorker.name(book.id)).get()
                    dismissed.edit { DownloadFailures.finishedIds(rows).forEach { putBoolean(it, true) } }
                }
                work.enqueueUniqueWork(LibriVoxDownloadWorker.name(book.id), ExistingWorkPolicy.KEEP,
                    LibriVoxDownloadWorker.request(book.id))
            } catch (error: Exception) {
                mutable.update { it.copy(error = error.message ?: "Couldn't download this book. Please try again.") }
            }
        }
    }
    fun dismissDownload(id: String) {
        state.value.downloads[id]?.let { dismissed.edit { putBoolean(it.workID, true) } }
        mutable.update { it.copy(downloads = it.downloads - id) }
    }
    fun retryDownload(id: String) {
        scope.launch {
            val book = withContext(Dispatchers.IO) { catalog.books().firstOrNull { it.id == id } }
            if (book != null) download(book)
        }
    }
    fun cancel(id: String) {
        scope.launch {
            withContext(Dispatchers.IO) {
                library.identity(id)?.let { row ->
                    val folder = File(downloadRoot, row.id)
                    if (folder.isDirectory) File(folder, ".cancelled").writeText("")
                }
            }
            work.cancelUniqueWork(LibriVoxDownloadWorker.name(id))
            mutable.update { it.copy(downloads = it.downloads - id) }
        }
    }
    fun stopSample() {
        sampleJob?.cancel(); sampleTimer?.cancel(); sample?.release(); sample = null
        if (sampleHasFocus) { audioManager.abandonAudioFocusRequest(sampleFocus); sampleHasFocus = false }
        mutable.update { it.copy(sampleId = null, sampleLoading = false) }
    }
    fun sample(book: CatalogBook) {
        if (state.value.sampleId == book.id) { stopSample(); return }
        stopSample()
        if (!connected()) return
        mutable.update { it.copy(sampleId = book.id, sampleLoading = true) }
        sampleJob = scope.launch {
            try {
                val first = withContext(Dispatchers.IO) { tracks(book).firstOrNull() } ?: error("No sample available.")
                ensureActive()
                val player = MediaPlayer(); sample = player
                player.setAudioAttributes(sampleAttributes)
                player.setOnErrorListener { _, _, _ -> stopSample(); mutable.update { it.copy(error = "Couldn't play this sample. Please try again.") }; true }
                player.setOnCompletionListener { stopSample() }
                player.setOnPreparedListener {
                    if (sample !== it) return@setOnPreparedListener
                    runCatching { it.seekTo(30_000L, MediaPlayer.SEEK_CLOSEST) }.onFailure {
                        stopSample(); mutable.update { state -> state.copy(error = "Couldn't play this sample. Please try again.") }
                    }
                }
                player.setOnSeekCompleteListener {
                    if (sample !== it) return@setOnSeekCompleteListener
                    sampleHasFocus = audioManager.requestAudioFocus(sampleFocus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
                    if (!sampleHasFocus) { stopSample(); return@setOnSeekCompleteListener }
                    runCatching {
                        it.start(); mutable.update { state -> state.copy(sampleLoading = false) }
                        sampleTimer = scope.launch { delay(20_000); stopSample() }
                    }.onFailure {
                        stopSample(); mutable.update { state -> state.copy(error = "Couldn't play this sample. Please try again.") }
                    }
                }
                player.setDataSource(first.url); player.prepareAsync()
            } catch (cancel: CancellationException) { throw cancel }
            catch (error: Exception) { stopSample(); mutable.update { it.copy(error = error.message ?: "Couldn't play this sample.") } }
        }
    }
    companion object {
        @Volatile private var instance: ShelvesSession? = null
        fun get(context: Context): ShelvesSession = instance ?: synchronized(this) {
            instance ?: ShelvesSession(context.applicationContext as android.app.Application).also { instance = it }
        }
    }
}

/** Progress emissions reuse titles and invalidate the library only on finished-work changes. */
internal class DownloadUpdates(private val title: (String) -> String?) {
    private val titles = mutableMapOf<String, String>()
    private var finished = emptyMap<java.util.UUID, WorkInfo.State>()
    data class Update(val titles: Map<String, String>, val finishedChanged: Boolean)
    fun observe(infos: List<WorkInfo>): Update {
        val ids = infos.mapNotNull { info ->
            info.tags.firstOrNull { it.startsWith(LibriVoxDownloadWorker.TAG + ":") }?.substringAfter(":")
        }.toSet()
        titles.keys.retainAll(ids)
        ids.forEach { id -> if (id !in titles) titles[id] = title(id) ?: "Audiobook" }
        val next = infos.filter { it.state.isFinished }.associate { it.id to it.state }
        val changed = next != finished
        finished = next
        return Update(titles.toMap(), changed)
    }
}
