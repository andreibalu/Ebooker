package dev.unpaged.android.playback

import dev.unpaged.android.library.*
import org.junit.Assert.*
import org.junit.Test

class PlaybackRulesTest {
    private val book = LibraryBook("book", "The Book", "Author", listOf(
        LibraryTrack("First", "1.wav", "1.wav", 300000, "a"),
        LibraryTrack("Second", "2.wav", "2.wav", 300000, "b")))
    private var now = 0L
    private fun policy() = PlaybackPersistenceRules { now }

    @Test fun resumeBacktracksOnlyFirstContinueAndNeverCrossesTrackBoundary() {
        val resume = ResumePolicy()
        assertEquals(1 to 0L, resume.start(book.copy(currentTrackIndex = 1, currentPositionMs = 30000), 60))
        assertEquals(1 to 120000L, resume.start(book.copy(currentTrackIndex = 1, currentPositionMs = 120000), 60))
        assertEquals(0 to 0L, ResumePolicy().start(book.copy(isFinished = true, currentTrackIndex = 1, currentPositionMs = 300000), 60))
        assertEquals(0 to 60000L, ResumePolicy().start(book.copy(currentPositionMs = 60000), 0))
    }
    @Test fun embeddedMarkersAreSortedDeduplicatedAndTileFile() {
        val markers = listOf(ChapterMarker("Last", 200000, 250000), ChapterMarker(" Head ", 1000, 3000),
            ChapterMarker("Duplicate", 1200, 4000), ChapterMarker("Bad", -1, 100), ChapterMarker("Past", 299900, 400000))
        val chapters = PlaybackRules.chapters(book, mapOf(0 to markers))
        assertEquals(3, chapters.size)
        assertEquals("Head", chapters[0].title)
        assertEquals(0L, chapters[0].startMs); assertEquals(200000L, chapters[0].durationMs)
        assertEquals(100000L, chapters[1].durationMs)
        assertEquals("Second", chapters[2].title)
        assertEquals(0, PlaybackRules.chapterIndex(chapters, 0, 199749))
        assertEquals(1, PlaybackRules.chapterIndex(chapters, 0, 199750))
        assertEquals(2, PlaybackRules.chapterIndex(chapters, 1, 0))
    }
    @Test fun progressPenaltyCountsOnlyPlayingWallClockAndMarkClearsIt() {
        val rules = policy()
        now = 120000; rules.tick(false)
        assertEquals(180000L, rules.penaltyRemainingMs)
        now = 299000; rules.tick(true)
        assertEquals(1000L, rules.penaltyRemainingMs)
        assertEquals(10000L, rules.highWater(10000, 250000))
        now = 300000; rules.tick(true)
        assertEquals(250000L, rules.highWater(10000, 250000))
        assertEquals(250000L, rules.highWater(250000, 10000))
        rules.seek(); assertEquals(180000L, rules.penaltyRemainingMs)
        rules.mark(); assertEquals(0L, rules.penaltyRemainingMs)
    }
    @Test fun sleepUsesInjectedMonotonicClockExpiresOnceAndCanBeCancelled() {
        val rules = policy()
        rules.sleep(5); assertEquals(300000L, rules.sleepRemaining())
        now = 299999; assertFalse(rules.expireSleep())
        now = 300000; assertTrue(rules.expireSleep()); assertFalse(rules.expireSleep())
        assertNull(rules.sleepRemaining())
        rules.sleep(15); rules.sleep(null); now += 1000000; assertFalse(rules.expireSleep())
    }
    @Test fun loadingAnotherBookResetsPenaltyWithoutCancellingSleep() {
        val rules = policy()
        rules.sleep(5); rules.mark()
        now = 1000; rules.load()
        assertEquals(180000L, rules.penaltyRemainingMs)
        assertEquals(299000L, rules.sleepRemaining())
        assertTrue(rules.shouldPersist(PlaybackProgress(0, 0, 0), false))
    }
}
