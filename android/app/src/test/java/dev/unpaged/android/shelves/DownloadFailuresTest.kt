package dev.unpaged.android.shelves

import androidx.work.WorkInfo
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.IOException
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class DownloadFailuresTest {
    @Test fun onlyIoFailuresRetry() {
        assertTrue(DownloadFailures.retryable(IOException("network")))
        assertTrue(DownloadFailures.retryable(java.net.SocketTimeoutException()))
        assertFalse(DownloadFailures.retryable(IllegalArgumentException()))
        assertFalse(DownloadFailures.retryable(IllegalStateException("Download cancelled.")))
        assertFalse(DownloadFailures.retryable(NoSuchElementException()))
    }
    @Test fun reEnqueueDismissesEveryFinishedRowButNotActiveOnes() {
        fun info(state: WorkInfo.State) = WorkInfo(UUID.randomUUID(), state, setOf(LibriVoxDownloadWorker.name("1")))
        val failed = info(WorkInfo.State.FAILED); val cancelled = info(WorkInfo.State.CANCELLED)
        val succeeded = info(WorkInfo.State.SUCCEEDED); val running = info(WorkInfo.State.RUNNING)
        val ids = DownloadFailures.finishedIds(listOf(failed, cancelled, succeeded, running))
        assertEquals(setOf(failed.id, cancelled.id, succeeded.id).map { it.toString() }.toSet(), ids.toSet())
    }
}
