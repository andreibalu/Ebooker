package dev.unpaged.android.shelves

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class DownloadUpdatesTest {
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
