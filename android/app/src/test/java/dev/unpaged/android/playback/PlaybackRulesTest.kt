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
    @Test fun trackChaptersPreserveQueueAndSingleTrackDisplayTitle() {
        val chapters = PlaybackRules.chapters(book)
        assertEquals(listOf("First", "Second"), chapters.map { it.title })
        assertEquals(listOf(0, 1), chapters.map { it.trackIndex })
        assertEquals(listOf(300000L, 300000L), chapters.map { it.durationMs })
        val single = book.copy(tracks = book.tracks.take(1))
        assertEquals("The Book", PlaybackRules.chapters(single).single().title)
        assertNull(PlaybackRules.miniSecondary(single, 0))
        assertEquals("First", PlaybackRules.miniSecondary(book, 0))
        assertNull(PlaybackRules.miniSecondary(book.copy(title = "First"), 0))
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
    @Test fun aSingleMarkerFallsBackToTrackChapter() {
        assertEquals(PlaybackRules.chapters(book), PlaybackRules.chapters(book, mapOf(0 to listOf(ChapterMarker("Only", 2000, 300000)))))
    }
    @Test fun previousChapterRestartsAfterFiveSecondsOtherwiseStepsBack() {
        val chapters = PlaybackRules.chapters(book)
        assertNull(PlaybackRules.previous(chapters, 0, 5000))
        assertEquals(0, PlaybackRules.previous(chapters, 0, 5001)?.index)
        assertEquals(0, PlaybackRules.previous(chapters, 1, 5000)?.index)
        assertEquals(1, PlaybackRules.previous(chapters, 1, 5001)?.index)
        assertNull(PlaybackRules.previous(chapters.take(1), 0, 100000))
    }
    @Test fun skipsClampWithinFileOrAdvanceToNextFileNearItsEnd() {
        assertEquals(0 to 45000L, PlaybackRules.skipForward(book, 0, 15000, 30))
        assertEquals(1 to 0L, PlaybackRules.skipForward(book, 0, 269000, 30))
        assertEquals(1 to 300000L, PlaybackRules.skipForward(book, 1, 290000, 45))
    }
    @Test fun backwardSkipAndMomentOffsetClampAtCurrentFileStart() {
        assertEquals(0L, PlaybackRules.skipBackward(15000, 30))
        assertEquals(45000L, PlaybackRules.skipBackward(60000, 15))
        assertEquals(60000L, PlaybackRules.momentTime(60000, 0))
        assertEquals(0L, PlaybackRules.momentTime(60000, 120))
        assertEquals(30000L, PlaybackRules.momentTime(60000, 30))
        assertEquals(1.25f, PlaybackRules.speed(1.25f))
        assertThrows(IllegalArgumentException::class.java) { PlaybackRules.speed(Float.NaN) }
        assertThrows(IllegalArgumentException::class.java) { PlaybackRules.speed(3f) }
    }
    @Test fun persistenceUsesFiveSecondDeltaButForcesPauseAndTrackTransitions() {
        val rules = policy()
        val zero = PlaybackProgress(0, 0, 0)
        assertTrue(rules.shouldPersist(zero, false)); rules.didPersist(zero)
        assertFalse(rules.shouldPersist(zero.copy(positionMs = 4999), false))
        assertTrue(rules.shouldPersist(zero.copy(positionMs = 5000), false))
        assertTrue(rules.shouldPersist(zero.copy(trackIndex = 1), false))
        assertTrue(rules.shouldPersist(zero.copy(positionMs = 1), true))
        rules.didPersist(zero.copy(positionMs = 20000))
        assertTrue(rules.shouldPersist(zero.copy(positionMs = 10000), false))
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
    @Test fun speedAndSleepChoicesMatchIosExactly() {
        assertEquals(listOf(.8f, 1f, 1.25f, 1.5f, 1.75f, 2f), PlaybackRules.speeds)
        assertEquals(listOf(5, 15, 30, 60), PlaybackRules.sleepMinutes)
        assertThrows(IllegalArgumentException::class.java) { policy().sleep(10) }
    }
}
