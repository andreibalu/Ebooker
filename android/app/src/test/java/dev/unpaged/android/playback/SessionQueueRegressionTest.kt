package dev.unpaged.android.playback

import dev.unpaged.android.library.LibraryBook
import dev.unpaged.android.library.LibraryTrack
import org.junit.Assert.*
import org.junit.Test

class SessionQueueRegressionTest {
    @Test fun newerRequestRejectsOldResolutionAndQueueEvenForSameBook() {
        val gate = SessionQueueGate()
        val old = gate.begin("X")
        gate.stage(old, "B")
        val current = gate.begin("X")
        assertFalse(gate.stage(old, "B"))
        assertTrue(gate.stage(current, "B"))
        assertFalse(gate.consume(old, "B"))
        assertFalse(gate.consume(current, "A"))
        assertTrue(gate.consume(current, "B"))
    }
    @Test fun finishedAndEndedBooksRestartAtFirstTrackForSelectionAndResumption() {
        val book = LibraryBook("finished", "Finished", "Author", listOf(
            LibraryTrack("First", "1.wav", "1.wav", 120000, "a"),
            LibraryTrack("Last", "2.wav", "2.wav", 120000, "b")),
            currentTrackIndex = 1, currentPositionMs = 120000)
        val resume = ResumePolicy()
        assertEquals(0 to 0L, CarResumePolicy.start(resume, book.copy(isFinished = true), 60, false))
        assertEquals(0 to 0L, CarResumePolicy.start(resume, book, 60, true))
        assertEquals(1 to 120000L, CarResumePolicy.start(resume, book, 60, false))
    }

}
