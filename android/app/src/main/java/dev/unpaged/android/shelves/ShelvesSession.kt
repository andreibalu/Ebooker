package dev.unpaged.android.shelves

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
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URI

data class DownloadEntry(val progress: Float = 0f, val error: String? = null, val complete: Boolean = false)
data class ShelvesSessionState(val downloads: Map<String, DownloadEntry> = emptyMap(), val sampleId: String? = null,
    val sampleLoading: Boolean = false, val error: String? = null, val libraryRevision: Int = 0)

/** App-session ownership: navigation never cancels downloads; process death leaves a streaming row. */
class ShelvesSession private constructor(private val context: android.app.Application) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val store = SQLiteLibraryStore(context)
    private val library = CatalogLibraryService(store)
    private val catalog = SQLiteCatalogStore(context)
    private val client = LibriVoxClient()
    private val jobs = mutableMapOf<String, Job>()
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
    private val cleanup = scope.async(Dispatchers.IO) { downloadRoot.listFiles()?.forEach { it.deleteRecursively() } }
    fun connected(): Boolean {
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
        val added = library.add(book, tracks(book))
        mutable.update { it.copy(libraryRevision = it.libraryRevision + 1, downloads = if (!added.isDownloaded && it.downloads[book.id]?.complete == true) it.downloads - book.id else it.downloads) }
        added
    }
    fun dismissError() { mutable.update { it.copy(error = null) } }
    fun download(book: CatalogBook) {
        if (jobs[book.id]?.isActive == true) return
        if (!connected()) { mutable.update { it.copy(error = "You're offline. Connect to download this book.") }; return }
        jobs[book.id] = scope.launch {
            updateDownload(book.id, DownloadEntry())
            var temp: File? = null
            var destination: File? = null
            var committed = false
            try {
                cleanup.await()
                withContext(Dispatchers.IO) {
                    val tracks = tracks(book)
                    val row = library.add(book, tracks)
                    mutable.update { it.copy(libraryRevision = it.libraryRevision + 1) }
                    if (row.isDownloaded) { committed = true; return@withContext }
                    val folder = File(downloadRoot, row.id); temp = folder
                    check(folder.mkdirs() || folder.isDirectory)
                    val owned = tracks.mapIndexed { index, track ->
                        currentCoroutineContext().ensureActive()
                        require(URI(track.url).scheme == "https")
                        val connection = URI(track.url).toURL().openConnection() as HttpURLConnection
                        connection.connectTimeout = 15_000; connection.readTimeout = 15_000
                        val name = "%04d.mp3".format(java.util.Locale.ROOT, index)
                        val file = File(folder, name)
                        try {
                            if (connection.responseCode !in 200..299) throw FeedProblem(connection.responseCode)
                            val length = connection.contentLengthLong
                            var copied = 0L
                            connection.inputStream.use { input -> FileOutputStream(file).use { output ->
                                val buffer = ByteArray(64 * 1024)
                                while (true) {
                                    currentCoroutineContext().ensureActive()
                                    val count = input.read(buffer); if (count < 0) break
                                    output.write(buffer, 0, count); copied += count
                                    val fraction = if (length > 0) (copied.toFloat() / length).coerceIn(0f, 1f) else 0f
                                    updateDownload(book.id, DownloadEntry((index + fraction) / tracks.size))
                                }
                                output.fd.sync()
                            } }
                            check(file.length() > 0 && (length <= 0 || file.length() == length)) { "The download was incomplete. Please try again." }
                        } finally { connection.disconnect() }
                        row.tracks[index].copy(storedName = name)
                    }
                    currentCoroutineContext().ensureActive()
                    // Short filesystem/index hand-off finishes atomically with respect to cancellation.
                    withContext(NonCancellable) {
                        val final = File(File(context.filesDir, "audiobooks"), row.id); destination = final
                        check(final.parentFile!!.mkdirs() || final.parentFile!!.isDirectory)
                        check(!final.exists() && folder.renameTo(final)) { "Couldn't save the download." }
                        library.promote(row.id, owned, final.walkTopDown().filter { it.isFile }.sumOf { it.length() })
                        committed = true
                    }
                }
                updateDownload(book.id, DownloadEntry(1f, complete = true))
            } catch (_: CancellationException) { mutable.update { it.copy(downloads = it.downloads - book.id) } }
            catch (error: Exception) { updateDownload(book.id, DownloadEntry(error = error.message ?: "Couldn't download this book. Please try again.")) }
            finally {
                withContext(Dispatchers.IO + NonCancellable) { temp?.deleteRecursively(); if (!committed) destination?.deleteRecursively() }
                mutable.update { it.copy(libraryRevision = it.libraryRevision + 1) }
            }
        }
    }
    private fun updateDownload(id: String, entry: DownloadEntry) { mutable.update { it.copy(downloads = it.downloads + (id to entry)) } }
    fun retryDownload(id: String) {
        scope.launch {
            val book = withContext(Dispatchers.IO) { catalog.books().firstOrNull { it.id == id } }
            if (book != null) download(book)
        }
    }
    fun cancel(id: String) { jobs[id]?.cancel() }
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
