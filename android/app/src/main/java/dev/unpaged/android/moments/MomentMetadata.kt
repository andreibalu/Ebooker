package dev.unpaged.android.moments

import dev.unpaged.android.library.LibraryMoment
import org.json.JSONArray
import java.util.Locale

enum class MomentCategory(val title: String) {
    dialogue("Dialogue"), action("Action"), plotTwist("Plot Twist"), characterIntro("Character Intro"),
    worldBuilding("World Building"), quote("Quote"), reflection("Reflection"), humor("Humor"), tension("Tension"), romance("Romance")
}
enum class MomentMood(val title: String) {
    tense("Tense"), funny("Funny"), sad("Sad"), romantic("Romantic"), inspirational("Inspirational"),
    mysterious("Mysterious"), peaceful("Peaceful"), dramatic("Dramatic")
}
fun decodeTags(json: String): List<String> = runCatching {
    val array = JSONArray(json); List(array.length()) { array.getString(it) }
}.getOrDefault(emptyList())
val LibraryMoment.categories get() = decodeTags(categoriesJson).mapNotNull { name -> MomentCategory.entries.find { it.name == name } }
val LibraryMoment.characters get() = decodeTags(charactersJson)
val LibraryMoment.moodValue get() = MomentMood.entries.find { it.name == mood }

data class MomentFilters(val categories: Set<String> = emptySet(), val moods: Set<String> = emptySet(),
                         val characters: Set<String> = emptySet()) {
    val active get() = categories.isNotEmpty() || moods.isNotEmpty() || characters.isNotEmpty()
    fun apply(moments: List<LibraryMoment>) = moments.filter { m ->
        (categories.isEmpty() || m.categories.any { it.name in categories }) &&
            (moods.isEmpty() || m.mood in moods) &&
            (characters.isEmpty() || m.characters.any { it.lowercase(Locale.ROOT) in characters })
    }.sortedWith(compareByDescending<LibraryMoment> { it.isPinned }.thenByDescending { it.createdAt }.thenBy { it.id })
}
fun addCharacter(existing: List<String>, input: String): List<String> {
    val trimmed = input.trim()
    return if (trimmed.isEmpty() || existing.any { it.equals(trimmed, ignoreCase = true) }) existing else existing + trimmed
}

/** Pending edits retain the exact track/time snapshot through activity recreation. */
val MomentSaver = androidx.compose.runtime.saveable.listSaver<LibraryMoment?, Any>(
    save = { if (it == null) emptyList() else listOf(it.id, it.bookId, it.trackIndex, it.timeMs, it.label, it.notes, it.categoriesJson,
        it.quoteLine.orEmpty(), it.charactersJson, it.mood.orEmpty(), it.createdAt, it.isPinned) },
    restore = { if (it.isEmpty()) null else LibraryMoment(it[0] as String, it[1] as String, it[2] as Int, it[3] as Long,
        it[4] as String, it[5] as String, it[6] as String, (it[7] as String).ifEmpty { null },
        it[8] as String, (it[9] as String).ifEmpty { null }, it[10] as Long, it[11] as Boolean) }
)
val MomentFiltersSaver = androidx.compose.runtime.saveable.listSaver<MomentFilters, Any>(
    save = { listOf(ArrayList(it.categories), ArrayList(it.moods), ArrayList(it.characters)) },
    restore = { MomentFilters((it[0] as List<*>).filterIsInstance<String>().toSet(),
        (it[1] as List<*>).filterIsInstance<String>().toSet(), (it[2] as List<*>).filterIsInstance<String>().toSet()) }
)
