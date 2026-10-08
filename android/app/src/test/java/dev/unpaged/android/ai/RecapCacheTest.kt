package dev.unpaged.android.ai

import android.content.Context
import dev.unpaged.android.UnpagedPreferences
import dev.unpaged.android.library.LibraryBook
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

@RunWith(RobolectricTestRunner::class)
class RecapCacheTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val book = LibraryBook("cache-test", "Title", "Author", emptyList(), currentPositionMs = 10_000)

    @Test fun cachePersistsSeparatelyAndDeletionRemovesIt() {
        val backedUp = context.getSharedPreferences("unpaged", Context.MODE_PRIVATE)
        val cache = RecapCache(context)
        val value = Recap("Recap.", "Headline")
        cache.save(book, value)
        assertFalse(backedUp.all.keys.any { it.startsWith("recap.") })
        assertTrue(context.getSharedPreferences("recap_cache", Context.MODE_PRIVATE).contains("recap.${book.id}"))
        val reopened = RecapCache(context)
        assertEquals(value, reopened.read(book, headline = true))
        assertNull(reopened.read(book.copy(currentTrackIndex = 1)))
        assertNull(reopened.read(book.copy(currentPositionMs = 20_000)))
        reopened.remove(book)
        assertNull(cache.read(book))
    }

    @Test fun firstPreferencesUseDropsAllLegacyRecapsAndPreservesSettings() {
        val backedUp = context.getSharedPreferences("unpaged", Context.MODE_PRIVATE)
        backedUp.edit().clear().putString("recap.one", "private text")
            .putString("recap.two", "more private text").putString("appearance", "dark").commit()
        val preferences = UnpagedPreferences(context)
        assertFalse(backedUp.all.keys.any { it.startsWith("recap.") })
        assertEquals("dark", preferences.text("appearance", "light"))
        assertTrue(backedUp.getBoolean("legacyRecapsRemoved", false))
        assertNull(RecapCache(context).read(book))
    }

    @Test fun enablingHeadlineRejectsHeadlineLessRecapAcrossReopen() {
        RecapCache(context).save(book, Recap("Recap.", null))
        val reopened = RecapCache(context)
        assertEquals(Recap("Recap.", null), reopened.read(book, headline = false))
        assertNull(reopened.read(book, headline = true))
        reopened.save(book, Recap("New recap.", "New headline"))
        assertEquals(Recap("New recap.", "New headline"), reopened.read(book, headline = true))
        assertEquals(Recap("New recap.", "New headline"), reopened.read(book, headline = false))
    }

    @Test fun everyBackupAndTransferPolicyExcludesRecapStore() {
        for ((file, policies) in listOf("backup_rules.xml" to listOf("full-backup-content"),
            "data_extraction_rules.xml" to listOf("cloud-backup", "device-transfer"))) {
            val document = DocumentBuilderFactory.newInstance().newDocumentBuilder()
                .parse(File("src/main/res/xml/$file"))
            for (policy in policies) {
                val element = document.getElementsByTagName(policy).item(0) as org.w3c.dom.Element
                val includes = element.getElementsByTagName("include")
                val sharedPrefs = (0 until includes.length).map { includes.item(it) as org.w3c.dom.Element }
                    .filter { it.getAttribute("domain") == "sharedpref" }.map { it.getAttribute("path") }
                assertEquals("$file/$policy preference allowlist", listOf("unpaged.xml"), sharedPrefs)
                val excludes = element.getElementsByTagName("exclude")
                assertTrue("$file/$policy must explicitly exclude recaps", (0 until excludes.length).any {
                    val exclude = excludes.item(it) as org.w3c.dom.Element
                    exclude.getAttribute("domain") == "sharedpref" && exclude.getAttribute("path") == "recap_cache.xml"
                })
            }
        }
    }
}
