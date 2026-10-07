package dev.unpaged.android.ai

import com.google.mlkit.genai.schema.annotations.Generable
import com.google.mlkit.genai.schema.annotations.Guide
import org.json.JSONArray
import org.json.JSONObject

/** Cheap structured fields first; longest prose last, as in the iOS Generable schema. */
@Generable
data class MomentOutput(
    @param:Guide(description = "3–5 word title in Title Case") val momentName: String,
    @param:Guide(description = "1–3 matching categories", minItems = 1, maxItems = 3,
        enumValues = ["dialogue", "action", "plotTwist", "characterIntro", "worldBuilding", "quote", "reflection", "humor", "tension", "romance"])
    val categories: List<String>,
    @param:Guide(description = "Overall mood", enumValues = ["tense", "funny", "sad", "romantic", "inspirational", "mysterious", "peaceful", "dramatic"])
    val mood: String,
    @param:Guide(description = "Names of characters speaking or mentioned, empty if none", maxItems = 6) val characters: List<String>,
    @param:Guide(description = "A complete verbatim transcript sentence, 5–20 words, or empty string. Never paraphrase or invent.") val quoteLine: String,
    @param:Guide(description = "Exactly 2 complete short sentences, max 40 words total") val momentNote: String,
) {
    fun json(): String = JSONObject().put("momentName", momentName).put("categories", JSONArray(categories)).put("mood", mood)
        .put("characters", JSONArray(characters)).put("quoteLine", quoteLine).put("momentNote", momentNote).toString()
}
@Generable
data class RecapOutput(@param:Guide(description = "Exactly two complete sentences") val recap: String) {
    fun json(): String = JSONObject().put("recap", recap).toString()
}
@Generable
data class HeadlineRecapOutput(
    @param:Guide(description = "3–4 words summarizing progress, no ending punctuation") val progressHeadline: String,
    @param:Guide(description = "Exactly two complete sentences") val recap: String,
) {
    fun json(): String = JSONObject().put("progressHeadline", progressHeadline).put("recap", recap).toString()
}
