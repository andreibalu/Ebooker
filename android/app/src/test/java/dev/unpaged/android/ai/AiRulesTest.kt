package dev.unpaged.android.ai

import dev.unpaged.android.library.LibraryMoment
import dev.unpaged.android.UnpagedPreferences
import dev.unpaged.android.library.LibraryBook
import dev.unpaged.android.library.LibraryTrack
import dev.unpaged.android.moments.MomentCategory
import dev.unpaged.android.moments.MomentMood
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.io.File

@RunWith(RobolectricTestRunner::class)
class AiRulesTest {
    private val transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept. Morning came slowly."
    private val quote = "The storm broke over the harbor at midnight, and nobody slept."
    @Test fun normalQuotePassesThrough() { assertEquals("A memorable line from the story.", AiRules.sanitizedQuote("A memorable line from the story.", "word ".repeat(30))) }
    @Test fun surroundingQuotationMarksRemoved() { assertEquals("Hello there.", AiRules.sanitizedQuote("\"“”'Hello there.'”\"", "x".repeat(50))) }
    @Test fun whitespaceCollapsed() { assertEquals("Line one Line two Line three.", AiRules.sanitizedQuote("Line one\nLine two\r\nLine three.", "x".repeat(500))) }
    @Test fun midWordQuoteDropped() { assertEquals("", AiRules.sanitizedQuote("I cannot describe my sensations as I embark on the jour", transcript)) }
    @Test fun partialTailDropped() { assertEquals("She closed the door behind her.", AiRules.sanitizedQuote("She closed the door behind her. He followed with his hand trem", "x".repeat(500))) }
    @Test fun longUnterminatedQuoteDropped() { assertEquals("", AiRules.sanitizedQuote("z".repeat(230), "a".repeat(1000))) }
    @Test fun longQuoteKeepsFirstSentence() { assertEquals("She walked into the storm without looking back.", AiRules.sanitizedQuote("She walked into the storm without looking back. " + "x".repeat(230), "a".repeat(1000))) }
    @Test fun transcriptSizedShortSentenceDropped() { assertEquals("", AiRules.sanitizedQuote("Hi." + "x".repeat(220), "ab")) }
    @Test fun emptyQuoteDropped() { assertEquals("", AiRules.sanitizedQuote("", transcript)) }
    @Test fun completeNoteUnchanged() { assertEquals("Victor decides to embark on a perilous voyage. The moment marks a turning point in his life.", AiRules.complete("Victor decides to embark on a perilous voyage. The moment marks a turning point in his life.")) }
    @Test fun partialNoteRecovered() { assertEquals("Victor decides to embark on a perilous voyage.", AiRules.complete("Victor decides to embark on a perilous voyage. This moment marks a turn")) }
    @Test fun noCompleteSentenceShowsEllipsis() { assertEquals("Victor decides to embark on a perilous voyage and…", AiRules.complete("Victor decides to embark on a perilous voyage and")) }
    @Test fun blankNoteEmpty() { assertEquals("", AiRules.complete(" \n ")) }
    @Test fun verbatimQuoteKept() { assertEquals(quote, AiRules.verifiedQuote(quote, transcript)) }
    @Test fun caseAndPunctuationIgnored() { assertNotNull(AiRules.verifiedQuote("the storm broke over the harbor at midnight and nobody slept.", transcript)) }
    @Test fun nearMissSnapsAtSeventyPercent() { assertEquals(quote, AiRules.verifiedQuote("Storm broke over harbor at midnight, nobody slept!", transcript)) }
    @Test fun inventedQuoteDropped() { assertNull(AiRules.verifiedQuote("To be or not to be, that is the question.", transcript)) }
    @Test fun shortNonVerbatimQuoteDropped() { assertNull(AiRules.verifiedQuote("Harbor explosions!", transcript)) }
    @Test fun matchKeyFoldsDiacritics() { assertEquals("cafe night falls", AiRules.matchKey("Café—NIGHT, falls!")) }
    @Test fun sentenceTerminators() { assertEquals(listOf("One came first.", "Two came second!", "Three came third?"), AiRules.sentences("One came first. Two came second! Three came third?")) }
    @Test fun categoryEnumPromptSync() { MomentCategory.entries.forEach { assertTrue(AiPrompts.moment.contains(it.name)); assertTrue(File("src/main/java/dev/unpaged/android/ai/ModelOutputs.kt").readText().contains("\"${it.name}\"")) } }
    @Test fun moodEnumPromptSync() { MomentMood.entries.forEach { assertTrue(AiPrompts.moment.contains(it.name)); assertTrue(File("src/main/java/dev/unpaged/android/ai/ModelOutputs.kt").readText().contains("\"${it.name}\"")) } }
    @Test fun headlineCaps() { for ((input, expected) in listOf("one two three four" to "one two three four", "alpha beta gamma delta epsilon zeta" to "alpha beta gamma delta", "   left right   " to "left right", "" to "", "Hello" to "Hello")) assertEquals(expected, AiRules.cap(input, 4)) }
    @Test fun windowsClamp() { assertEquals(0L to 20_000L, AiRules.smartWindow(10_000, 20_000)); assertEquals(25_000L to 115_000L, AiRules.smartWindow(100_000, 500_000)); assertEquals(0L to 10_000L, AiRules.recapWindow(10_000)); assertEquals(100_000L to 300_000L, AiRules.recapWindow(300_000)) }
    private fun json(category: String = "reflection", mood: String = "peaceful") = """{"momentName":"A long title with seven full words","categories":["$category"],"mood":"$mood","characters":["Alice"," Bob ","","C","D","E","F","G"],"quoteLine":"$quote","momentNote":"${"word ".repeat(50)}end. More words."}"""
    @Test fun quoteWordCaps() { val quote = "word ".repeat(21).trim() + "."; assertNull(AiRules.verifiedQuote(quote, quote + "more ".repeat(100))); assertNull(AiRules.verifiedQuote("Short quote.", "Short quote. " + "text ".repeat(100))) }
    @Test fun outputCapsAndMetadata() { val m = AiRules.moment(json(), transcript, LibraryMoment("m", "b", 0, 10, "")); assertEquals(5, AiRules.words(m.label).size); assertTrue(AiRules.words(m.notes).size <= 40); assertEquals(quote, m.quoteLine); assertEquals(6, org.json.JSONArray(m.charactersJson).length()) }
    private val draft = LibraryMoment("m", "b", 0, 10, "")
    @Test fun invalidEnumsAreDroppedNotFatal() { val m = AiRules.moment(json("fiction", "happy"), transcript, draft); assertEquals("[]", m.categoriesJson); assertNull(m.mood) }
    @Test fun enumMatchIsCaseInsensitive() { val m = AiRules.moment(json("PlotTwist", "Peaceful"), transcript, draft); assertEquals("[\"plotTwist\"]", m.categoriesJson); assertEquals("peaceful", m.mood) }
    @Test fun momentParsesFencedOutputWithExtraKeys() {
        val raw = "```json\n{\"momentName\":\"Night Storm\",\"extra\":[1],\"categories\":[\"Tension\",\"bogus\"],\"mood\":\"TENSE\",\"momentNote\":\"A storm breaks. Nobody sleeps.\"}\n```"
        val m = AiRules.moment(raw, transcript, draft)
        assertEquals("Night Storm", m.label); assertEquals("[\"tension\"]", m.categoriesJson); assertEquals("tense", m.mood); assertEquals("[]", m.charactersJson); assertNull(m.quoteLine)
    }
    @Test fun momentStillNeedsNameAndNote() { assertThrows(Exception::class.java) { AiRules.moment("{\"mood\":\"tense\"}", transcript, draft) } }
    @Test fun speechMarkersAndHallucinationsRemoved() {
        assertEquals("", SpeechText.clean(" [BLANK_AUDIO] ")); assertEquals("", SpeechText.clean("[Music] (music) ♪")); assertEquals("", SpeechText.clean("Thank you."))
        assertEquals("It was a long night.", SpeechText.clean("[Music] It was a long night. (door creaks) *applause*"))
    }
    @Test fun resamplerAveragesInsteadOfDecimating() {
        // 48 kHz alternating +1/-1 is pure Nyquist noise; naive decimation would alias it, a box filter cancels it.
        val r = BoxResampler(0, 100); for (i in 0 until 4800) r.add(i * 1_000_000.0 / 48_000, if (i % 2 == 0) 1f else -1f)
        val out = r.finish(); assertTrue(out.size in 1590..1600); assertTrue(out.take(1500).all { kotlin.math.abs(it) < .4f })
    }
    @Test fun resamplerHonorsBoundsAndInterpolatesUpsampling() {
        val r = BoxResampler(10, 20); for (i in 0 until 400) r.add(i * 1000.0, i.toFloat())
        val out = r.finish(); assertTrue(out.size in 140..160); assertEquals(10f, out[0], .01f); assertTrue(out.toList().zipWithNext().all { (a, b) -> b >= a })
    }
    @Test fun contextBudgetIncludesOutputAllowance() { assertTrue(fitsContext(3596, GenerationKind.MOMENT)); assertFalse(fitsContext(3597, GenerationKind.MOMENT)); assertFalse(fitsContext(3797, GenerationKind.RECAP)); assertTrue(fitsContext(3796, GenerationKind.RECAP)) }
    @Test fun errorCodesMapToFailures() {
        assertEquals(GenerationFailure.UNSAFE, failureFor(com.google.mlkit.genai.common.GenAiException.ErrorCode.RESPONSE_GENERATION_ERROR))
        assertEquals(GenerationFailure.BUSY, failureFor(com.google.mlkit.genai.common.GenAiException.ErrorCode.BUSY))
        assertEquals(GenerationFailure.CONTEXT, failureFor(com.google.mlkit.genai.common.GenAiException.ErrorCode.REQUEST_TOO_LARGE))
        assertEquals(GenerationFailure.FAILED, failureFor(com.google.mlkit.genai.common.GenAiException.ErrorCode.NOT_AVAILABLE))
    }
    @Test fun unsafeCopyMirrorsIos() {
        val unsafe = LocalGenerationException(GenerationFailure.UNSAFE)
        assertEquals("AI detected content likely to be unsafe and couldn't name this moment.", AiMessages.momentFailure(unsafe)); assertEquals("Couldn't analyze this moment.", AiMessages.momentFailure(IllegalStateException()))
        assertEquals("On-device AI declined to summarize this passage.", AiMessages.recapFailure(unsafe, true)); assertEquals("Couldn't generate a recap. Please try again.", AiMessages.recapFailure(IllegalStateException(), true))
    }
    @Test fun unsafeDoesNotRetry() = runBlocking { val g = Generator(mutableListOf(GenerationFailure.UNSAFE)); try { generateLocally(g, transcript, "i", "t", GenerationKind.RECAP); fail() } catch (e: LocalGenerationException) { assertEquals(GenerationFailure.UNSAFE, e.reason); assertEquals(1, g.prompts.size) } }
    @Test fun recapRejectsMissingOrWrongTypedText() { for (json in listOf("{}", "```json {} ```", "{\"recap\":3}", "no json")) assertThrows(Exception::class.java) { AiRules.recap(json, false) } }
    @Test fun recapToleratesFencesProseAndExtraKeys() { assertEquals("A complete sentence here.", AiRules.recap("Sure!\n```json\n{\"recap\":\"A complete sentence here.\",\"extra\":true}\n```", false).text) }
    @Test fun extractObjectHandlesBracesInStrings() { assertEquals("a } b", AiRules.extractObject("x {\"k\":\"a } b\"} tail {\"z\":1}").getString("k")) }
    @Test fun recapHeadlineFirstAndSanitized() { assertTrue(AiPrompts.recap(true).indexOf("progressHeadline") < AiPrompts.recap(true).indexOf("recap (")); val r = AiRules.recap("""{"progressHeadline":"One two three four five.","recap":"A complete sentence here. A second complete sentence here. An unfinished"}""", true); assertEquals("One two three four", r.headline); assertEquals("A complete sentence here. A second complete sentence here.", r.text) }
    @Test fun modelRejectsShortAndCorruptedFile() { val f = File.createTempFile("model", ".bin"); try { f.writeText("invalid"); assertFalse(SpeechModelStore.verified(f)) } finally { f.delete() } }
    @Test fun recapPersistenceAndAnchorInvalidation() { val b = LibraryBook("ai", "Title", "Author", listOf(LibraryTrack("track", "file", "file", 300_000, "sha")), currentPositionMs = 10_000); RecapCache(RuntimeEnvironment.getApplication()).save(b, Recap("Recap.", "Headline")); assertEquals(Recap("Recap.", "Headline"), RecapCache(RuntimeEnvironment.getApplication()).read(b)); assertNull(RecapCache(RuntimeEnvironment.getApplication()).read(b.copy(currentPositionMs = 20_000))) }
    @Test fun masterAiOffResetsChildPreferencesAcrossReopen() {
        val p = UnpagedPreferences(RuntimeEnvironment.getApplication())
        for (key in listOf("useLocalAIFeatures", "useSmartMomentNaming", "useSmartSummary", "shortenSummary")) p.setAiPreference(key, true)
        p.setAiPreference("useLocalAIFeatures", false)
        val reopened = UnpagedPreferences(RuntimeEnvironment.getApplication())
        for (key in listOf("useLocalAIFeatures", "useSmartMomentNaming", "useSmartSummary", "shortenSummary")) assertEquals("false", reopened.text(key, "true"))
    }
    @Test fun disablingSummaryResetsHeadlineOnly() {
        val p = UnpagedPreferences(RuntimeEnvironment.getApplication())
        for (key in listOf("useLocalAIFeatures", "useSmartMomentNaming", "useSmartSummary", "shortenSummary")) p.setAiPreference(key, true)
        p.setAiPreference("useSmartSummary", false)
        assertEquals("false", p.text("shortenSummary", "true")); assertEquals("true", p.text("useSmartMomentNaming", "false"))
    }
    @Test fun inferenceHasNoNetworkClient() {
        for (name in listOf("AiRules.kt", "LocalGenerator.kt", "SegmentTranscriber.kt", "AiCoordinator.kt")) {
            val source = File("src/main/java/dev/unpaged/android/ai/$name").readText()
            for (client in listOf("java.net", "okhttp", "retrofit", "HttpURLConnection", "URL(", "ABSClient", "LibriVoxClient")) assertFalse("$name must have no network inference client: $client", source.contains(client))
        }
    }
    private class Generator(private val failures: MutableList<GenerationFailure>) : LocalGenerator {
        val prompts = mutableListOf<String>()
        override suspend fun status() = GeneratorStatus.AVAILABLE
        override suspend fun prewarm() = Unit
        override suspend fun download(progress: (Long) -> Unit) = Unit
        override suspend fun generate(prompt: String, kind: GenerationKind): String { prompts += prompt; if (failures.isNotEmpty()) throw LocalGenerationException(failures.removeAt(0)); return "ok" }
    }
    @Test fun overflowRetriesOnlyTranscriptTail() = runBlocking { val g = Generator(mutableListOf(GenerationFailure.CONTEXT)); assertEquals("ok", generateLocally(g, "abcdefgh", "instruction", "title", GenerationKind.MOMENT)); assertEquals(2, g.prompts.size); assertTrue(g.prompts[1].contains("\nefgh\n")) }
    @Test fun busyRetriesOriginalOnce() = runBlocking { val g = Generator(mutableListOf(GenerationFailure.BUSY)); generateLocally(g, transcript, "instruction", "title", GenerationKind.MOMENT); assertEquals(g.prompts[0], g.prompts[1]) }
    @Test fun terminalFailureDoesNotRetry() = runBlocking { val g = Generator(mutableListOf(GenerationFailure.FAILED)); try { generateLocally(g, transcript, "instruction", "title", GenerationKind.MOMENT); fail() } catch (_: LocalGenerationException) { assertEquals(1, g.prompts.size) } }
}
