package dev.unpaged.android.playback

import org.junit.Assert.*
import org.junit.Test

class ArtworkThumbnailTest {
    @Test fun sampleSizeKeepsAtLeastTargetSide() {
        assertEquals(1, ArtworkThumbnail.sampleSize(400, 600))
        assertEquals(2, ArtworkThumbnail.sampleSize(1024, 1024))
        assertEquals(4, ArtworkThumbnail.sampleSize(2048, 2048))
        assertEquals(1, ArtworkThumbnail.sampleSize(2048, 700))
    }
    @Test fun missingCoverYieldsNull() {
        assertNull(ArtworkThumbnail.load(java.io.File("/nonexistent/cover.png"), java.io.File("/tmp/x"), "k"))
    }
}
