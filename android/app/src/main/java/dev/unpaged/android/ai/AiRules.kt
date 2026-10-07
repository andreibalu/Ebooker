package dev.unpaged.android.ai

import dev.unpaged.android.library.LibraryMoment
import dev.unpaged.android.moments.MomentCategory
import dev.unpaged.android.moments.MomentMood
import org.json.JSONArray
import org.json.JSONObject
import java.text.Normalizer
import java.util.Locale

/** Pure post-processing. No service, transport, or model download access. */
object AiRules {
    fun smartWindow(position: Long, duration: Long) = (position - 75_000).coerceAtLeast(0) to (position + 15_000).coerceAtMost(duration)
    fun recapWindow(position: Long) = (position - 200_000).coerceAtLeast(0) to position
    fun words(text: String) = text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
    fun cap(text: String, count: Int) = words(text).take(count).joinToString(" ")
    fun complete(text: String): String {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || trimmed.last() in ".!?") return trimmed
        val end = trimmed.indexOfLast { it in ".!?" }
        return if (end >= 19) trimmed.take(end + 1) else "$trimmed…"
    }
    fun sentences(text: String) = Regex("[^.!?]+[.!?]+(?:[\"'”’])?").findAll(text).map { it.value.trim() }.toList()
    fun prose(text: String, limit: Int) = complete(cap(sentences(text).take(2).joinToString(" ").ifEmpty { text }, limit))
    fun matchKey(text: String): String = Normalizer.normalize(text.lowercase(Locale.ROOT), Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "").replace(Regex("[^\\p{L}\\p{N}]+"), " ").trim()
    fun sanitizedQuote(raw: String, transcript: String): String {
        val text = raw.replace(Regex("\\s+"), " ").trim().trim('"', '“', '”', '\'')
        if (text.isEmpty()) return ""
        if (text.length > 220 || text.length.toDouble() / transcript.length.coerceAtLeast(1) > .45) {
            val first = sentences(text).firstOrNull().orEmpty()
            return first.takeIf { it.length in 20..140 } ?: ""
        }
        if (text.last() in ".!?") return text
        val end = text.indexOfLast { it in ".!?" }
        return if (end >= 19) text.take(end + 1) else ""
    }
    fun verifiedQuote(raw: String, transcript: String): String? {
        val quote = sanitizedQuote(raw, transcript)
        val key = matchKey(quote)
        if (key.isEmpty()) return null
        if (words(quote).size !in 5..20) return null
        if (matchKey(transcript).contains(key)) return quote
        val words = key.split(" ").toSet()
        if (words.size < 3) return null
        return sentences(transcript).filter { it.length in 20..220 && words(it).size in 5..20 }
            .map { it to matchKey(it).split(" ").toSet().intersect(words).size.toDouble() / words.size }
            .maxByOrNull { it.second }?.takeIf { it.second >= .7 }?.first
    }
    /** Strips code fences/prose and returns the first balanced `{…}` object. Unknown keys are the caller's to ignore. */
    fun extractObject(text: String): JSONObject {
        val start = text.indexOf('{')
        require(start >= 0) { "No JSON object" }
        var depth = 0; var inString = false; var escaped = false
        for (i in start until text.length) {
            val c = text[i]
            if (inString) { if (escaped) escaped = false else if (c == '\\') escaped = true else if (c == '"') inString = false; continue }
            when (c) { '"' -> inString = true; '{' -> depth++; '}' -> if (--depth == 0) return JSONObject(text.substring(start, i + 1)) }
        }
        error("Unterminated JSON object")
    }
    private fun string(json: JSONObject, key: String) = (json.opt(key) as? String) ?: error("Invalid $key")
    private fun optionalStrings(json: JSONObject, key: String): List<String> {
        val array = json.opt(key) as? JSONArray ?: return emptyList()
        return List(array.length()) { array.opt(it) as? String }.filterNotNull()
    }
    fun moment(json: String, transcript: String, draft: LibraryMoment): LibraryMoment {
        val obj = extractObject(json)
        val categories = optionalStrings(obj, "categories").mapNotNull { tag -> MomentCategory.entries.firstOrNull { it.name.equals(tag.trim(), ignoreCase = true) }?.name }.distinct().take(3)
        val mood = (obj.opt("mood") as? String)?.trim()?.let { raw -> MomentMood.entries.firstOrNull { it.name.equals(raw, ignoreCase = true) }?.name }
        return draft.copy(label = cap(string(obj, "momentName"), 5).ifBlank { "Saved Moment" },
            notes = prose(string(obj, "momentNote"), 40), categoriesJson = JSONArray(categories).toString(),
            mood = mood, charactersJson = JSONArray(optionalStrings(obj, "characters").map { it.trim() }.filter { it.isNotEmpty() }.distinct().take(6)).toString(),
            quoteLine = (obj.opt("quoteLine") as? String)?.let { verifiedQuote(it, transcript) })
    }
    fun recap(json: String, headline: Boolean): Recap {
        val obj = extractObject(json)
        return Recap(prose(string(obj, "recap"), 80).also { require(it.isNotBlank()) },
            if (headline) (obj.opt("progressHeadline") as? String)?.let { cap(it, 4).trimEnd('.', '!', '?').ifBlank { null } } else null)
    }
}
data class Recap(val text: String, val headline: String?)

/** User-facing failure copy, mirroring the iOS unsafe-content and generic-failure messages. */
object AiMessages {
    private fun unsafe(e: Throwable) = (e as? LocalGenerationException)?.reason == GenerationFailure.UNSAFE
    fun momentFailure(e: Throwable) = if (unsafe(e)) "AI detected content likely to be unsafe and couldn't name this moment." else "Couldn't analyze this moment."
    fun recapFailure(e: Throwable, downloaded: Boolean) = when {
        !downloaded -> "Audio for this book isn't on this phone."
        unsafe(e) -> "On-device AI declined to summarize this passage."
        else -> "Couldn't generate a recap. Please try again."
    }
}
