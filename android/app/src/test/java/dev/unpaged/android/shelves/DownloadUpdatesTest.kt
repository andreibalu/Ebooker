package dev.unpaged.android.shelves

import androidx.work.WorkInfo
import androidx.work.workDataOf
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class DownloadUpdatesTest {
    @Test fun progressUsesOnlyWorkTitlesAndCompletionInvalidatesOnce() {
        val queried = mutableListOf<String>()
        val updates = DownloadUpdates { id -> queried += id; "Title $id" }
        val id = UUID.randomUUID()
        fun info(state: WorkInfo.State, progress: Int) = WorkInfo(id, state,
            setOf(LibriVoxDownloadWorker.name("133")), progress = workDataOf(LibriVoxDownloadWorker.PROGRESS to progress))
        assertFalse(updates.observe(listOf(info(WorkInfo.State.RUNNING, 0))).finishedChanged)
        repeat(10) { assertFalse(updates.observe(listOf(info(WorkInfo.State.RUNNING, it * 10))).finishedChanged) }
        assertEquals(listOf("133"), queried)
        val completed = updates.observe(listOf(info(WorkInfo.State.SUCCEEDED, 100)))
        assertEquals("Title 133", completed.titles["133"])
        assertTrue(completed.finishedChanged)
        assertFalse(updates.observe(listOf(info(WorkInfo.State.SUCCEEDED, 100))).finishedChanged)
        assertTrue(updates.observe(listOf(info(WorkInfo.State.FAILED, 20))).finishedChanged)
        assertFalse(updates.observe(listOf(info(WorkInfo.State.FAILED, 20))).finishedChanged)
    }
    @Test fun targetedTitleLookupDoesNotDecodeUnrelatedCatalogRows() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("librivox-catalog.db")
        val catalog = SQLiteCatalogStore(context)
        try {
            catalog.seed(listOf(CatalogBook("133", "Jane Eyre", "Author", "", "English", 60)))
            catalog.writableDatabase.execSQL("INSERT INTO catalog VALUES ('unrelated', 'invalid json')")
            assertEquals("Jane Eyre", catalog.title("133"))
            assertNull(catalog.title("missing"))
        } finally { catalog.close() }
    }
}
