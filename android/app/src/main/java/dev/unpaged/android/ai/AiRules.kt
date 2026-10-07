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
    private fun strict(json: String, keys: Set<String>): JSONObject {
        require(json.trim().startsWith("{") && json.trim().endsWith("}"))
        return JSONObject(json).also { require(it.keys().asSequence().toSet() == keys) }
    }
    private fun string(json: JSONObject, key: String) = (json.get(key) as? String) ?: error("Invalid $key")
    private fun strings(json: JSONObject, key: String): List<String> {
        val array = json.get(key) as? JSONArray ?: error("Invalid $key")
        return List(array.length()) { array.get(it) as? String ?: error("Invalid $key") }
    }
    fun moment(json: String, transcript: String, draft: LibraryMoment): LibraryMoment {
        val obj = strict(json, setOf("momentName", "categories", "mood", "characters", "quoteLine", "momentNote"))
        val categories = strings(obj, "categories").distinct()
        require(categories.size in 1..3 && categories.all { tag -> MomentCategory.entries.any { it.name == tag } })
        val mood = string(obj, "mood").trim()
        require(MomentMood.entries.any { it.name == mood })
        return draft.copy(label = cap(string(obj, "momentName"), 5).ifBlank { "Saved Moment" },
            notes = prose(string(obj, "momentNote"), 40), categoriesJson = JSONArray(categories).toString(),
            mood = mood, charactersJson = JSONArray(strings(obj, "characters").map { it.trim() }.filter { it.isNotEmpty() }.distinct().take(6)).toString(),
            quoteLine = verifiedQuote(string(obj, "quoteLine"), transcript))
    }
    fun recap(json: String, headline: Boolean): Recap {
        val obj = strict(json, if (headline) setOf("progressHeadline", "recap") else setOf("recap"))
        return Recap(prose(string(obj, "recap"), 80).also { require(it.isNotBlank()) },
            if (headline) cap(string(obj, "progressHeadline"), 4).trimEnd('.', '!', '?').ifBlank { null } else null)
    }
}
data class Recap(val text: String, val headline: String?)
