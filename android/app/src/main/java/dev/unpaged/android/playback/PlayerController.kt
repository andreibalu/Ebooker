package dev.unpaged.android.playback

import android.content.ComponentName
import android.content.Context
import android.app.Application
import androidx.core.net.toUri
import dev.unpaged.android.UnpagedApplication
import android.os.SystemClock
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import androidx.core.content.ContextCompat
import dev.unpaged.android.UnpagedPreferences
import dev.unpaged.android.library.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.util.UUID
import dev.unpaged.android.equalizer.*

/** Shared with the service: state and commands always operate on the session's sole engine. */
data class PlayerState(
    val book: LibraryBook? = null, val playing: Boolean = false, val loading: Boolean = false,
    val trackIndex: Int = 0, val positionMs: Long = 0, val speed: Float = 1f,
    val chapters: List<PlaybackChapter> = emptyList(), val sleepRemainingMs: Long? = null,
    val error: String? = null, val revision: Int = 0,
) {
    val durationMs get() = book?.tracks?.getOrNull(trackIndex)?.durationMs ?: 0L
    val chapterIndex get() = PlaybackRules.chapterIndex(chapters, trackIndex, positionMs)
    val canPrevious get() = PlaybackRules.previous(chapters, trackIndex, positionMs) != null
    val canNext get() = chapterIndex + 1 < chapters.size
}

@androidx.annotation.OptIn(UnstableApi::class)
class PlayerController internal constructor(private val context: Application) {
    companion object {
        fun get(context: Context): PlayerController = (context.applicationContext as UnpagedApplication).player
    }
    val equalizerProcessor = EqualizerAudioProcessor()
    private val mutableEqualizer = MutableStateFlow(EqualizerConfiguration())
    val equalizer = mutableEqualizer.asStateFlow()
    fun setEqualizer(value: EqualizerConfiguration) {
        val book = state.value.book ?: return
        val config = value.normalized()
        mutableEqualizer.value = config
        equalizerProcessor.configuration = config
        val json = config.json()
        mutableState.value = state.value.copy(book = book.copy(equalizerJson = json))
        writes.trySend { store.updateEqualizer(book.id, json) }
    }

    val preferences = UnpagedPreferences(context)
    private val store = SQLiteLibraryStore(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val writes = Channel<() -> Unit>(Channel.UNLIMITED)
    private val mutableState = MutableStateFlow(PlayerState())
    val state = mutableState.asStateFlow()
    private val resume = ResumePolicy()
    private val rules = PlaybackPersistenceRules(SystemClock::elapsedRealtime)
    private var player: Player? = null
    private var connection: com.google.common.util.concurrent.ListenableFuture<MediaController>? = null
    private var pending: (() -> Unit)? = null
    private var ticker: Job? = null
    private var loadJob: Job? = null
    private val markers = mutableMapOf<Int, List<ChapterMarker>>()
    private var replacing = false
    private var preservingSkipTarget: Pair<Int, Long>? = null

    init {
        scope.launch(Dispatchers.IO) {
            for (write in writes) {
                try { write(); withContext(Dispatchers.Main) { mutableState.value = state.value.copy(revision = state.value.revision + 1) } }
                catch (_: Exception) { withContext(Dispatchers.Main) { mutableState.value = state.value.copy(error = "Could not save playback progress. Please try again.") } }
            }
        }
    }
    fun connect() {
        if (connection != null) return
        val future = MediaController.Builder(context, SessionToken(context, ComponentName(context, PlaybackService::class.java))).buildAsync()
        connection = future
        future.addListener({
            try { future.get() } catch (_: Exception) {
                connection = null
                mutableState.value = state.value.copy(error = "Playback could not start. Please try again.", loading = false)
            }
        }, ContextCompat.getMainExecutor(context))
    }
    fun attach(engine: Player) {
        player = engine
        engine.addListener(listener)
        ticker?.cancel()
        ticker = scope.launch {
            while (isActive) {
                delay(1000)
                rules.tick(engine.isPlaying)
                if (rules.expireSleep()) engine.pause()
                update()
                persist(false)
            }
        }
        pending?.also { pending = null; it() }
    }
    fun detach() {
        update(); persist(true); ticker?.cancel(); player?.removeListener(listener)
        player = null
        connection?.let(MediaController::releaseFuture); connection = null
        mutableState.value = PlayerState(revision = state.value.revision + 1)
    }

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            if (replacing) return
            update()
            if (events.contains(Player.EVENT_IS_PLAYING_CHANGED) || events.contains(Player.EVENT_MEDIA_ITEM_TRANSITION)
                || events.contains(Player.EVENT_PLAYBACK_STATE_CHANGED) || events.contains(Player.EVENT_PLAYBACK_PARAMETERS_CHANGED)
                || events.contains(Player.EVENT_POSITION_DISCONTINUITY)) persist(true)
        }
        override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
            if (replacing) return
            if (reason == Player.DISCONTINUITY_REASON_SEEK) {
                val preserving = preservingSkipTarget
                preservingSkipTarget = null
                if (preserving != null && preserving.first == newPosition.mediaItemIndex
                    && kotlin.math.abs(preserving.second - newPosition.positionMs) <= 250) rules.mark() else rules.seek()
            } else if (reason == Player.DISCONTINUITY_REASON_AUTO_TRANSITION) rules.seek()
        }
        override fun onTracksChanged(tracks: androidx.media3.common.Tracks) {
            val index = player?.currentMediaItemIndex ?: return
            val found = mutableListOf<ChapterMarker>()
            for (group in tracks.groups) for (i in 0 until group.length) {
                val metadata = group.getTrackFormat(i).metadata ?: continue
                for (m in 0 until metadata.length()) {
                    val entry = metadata[m]
                    if (entry is androidx.media3.extractor.metadata.id3.ChapterFrame) {
                        val title = (0 until entry.subFrameCount).map { entry.getSubFrame(it) }
                            .filterIsInstance<androidx.media3.extractor.metadata.id3.TextInformationFrame>()
                            .firstOrNull { it.id == "TIT2" }?.values?.firstOrNull().orEmpty()
                        found += ChapterMarker(title, entry.startTimeMs.toLong(), entry.endTimeMs.toLong())
                    }
                }
            }
            if (found.isNotEmpty()) { markers[index] = found; update() }
        }
        override fun onPlayerError(error: PlaybackException) {
            mutableState.value = state.value.copy(error = "This audiobook could not be played. Check the file or network connection.", loading = false)
        }
    }

    fun play(book: LibraryBook, track: Int? = null) {
        connect()
        loadJob?.cancel()
        pending = null
        loadJob = scope.launch {
            // Serialize behind pending writes before reading the latest durable position.
            val ready = CompletableDeferred<LibraryBook?>()
            writes.send { try { ready.complete(store.books().firstOrNull { it.id == book.id }) } catch (error: Exception) { ready.completeExceptionally(error); throw error } }
            val fresh = try { ready.await() } catch (_: Exception) { return@launch } ?: return@launch
            val target = track?.let { it to 0L } ?: resume.start(fresh, preferences.seconds("resumeBacktrackSeconds", 60))
            val action = { load(fresh, target.first, target.second) }
            if (player == null) { pending = action; mutableState.value = state.value.copy(loading = true) } else action()
        }
    }
    private fun load(book: LibraryBook, track: Int, position: Long) {
        val engine = player ?: return
        if (book.tracks.isEmpty()) return
        persist(true)
        markers.clear()
        preservingSkipTarget = null
        rules.load()
        val eq = EqualizerConfiguration.decode(book.equalizerJson)
        mutableEqualizer.value = eq
        equalizerProcessor.configuration = eq
        val artwork = GeneratedArtwork.png(book.title)
        val items = book.tracks.mapIndexed { index, file ->
            val uri = if (file.storedName.isNotEmpty()) android.net.Uri.fromFile(File(context.filesDir, "audiobooks/${book.id}/${file.storedName}"))
                else (file.remoteUrl ?: "").toUri()
            MediaItem.Builder().setMediaId("${book.id}:$index").setUri(uri)
                .setMediaMetadata(MediaMetadata.Builder().setTitle(PlaybackRules.title(book, index))
                    .setAlbumTitle(book.title).setArtist(book.author).setArtworkData(artwork, MediaMetadata.PICTURE_TYPE_FRONT_COVER).build()).build()
        }
        mutableState.value = state.value.copy(book = book, error = null, chapters = PlaybackRules.chapters(book))
        replacing = true
        engine.setMediaItems(items, track.coerceIn(book.tracks.indices), position.coerceAtLeast(0))
        engine.setPlaybackSpeed(book.playbackSpeed.toFloat().takeIf { it in PlaybackRules.speeds } ?: 1f)
        engine.prepare()
        engine.play()
        replacing = false
        update(); persist(true)
    }
    private fun update() {
        val engine = player ?: return
        var book = state.value.book ?: return
        val index = engine.currentMediaItemIndex.coerceIn(book.tracks.indices)
        if (book.tracks[index].durationMs <= 0 && engine.duration > 0) {
            val duration = engine.duration.coerceAtMost(1_000_000_000L)
            val id = book.id
            book = book.copy(tracks = book.tracks.mapIndexed { i, track -> if (i == index) track.copy(durationMs = duration) else track })
            writes.trySend { store.updateTrackDuration(id, index, duration) }
        }
        val position = if (engine.playbackState == Player.STATE_ENDED) book.tracks[index].durationMs else engine.currentPosition.coerceIn(0, book.tracks[index].durationMs.takeIf { it > 0 } ?: 1_000_000_000L)
        val overall = book.tracks.take(index).sumOf { it.durationMs } + position
        val finished = engine.playbackState == Player.STATE_ENDED
        val high = if (finished) book.durationMs else rules.highWater(book.highWaterMarkMs, overall)
        mutableState.value = state.value.copy(book = book.copy(currentTrackIndex = index, currentPositionMs = position,
            highWaterMarkMs = high, playbackSpeed = engine.playbackParameters.speed.toDouble(), isFinished = finished,
            lastPlayedAt = if (engine.isPlaying) System.currentTimeMillis() else book.lastPlayedAt),
            trackIndex = index, positionMs = position, playing = engine.isPlaying, loading = engine.playbackState == Player.STATE_BUFFERING,
            speed = engine.playbackParameters.speed, chapters = PlaybackRules.chapters(book, markers), sleepRemainingMs = rules.sleepRemaining())
    }
    private fun persist(force: Boolean) {
        val s = state.value
        val book = s.book ?: return
        val progress = PlaybackProgress(s.trackIndex, s.positionMs, book.highWaterMarkMs, s.speed.toDouble(), book.isFinished)
        if (!rules.shouldPersist(progress, force)) return
        writes.trySend { store.updatePlaybackProgress(book.id, progress) }
        rules.didPersist(progress)
    }
    fun background() { update(); persist(true) }
    fun toggle() { player?.let { if (it.playWhenReady) it.pause() else { if (it.playbackState == Player.STATE_IDLE) it.prepare(); it.play() } } }
    fun seek(position: Long, penalize: Boolean = true) {
        if (state.value.durationMs <= 0) return
        val bounded = position.coerceIn(0, state.value.durationMs)
        preservingSkipTarget = if (!penalize) state.value.trackIndex to bounded else null
        if (penalize) rules.seek()
        player?.seekTo(bounded)
        // ExoPlayer seek callbacks apply a penalty. Skips while saving preserve that state.
        if (!penalize) rules.mark()
        update(); persist(true)
    }
    fun skip(forward: Boolean) {
        val s = state.value; val book = s.book ?: return
        if (s.durationMs <= 0) return
        val preserving = rules.penaltyRemainingMs == 0L
        if (forward) {
            val target = PlaybackRules.skipForward(book, s.trackIndex, s.positionMs, preferences.seconds("skipForwardSeconds", 30))
            if (target.first != s.trackIndex) navigate(target.first, target.second, false)
            else seek(target.second, !preserving)
        } else seek(PlaybackRules.skipBackward(s.positionMs, preferences.seconds("skipBackSeconds", 30)), !preserving)
    }
    fun previous() { val s = state.value; PlaybackRules.previous(s.chapters, s.trackIndex, s.positionMs)?.let { chapter(it.index, false) } }
    fun next() { if (state.value.canNext) chapter(state.value.chapterIndex + 1, false) }
    fun chapter(index: Int, autoplay: Boolean = true) { state.value.chapters.getOrNull(index)?.let { navigate(it.trackIndex, it.startMs, autoplay) } }
    private fun navigate(track: Int, position: Long, autoplay: Boolean) {
        val engine = player ?: return
        val changed = track != engine.currentMediaItemIndex
        preservingSkipTarget = null
        rules.seek(); engine.seekTo(track, position)
        if (changed || autoplay) engine.play()
        update(); persist(true)
    }
    fun speed(value: Float) { player?.setPlaybackSpeed(PlaybackRules.speed(value)); update(); persist(true) }
    fun sleep(minutes: Int?) { rules.sleep(minutes); update() }
    fun markProgress() {
        rules.mark()
        val book = state.value.book ?: return
        val overall = book.globalPositionMs
        mutableState.value = state.value.copy(book = book.copy(highWaterMarkMs = overall))
        writes.trySend { store.setProgressMarker(book.id, overall) }
        persist(true)
    }
    fun draftMoment(): LibraryMoment? {
        update()
        val s = state.value; val book = s.book ?: return null
        val time = PlaybackRules.momentTime(s.positionMs, preferences.seconds("momentBacktrackSeconds", 0))
        return LibraryMoment(UUID.randomUUID().toString(), book.id, s.trackIndex, time, "Saved Moment")
    }
    fun saveMoment(moment: LibraryMoment) { writes.trySend { store.saveMoment(moment) } }
    fun playMoment(book: LibraryBook, moment: LibraryMoment) {
        connect(); loadJob?.cancel(); pending = null
        val action = { load(book, moment.trackIndex, moment.timeMs) }
        if (player == null) { pending = action; mutableState.value = state.value.copy(loading = true) } else action()
    }
    fun removed(id: String) {
        if (state.value.book?.id != id) return
        loadJob?.cancel(); pending = null
        replacing = true; player?.stop(); player?.clearMediaItems(); replacing = false
        mutableState.value = PlayerState(revision = state.value.revision + 1)
    }
    fun dismissError() { mutableState.value = state.value.copy(error = null) }
}
