package dev.unpaged.android.ai

import android.content.Context
import android.os.Bundle
import androidx.core.content.edit
import dev.unpaged.android.MainActivity
import dev.unpaged.android.UnpagedApplication
import org.json.JSONObject
import org.json.JSONArray

object GeneratorEnvironment {
    fun create(context: Context): LocalGenerator = when (context.getSharedPreferences("ai-debug", Context.MODE_PRIVATE).getString("generator", "nano")) {
        "available" -> FakeLocalGenerator(GeneratorStatus.AVAILABLE)
        "unavailable" -> FakeLocalGenerator(GeneratorStatus.UNAVAILABLE)
        else -> NanoGenerator()
    }
}
/** Debug-only deterministic transformation; the transcript still comes from real Whisper. */
class FakeLocalGenerator(private val capability: GeneratorStatus) : LocalGenerator {
    override suspend fun status() = capability
    override suspend fun prewarm() = Unit
    override suspend fun download(progress: (Long) -> Unit) = Unit
    override suspend fun generate(prompt: String, maxTokens: Int): String {
        check(capability == GeneratorStatus.AVAILABLE)
        val transcript = prompt.substringAfter("<transcript>\n").substringBefore("\n</transcript>")
        val sentence = if (AiRules.matchKey(transcript).contains("ask what you can do for your country")) "Ask what you can do for your country."
            else AiRules.sentences(transcript).firstOrNull { AiRules.words(it).size in 5..20 }
                // Whisper often joins sentences with commas; quote a clause like the real model would.
                ?: transcript.split(',', ';').map { it.trim() }.firstOrNull { AiRules.words(it).size in 5..20 }?.let { "$it." }
                ?: ""
        return if (maxTokens == 500) JSONObject().put("momentName", "A Journey Begins Here").put("categories", JSONArray(listOf("reflection")))
            .put("mood", "peaceful").put("characters", JSONArray()).put("quoteLine", sentence)
            .put("momentNote", "The listener hears a new story. A journey begins with a memorable passage.").toString()
        else JSONObject().apply {
            if (prompt.contains("progressHeadline (")) put("progressHeadline", "A New Journey Begins")
            put("recap", "The story opens with a memorable passage. The listener follows the beginning of a journey.")
        }.toString()
    }
}
class AiFixtureActivity : MainActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val value = intent.getStringExtra("generator")
        if (value in listOf("available", "unavailable", "nano")) getSharedPreferences("ai-debug", MODE_PRIVATE).edit(commit = true) { putString("generator", value) }
        (application as UnpagedApplication).ai.reloadGenerator()
        super.onCreate(savedInstanceState)
    }
}
