package dev.unpaged.android.playback

import dev.unpaged.android.library.LibraryBook
import dev.unpaged.android.library.LibraryTrack
import org.junit.Assert.*
import org.junit.Test

class SessionQueueRegressionTest {
    @Test fun unrelatedDisconnectCannotAbandonStagedBook() {
        val gate = SessionQueueGate()
        val token = gate.begin("X")
        assertTrue(gate.stage(token, "B"))
        assertFalse(gate.disconnect("Y"))
        assertTrue(gate.consume(token, "B"))
        assertFalse(gate.consume(token, "B"))
    }
    @Test fun ownerDisconnectTimeoutAndPhoneLoadRejectLateApplications() {
        val gate = SessionQueueGate()
        val disconnected = gate.begin("X")
        gate.stage(disconnected, "B")
        assertTrue(gate.disconnect("X"))
        assertFalse(gate.consume(disconnected, "B"))
        val expired = gate.begin("X")
        gate.stage(expired, "B")
        assertTrue(gate.expire(expired))
        assertFalse(gate.consume(expired, "B"))
        val cleared = gate.begin("X")
        gate.stage(cleared, "B")
        gate.clear()
        assertFalse(gate.consume(cleared, "B"))
    }
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
    @Test fun removalInvalidatesBoundPreparationAndCannotRetargetItsGeneration() {
        val gate = SessionQueueGate()
        val token = gate.begin("X")
        assertTrue(gate.stage(token, "B"))
        assertFalse(gate.stage(token, "C"))
        assertFalse(gate.remove("C"))
        assertTrue(gate.current(token))
        assertTrue(gate.remove("B"))
        assertFalse(gate.stage(token, "B"))
        assertFalse(gate.consume(token, "B"))
    }
    @Test fun sameBookSelectionAndResumptionReuseOnlyUnfinishedPlayback() {
        assertTrue(CarResumePolicy.reuse(finished = false, ended = false))
        assertFalse(CarResumePolicy.reuse(finished = true, ended = false))
        assertFalse(CarResumePolicy.reuse(finished = false, ended = true))
        assertFalse(CarResumePolicy.reuse(finished = true, ended = true))
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
