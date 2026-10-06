package dev.unpaged.android.library

import dev.unpaged.android.LibrarySort
import dev.unpaged.android.UnpagedPreferences
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class LibraryPreferencesTest {
    @Test fun independentSortsAndListeningPreferencesSurviveNewOwner() {
        val context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("unpaged", 0).edit().clear().commit()
        val preferences = UnpagedPreferences(context)
        assertEquals(LibrarySort.RECENT, preferences.sort("Favorites"))
        assertFalse(preferences.shelvesFirst())
        assertEquals("system", preferences.text("appAppearance", "system"))
        preferences.setSort("Library", LibrarySort.TITLE)
        preferences.setSort("Favorites", LibrarySort.DURATION)
        preferences.setSeconds("skipBackSeconds", 45)
        preferences.setText("appAppearance", "dark")
        preferences.setShelvesFirst(true)
        val reopened = UnpagedPreferences(context)
        assertEquals(LibrarySort.TITLE, reopened.sort("Library"))
        assertEquals(LibrarySort.DURATION, reopened.sort("Favorites"))
        assertEquals(45, reopened.seconds("skipBackSeconds", 30))
        assertEquals("dark", reopened.text("appAppearance", "system"))
        assertTrue(reopened.shelvesFirst())
    }

    @Test fun sortUsesIosOrderingIncludingUnplayedDatesAndUnknownAuthor() {
        val books = listOf(
            LibraryBook("a", "Zulu", "", emptyList(), dateAdded = 100),
            LibraryBook("b", "alpha", "Beta", listOf(LibraryTrack("t", "", "", 1000, "")), dateAdded = 200),
            LibraryBook("c", "Middle", "Alpha", emptyList(), lastPlayedAt = 300, dateAdded = 50))
        assertEquals(listOf("c", "b", "a"), sortedBooks(books, LibrarySort.RECENT).map { it.id })
        assertEquals(listOf("b", "c", "a"), sortedBooks(books, LibrarySort.TITLE).map { it.id })
        assertEquals(listOf("c", "b", "a"), sortedBooks(books, LibrarySort.AUTHOR).map { it.id })
        assertEquals("b", sortedBooks(books, LibrarySort.DURATION).first().id)
        assertEquals(listOf("b", "a", "c"), sortedBooks(books, LibrarySort.DATE_ADDED).map { it.id })
    }
}
