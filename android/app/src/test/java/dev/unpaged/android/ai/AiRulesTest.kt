package dev.unpaged.android.ai

import dev.unpaged.android.library.LibraryMoment
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class AiRulesTest {
    private val transcript = "It was a long night. The storm broke over the harbor at midnight, and nobody slept. Morning came slowly."
    private val quote = "The storm broke over the harbor at midnight, and nobody slept."
    @Test fun midWordQuoteDropped() { assertEquals("", AiRules.sanitizedQuote("I cannot describe my sensations as I embark on the jour", transcript)) }
    @Test fun partialTailDropped() { assertEquals("She closed the door behind her.", AiRules.sanitizedQuote("She closed the door behind her. He followed with his hand trem", "x".repeat(500))) }
    @Test fun longUnterminatedQuoteDropped() { assertEquals("", AiRules.sanitizedQuote("z".repeat(230), "a".repeat(1000))) }
    @Test fun longQuoteKeepsFirstSentence() { assertEquals("She walked into the storm without looking back.", AiRules.sanitizedQuote("She walked into the storm without looking back. " + "x".repeat(230), "a".repeat(1000))) }
    @Test fun partialNoteRecovered() { assertEquals("Victor decides to embark on a perilous voyage.", AiRules.complete("Victor decides to embark on a perilous voyage. This moment marks a turn")) }
    @Test fun nearMissSnapsAtSeventyPercent() { assertEquals(quote, AiRules.verifiedQuote("Storm broke over harbor at midnight, nobody slept!", transcript)) }
    @Test fun inventedQuoteDropped() { assertNull(AiRules.verifiedQuote("To be or not to be, that is the question.", transcript)) }
    private fun json(category: String = "reflection", mood: String = "peaceful") = """{"momentName":"A long title with seven full words","categories":["$category"],"mood":"$mood","characters":["Alice"," Bob ","","C","D","E","F","G"],"quoteLine":"$quote","momentNote":"${"word ".repeat(50)}end. More words."}"""
    private val draft = LibraryMoment("m", "b", 0, 10, "")
    @Test fun invalidEnumsAreDroppedNotFatal() { val m = AiRules.moment(json("fiction", "happy"), transcript, draft); assertEquals("[]", m.categoriesJson); assertNull(m.mood) }
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
    @Test fun unsafeDoesNotRetry() = runBlocking { val g = Generator(mutableListOf(GenerationFailure.UNSAFE)); try { generateLocally(g, transcript, "i", "t", GenerationKind.RECAP); fail() } catch (e: LocalGenerationException) { assertEquals(GenerationFailure.UNSAFE, e.reason); assertEquals(1, g.prompts.size) } }
    @Test fun recapRejectsMissingOrWrongTypedText() { for (json in listOf("{}", "```json {} ```", "{\"recap\":3}", "no json")) assertThrows(Exception::class.java) { AiRules.recap(json, false) } }
    @Test fun recapToleratesFencesProseAndExtraKeys() { assertEquals("A complete sentence here.", AiRules.recap("Sure!\n```json\n{\"recap\":\"A complete sentence here.\",\"extra\":true}\n```", false).text) }
    @Test fun extractObjectHandlesBracesInStrings() { assertEquals("a } b", AiRules.extractObject("x {\"k\":\"a } b\"} tail {\"z\":1}").getString("k")) }
    @Test fun recapHeadlineFirstAndSanitized() { assertTrue(AiPrompts.recap(true).indexOf("progressHeadline") < AiPrompts.recap(true).indexOf("recap (")); val r = AiRules.recap("""{"progressHeadline":"One two three four five.","recap":"A complete sentence here. A second complete sentence here. An unfinished"}""", true); assertEquals("One two three four", r.headline); assertEquals("A complete sentence here. A second complete sentence here.", r.text) }
    @Test fun modelRejectsShortAndCorruptedFile() { val f = File.createTempFile("model", ".bin"); try { f.writeText("invalid"); assertFalse(SpeechModelStore.verified(f)) } finally { f.delete() } }
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
