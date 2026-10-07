package dev.unpaged.android.ai

import android.content.Context
import androidx.core.content.edit
import dev.unpaged.android.UnpagedPreferences
import dev.unpaged.android.library.LibraryBook
import dev.unpaged.android.library.LibraryMoment
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File

class AiCoordinator(private val context: Context) {
    val models = SpeechModelStore(context)
    private val transcriber: SegmentTranscriber = WhisperTranscriber(models)
    var generator: LocalGenerator = GeneratorEnvironment.create(context)
        private set
    private val mutableStatus = MutableStateFlow(GeneratorStatus.UNAVAILABLE)
    val status = mutableStatus.asStateFlow()
    suspend fun refresh() { mutableStatus.value = generator.status(); models.refresh() }
    suspend fun ready(): Boolean { refresh(); return status.value == GeneratorStatus.AVAILABLE && models.state.value.installed }
    suspend fun prewarm() { if (ready()) try { generator.prewarm() } catch (e: CancellationException) { throw e } catch (_: Exception) { /* Recheck at use. */ } }
    fun reloadGenerator() { generator = GeneratorEnvironment.create(context) }
    private fun audio(book: LibraryBook, track: Int): File {
        check(book.isDownloaded) { "Audio for this book isn't on this phone." }
        val name = book.tracks.getOrNull(track)?.storedName ?: error("No audio available for recap.")
        check(name.isNotEmpty()) { "Audio for this book isn't on this phone." }
        return File(context.filesDir, "audiobooks/${book.id}/$name").also { check(it.isFile) { "Audio for this book isn't on this phone." } }
    }
    suspend fun moment(book: LibraryBook, draft: LibraryMoment, position: Long): LibraryMoment {
        check(ready()); val window = AiRules.smartWindow(position, book.tracks[draft.trackIndex].durationMs)
        val transcript = transcriber.transcribe(audio(book, draft.trackIndex), window.first, window.second)
        return AiRules.moment(generateLocally(generator, transcript, AiPrompts.moment, book.title, 500), transcript, draft)
    }
    suspend fun recap(book: LibraryBook, track: Int, position: Long, headline: Boolean): Recap {
        val file = audio(book, track)
        check(ready()) { "On-device AI is not available." }
        val window = AiRules.recapWindow(position)
        check(position > window.first) { "No audio available for recap." }
        val transcript = transcriber.transcribe(file, window.first, window.second)
        return AiRules.recap(generateLocally(generator, transcript, AiPrompts.recap(headline), book.title, 300), headline)
    }
}

/** Recaps are bound to their exact progress snapshot; moving the marker invalidates the cache. */
class RecapCache(context: Context) {
    private val preferences = context.getSharedPreferences("recap_cache", Context.MODE_PRIVATE)
    init { UnpagedPreferences.removeLegacyRecaps(context) }
    private fun key(book: LibraryBook) = "recap.${book.id}"
    fun read(book: LibraryBook, headline: Boolean = false): Recap? = preferences.getString(key(book), "").orEmpty().takeIf { it.isNotEmpty() }?.let {
        runCatching { org.json.JSONObject(it).let { json ->
            if (json.getInt("track") == book.currentTrackIndex && json.getLong("position") == book.currentPositionMs)
                Recap(json.getString("text"), json.optString("headline").ifBlank { null }).takeIf { !headline || !it.headline.isNullOrBlank() } else null
        } }.getOrNull()
    }
    fun remove(book: LibraryBook) { preferences.edit { remove(key(book)) } }
    fun save(book: LibraryBook, value: Recap) {
        preferences.edit { putString(key(book), org.json.JSONObject().put("track", book.currentTrackIndex).put("position", book.currentPositionMs)
            .put("text", value.text).put("headline", value.headline.orEmpty()).toString()) }
    }
}
