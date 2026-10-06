package dev.unpaged.android.activity

import dev.unpaged.android.library.LibraryBook
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.time.ZonedDateTime

class ReadingActivityTest {
    private val book = LibraryBook("book", "Title", "Author", emptyList())
    @Test fun chunkThresholdRoundsMinutesAndSnapshotsAtStartHour() {
        val rows = mutableListOf<ReadingSession>()
        var now = ZonedDateTime.parse("2026-10-06T23:59:50+03:00")
        val recorder = ReadingSessionRecorder(rows::add) { now }
        repeat(299) { recorder.tick(book) }
        assertTrue(rows.isEmpty())
        now = now.plusMinutes(5)
        recorder.tick(book)
        assertEquals(5, rows.single().minutes)
        assertEquals(23, rows.single().hour)
        assertEquals(LocalDate.of(2026, 10, 6), rows.single().day)
        assertEquals("Title", rows.single().bookTitle)
        repeat(30) { recorder.tick(book.copy(title = "Renamed")) }
        recorder.end()
        assertEquals(1, rows.last().minutes)
        assertEquals("Title", rows.last().bookTitle)
        assertEquals(LocalDate.of(2026, 10, 7), rows.last().day)
    }
    @Test fun shortNoiseDroppedAndSwitchAttributesOldAndNewBookSeparately() {
        val rows = mutableListOf<ReadingSession>()
        val recorder = ReadingSessionRecorder(rows::add)
        repeat(29) { recorder.tick(book) }; recorder.flush(); assertTrue(rows.isEmpty())
        repeat(30) { recorder.tick(book) }
        recorder.tick(book.copy(id = "other", title = "Other"))
        assertEquals("book", rows.single().bookId)
        repeat(89) { recorder.tick(book.copy(id = "other", title = "Other")) }
        recorder.end()
        assertEquals(2, rows.last().minutes); assertEquals("other", rows.last().bookId)
        recorder.flush(); assertEquals(2, rows.size)
    }
    @Test fun streaksTotalsAndMetadataRemainIndependentOfCurrentLibrary() {
        val today = LocalDate.of(2026, 10, 6)
        fun row(offset: Long, minutes: Int, author: String = "Author", free: Boolean = false) = ReadingSession(day = today.minusDays(offset), hour = 21, minutes = minutes, bookId = author, bookTitle = "Title $author", bookAuthor = author, isFreeBook = free)
        val stats = ReadingStats(listOf(row(0, 30), row(1, 60), row(2, 15), row(4, 120, "Other", true), row(5, 1), row(6, 2), row(7, 3)), 2, today)
        assertEquals(231, stats.totalMinutes); assertEquals(3, stats.currentStreak); assertEquals(4, stats.longestStreak)
        assertEquals(21, stats.bestHour); assertEquals(today.minusDays(4), stats.bestDay?.key)
        assertEquals("Other", stats.topAuthor?.key); assertEquals("Title Other", stats.longestBook?.bookTitle)
        assertEquals(120, stats.freeMinutes); assertEquals(52, stats.freePercent); assertEquals(8, stats.daysTracked)
        assertEquals(0, ReadingStats(listOf(row(1, 30)), 0, today).currentStreak)
        assertEquals(0, ReadingStats(emptyList(), 0, today).longestStreak)
    }
}
