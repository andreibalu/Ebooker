package dev.unpaged.android.activity

import dev.unpaged.android.library.LibraryBook
import java.time.LocalDate
import java.time.ZonedDateTime
import java.util.UUID
import kotlin.math.roundToInt

data class ReadingSession(val id: String = UUID.randomUUID().toString(), val day: LocalDate,
    val hour: Int, val minutes: Int, val bookId: String, val bookTitle: String,
    val bookAuthor: String, val isFreeBook: Boolean, val createdAt: Long = System.currentTimeMillis())

/** Wall time, independent of playback speed and seek position. Metadata survives book deletion. */
class ReadingSessionRecorder(private val save: (ReadingSession) -> Unit,
    private val clock: () -> ZonedDateTime = { ZonedDateTime.now() }) {
    private var book: LibraryBook? = null
    private var start: ZonedDateTime? = null
    private var seconds = 0.0
    fun tick(current: LibraryBook, elapsed: Double = 1.0) {
        require(elapsed.isFinite() && elapsed >= 0)
        if (book?.id != current.id) { flush(); book = current }
        if (start == null) start = clock()
        seconds += elapsed
        if (seconds >= 300) flush()
    }
    fun flush() {
        val active = book
        val whenStarted = start
        if (active != null && whenStarted != null && seconds >= 30) {
            save(ReadingSession(day = whenStarted.toLocalDate(), hour = whenStarted.hour,
                minutes = (seconds / 60).roundToInt().coerceAtLeast(1), bookId = active.id,
                bookTitle = active.title, bookAuthor = active.author.ifBlank { "Unknown Author" }, isFreeBook = active.isFreeBook))
        }
        seconds = 0.0; start = null
    }
    fun end() { flush(); book = null }
}

data class ReadingStats(val sessions: List<ReadingSession>, val booksFinished: Int,
    val today: LocalDate = LocalDate.now()) {
    val totalMinutes = sessions.sumOf { it.minutes }
    val days = sessions.groupBy { it.day }.mapValues { (_, rows) -> rows.sumOf { it.minutes } }
    val firstDay = days.keys.minOrNull()?.coerceAtMost(today) ?: today
    val daysTracked = java.time.temporal.ChronoUnit.DAYS.between(firstDay, today).toInt() + 1
    val hours = List(24) { h -> sessions.filter { it.hour == h }.sumOf { it.minutes } }
    val weekdays = List(7) { d -> sessions.filter { it.day.dayOfWeek.value - 1 == d }.sumOf { it.minutes } }
    val bestHour = hours.indices.maxByOrNull { hours[it] } ?: 0
    val bestDow = weekdays.indices.maxByOrNull { weekdays[it] } ?: 0
    val bestDay = days.entries.sortedBy { it.key }.maxByOrNull { it.value }
    val bookMinutes = sessions.groupBy { it.bookId }.mapValues { (_, rows) -> rows.sumOf { it.minutes } }
    val longestBook = bookMinutes.entries.maxByOrNull { it.value }?.let { entry -> sessions.first { it.bookId == entry.key } }
    val authors = sessions.groupBy { it.bookAuthor }.filterKeys { it.isNotBlank() }.mapValues { (_, rows) -> rows.sumOf { it.minutes } }
    val topAuthor = authors.entries.maxByOrNull { it.value }
    val freeMinutes = sessions.filter { it.isFreeBook }.sumOf { it.minutes }
    val freePercent = if (totalMinutes == 0) 0 else (100.0 * freeMinutes / totalMinutes).roundToInt()
    val averageSession = if (sessions.isEmpty()) 0.0 else totalMinutes.toDouble() / sessions.size
    val currentStreak = generateSequence(today) { it.minusDays(1) }.takeWhile { days.containsKey(it) }.count()
    val longestStreak: Int = run {
        var longest = 0; var streak = 0; var previous: LocalDate? = null
        days.keys.filter { it <= today }.sorted().forEach { day ->
            streak = if (previous?.plusDays(1) == day) streak + 1 else 1
            longest = maxOf(longest, streak); previous = day
        }; longest
    }
}
fun activityDuration(minutes: Int): String = when {
    minutes < 60 -> "${minutes}m"
    minutes % 60 == 0 -> "${minutes / 60}h"
    else -> "${minutes / 60}h ${minutes % 60}m"
}
