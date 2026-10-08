package dev.unpaged.android.shelves

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files

class DownloadFilesTest {
    @Test fun coverCreatedBetweenTracksDoesNotSplitTheDownload() {
        val root = Files.createTempDirectory("download-handoff").toFile()
        try {
            val staging = File(root, "staging").apply { mkdirs() }
            val final = File(root, "final")
            File(staging, "0000.mp3").writeText("first")
            final.mkdirs(); File(final, "cover.png").writeText("custom cover")
            File(staging, "0001.mp3").writeText("second")
            File(final, "0002.mp3").writeText("third")
            val names = listOf("0000.mp3", "0001.mp3", "0002.mp3")
            DownloadFiles.finish(staging, final, names)
            assertEquals(listOf("first", "second", "third"), names.map { File(final, it).readText() })
            assertEquals("custom cover", File(final, "cover.png").readText())
            DownloadFiles.finish(staging, final, names)
            assertTrue(names.all { File(final, it).isFile })
        } finally { root.deleteRecursively() }
    }
    @Test fun missingTrackPreventsPromotionHandoff() {
        val root = Files.createTempDirectory("missing-download").toFile()
        try {
            assertThrows(IllegalStateException::class.java) {
                DownloadFiles.finish(File(root, "staging"), File(root, "final"), listOf("missing.mp3"))
            }
        } finally { root.deleteRecursively() }
    }
}
