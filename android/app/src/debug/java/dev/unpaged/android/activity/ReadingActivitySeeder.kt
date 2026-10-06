package dev.unpaged.android.activity

import android.os.Bundle
import dev.unpaged.android.MainActivity
import dev.unpaged.android.library.LibraryBook
import dev.unpaged.android.library.SQLiteLibraryStore
import java.time.LocalDate

/** Explicit debug entry only. Never called by production startup. */
object ReadingActivitySeeder {
    fun seed(store: SQLiteLibraryStore, daysTracked: Int = 113, reference: Boolean = false) {
        val books = store.books().take(6).ifEmpty { listOf(
            LibraryBook("sample-austen", "Pride and Prejudice", "Jane Austen", emptyList(), isFreeBook = true),
            LibraryBook("sample-melville", "Moby-Dick", "Herman Melville", emptyList(), isFreeBook = true),
            LibraryBook("sample-shelley", "Frankenstein", "Mary Shelley", emptyList(), isFreeBook = true),
            LibraryBook("sample-doyle", "The Adventures of Sherlock Holmes", "Arthur Conan Doyle", emptyList(), isFreeBook = true),
            LibraryBook("sample-wilde", "The Picture of Dorian Gray", "Oscar Wilde", emptyList(), isFreeBook = true),
            LibraryBook("sample-thoreau", "Walden", "Henry David Thoreau", emptyList(), isFreeBook = true)) }
        val random = SeededRandom()
        val weights = listOf(.42, .20, .18, .10, .06, .04)
        store.writableDatabase.beginTransaction()
        try {
            store.writableDatabase.delete("reading_sessions", null, null)
            fun save(day: LocalDate, hour: Int, minutes: Int, book: LibraryBook) {
                store.saveReadingSession(ReadingSession(day = day, hour = hour, minutes = minutes,
                    bookId = book.id, bookTitle = book.title, bookAuthor = book.author, isFreeBook = book.isFreeBook))
            }
            if (reference) save(LocalDate.now(), 20, 42, books.first())
            else for (offset in daysTracked - 1 downTo 0) {
                val day = LocalDate.now().minusDays(offset.toLong())
                val weekend = day.dayOfWeek.value >= 6
                val skip = (if (weekend) .16 else .30) - if (offset < 14) .08 else 0.0
                if (random.next() < skip) continue
                val count = 1 + (random.next() * if (weekend) 3 else 2).toInt()
                repeat(count) {
                    val r = random.next()
                    val hour = when { r < .12 -> 7 + (random.next() * 2).toInt(); r < .22 -> 12 + (random.next() * 2).toInt(); r < .55 -> 20 + (random.next() * 3).toInt(); r < .75 -> 21 + (random.next() * 2).toInt(); else -> (random.next() * 24).toInt() }
                    val length = random.next()
                    val minutes = when { length < .12 -> 4 + (random.next() * 8).toInt(); length < .70 -> 14 + (random.next() * 22).toInt(); else -> 36 + (random.next() * 55).toInt() }
                    val pick = random.next(); var weight = 0.0
                    val book = books.indices.firstOrNull { weight += weights[it]; pick <= weight }?.let { books[it] } ?: books.first()
                    save(day, hour, minutes, book)
                }
            }
            store.writableDatabase.setTransactionSuccessful()
        } finally { store.writableDatabase.endTransaction() }
    }
}
private class SeededRandom {
    private var state = 7
    fun next(): Double {
        state += 0x6D2B79F5
        var t = state
        t = (t xor (t ushr 15)) * (t or 1)
        t = t xor (t + ((t xor (t ushr 7)) * (t or 61)))
        return (t xor (t ushr 14)).toUInt().toDouble() / UInt.MAX_VALUE.toDouble()
    }
}
class ReadingFixtureActivity : MainActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent.getBooleanExtra("e2e-reading-fixture", false)) {
            val store = SQLiteLibraryStore(this)
            try { ReadingActivitySeeder.seed(store, reference = intent.getBooleanExtra("reference", false)) } finally { store.close() }
        }
        super.onCreate(savedInstanceState)
    }
}
