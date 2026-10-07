package dev.unpaged.android.playback

import dev.unpaged.android.library.LibraryBook
import dev.unpaged.android.library.PlaybackProgress

/** Pure iOS PlaybackChapterList rules; milliseconds are used at the Android boundary. */
data class ChapterMarker(val title: String, val startMs: Long, val endMs: Long)
data class PlaybackChapter(val index: Int, val title: String, val trackIndex: Int, val startMs: Long, val durationMs: Long)

object PlaybackRules {
    val speeds = listOf(.8f, 1f, 1.25f, 1.5f, 1.75f, 2f)
    val sleepMinutes = listOf(5, 15, 30, 60)
    fun title(book: LibraryBook, index: Int) = if (book.tracks.size == 1 && book.title.isNotBlank()) book.title.trim()
        else book.tracks.getOrNull(index)?.title.orEmpty()
    fun miniSecondary(book: LibraryBook, index: Int): String? = book.tracks.getOrNull(index)?.title?.trim()
        ?.takeIf { book.tracks.size > 1 && it.isNotEmpty() && it != book.title.trim() }
    private fun absChapters(book: LibraryBook): List<PlaybackChapter> = runCatching {
        val array = org.json.JSONArray(book.absChaptersJson ?: "[]")
        val ordered = (0 until array.length()).map { array.getJSONObject(it) }
            .filter { it.getLong("start") >= 0 && it.getLong("start") < book.durationMs - 500 }
            .sortedBy { it.getLong("start") }.fold(mutableListOf<org.json.JSONObject>()) { acc, chapter ->
                if (acc.isEmpty() || chapter.getLong("start") - acc.last().getLong("start") >= 500) acc.add(chapter)
                acc
            }
        if (ordered.size < 2) return emptyList()
        ordered.mapIndexed { index, chapter ->
            val start = if (index == 0) 0 else chapter.getLong("start")
            var position = dev.unpaged.android.abs.ABSRules.position(start, book.tracks.map { it.durationMs })
            if (position.first < book.tracks.lastIndex && book.tracks[position.first].durationMs - position.second < 500) position = position.first + 1 to 0L
            PlaybackChapter(index, chapter.optString("title").trim().ifBlank { "Chapter ${index + 1}" }, position.first, position.second,
                ((ordered.getOrNull(index + 1)?.getLong("start") ?: chapter.getLong("end")) - start).coerceAtLeast(0))
        }
    }.getOrDefault(emptyList())
    fun chapters(book: LibraryBook, markers: Map<Int, List<ChapterMarker>> = emptyMap()): List<PlaybackChapter> = buildList {
        val abs = absChapters(book)
        if (abs.isNotEmpty()) { addAll(abs); return@buildList }
        book.tracks.forEachIndexed { track, file ->
            val ordered = markers[track].orEmpty().filter { it.startMs >= 0 && (file.durationMs <= 0 || it.startMs < file.durationMs - 500) }
                .sortedBy { it.startMs }.fold(mutableListOf<ChapterMarker>()) { acc, m ->
                    if (acc.isEmpty() || m.startMs - acc.last().startMs >= 500) acc.add(m)
                    acc
                }
            if (ordered.size < 2) add(PlaybackChapter(size, title(book, track), track, 0, file.durationMs))
            else ordered.forEachIndexed { i, marker ->
                val start = if (i == 0) 0 else marker.startMs
                val end = ordered.getOrNull(i + 1)?.startMs ?: file.durationMs.takeIf { it > 0 } ?: marker.endMs
                add(PlaybackChapter(size, marker.title.trim().ifEmpty { "Chapter ${size + 1}" }, track, start, (end - start).coerceAtLeast(0)))
            }
        }
    }
    fun chapterIndex(chapters: List<PlaybackChapter>, track: Int, position: Long): Int =
        chapters.lastOrNull { it.trackIndex < track || (it.trackIndex == track && it.startMs <= position + 250) }?.index ?: 0
    fun previous(chapters: List<PlaybackChapter>, track: Int, position: Long): PlaybackChapter? {
        if (chapters.size <= 1) return null
        val i = chapterIndex(chapters, track, position)
        val current = chapters[i]
        return if (position - current.startMs > 5000) current else chapters.getOrNull(i - 1)
    }
    fun skipBackward(position: Long, seconds: Int) = (position - seconds * 1000L).coerceAtLeast(0)
    fun momentTime(position: Long, seconds: Int) = (position - seconds * 1000L).coerceAtLeast(0)
    fun speed(value: Float): Float { require(value in speeds); return value }
    fun skipForward(book: LibraryBook, track: Int, position: Long, seconds: Int): Pair<Int, Long> {
        val target = position + seconds * 1000L
        val duration = book.tracks[track].durationMs
        return if (target >= duration - 1000 && track + 1 < book.tracks.size) track + 1 to 0L
        else track to target.coerceIn(0, duration)
    }
}

/** A pause toggle never consumes backtrack; Continue consumes it once per process launch. */
class ResumePolicy {
    private var available = true
    fun start(book: LibraryBook, seconds: Int): Pair<Int, Long> {
        val back = if (available && !book.isFinished) seconds * 1000L else 0L
        available = false
        return if (book.isFinished) 0 to 0L else book.currentTrackIndex to (book.currentPositionMs - back).coerceAtLeast(0)
    }
}

/** Clock injected for host tests; sleep expiration uses monotonic time, independent of speed. */
class PlaybackPersistenceRules(private val clock: () -> Long) {
    var penaltyRemainingMs = 180_000L
        private set
    private var lastTick = clock()
    private var persistedPosition = -10_000L
    private var persistedTrack = -1
    private var sleepDeadline: Long? = null
    fun load() { penaltyRemainingMs = 180_000; lastTick = clock(); persistedPosition = -10_000; persistedTrack = -1 }
    fun seek() { penaltyRemainingMs = 180_000; lastTick = clock() }
    fun mark() { penaltyRemainingMs = 0 }
    fun tick(playing: Boolean) {
        val now = clock()
        if (playing) penaltyRemainingMs = (penaltyRemainingMs - (now - lastTick).coerceAtLeast(0)).coerceAtLeast(0)
        lastTick = now
    }
    fun highWater(stored: Long, overall: Long) = if (penaltyRemainingMs == 0L) maxOf(stored, overall) else stored
    fun shouldPersist(progress: PlaybackProgress, force: Boolean): Boolean {
        if (!force && progress.trackIndex == persistedTrack && kotlin.math.abs(progress.positionMs - persistedPosition) < 5000) return false
        return true
    }
    fun didPersist(progress: PlaybackProgress) { persistedTrack = progress.trackIndex; persistedPosition = progress.positionMs }
    fun sleep(minutes: Int?) { require(minutes == null || minutes in PlaybackRules.sleepMinutes); sleepDeadline = minutes?.let { clock() + it * 60_000L } }
    fun sleepRemaining() = sleepDeadline?.let { (it - clock()).coerceAtLeast(0) }
    fun expireSleep(): Boolean = if (sleepDeadline != null && clock() >= sleepDeadline!!) { sleepDeadline = null; true } else false
}

/** An ended engine must restart even if its finished flag has not reached storage yet. */
internal object CarResumePolicy {
    fun reuse(finished: Boolean, ended: Boolean) = !finished && !ended
    fun start(resume: ResumePolicy, book: LibraryBook, seconds: Int, ended: Boolean) =
        resume.start(if (ended) book.copy(isFinished = true) else book, seconds)
}
