package dev.unpaged.android.playback

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.nio.ByteBuffer

class Mp4ChaptersTest {
    private fun bytes(block: DataOutputStream.() -> Unit) = ByteArrayOutputStream().also { stream -> DataOutputStream(stream).use(block) }.toByteArray()
    private fun box(type: String, data: ByteArray) = bytes { writeInt(data.size + 8); writeBytes(type); write(data) }
    private fun concat(vararg parts: ByteArray) = parts.fold(byteArrayOf()) { a, b -> a + b }
    private fun read(data: ByteArray): List<ChapterMarker> {
        val file = File.createTempFile("chapters", ".m4b")
        return try { file.writeBytes(data); Mp4Chapters.read(file) } finally { file.delete() }
    }
    private fun nero(version: Int = 1) = box("moov", box("udta", box("chpl", bytes {
        writeByte(version); write(byteArrayOf(0, 0, 0)); if (version == 1) writeInt(0)
        writeByte(3)
        listOf("Opening", "Café", "Conclusion").forEachIndexed { index, title ->
            writeLong(index * 300_000_000L)
            val text = title.toByteArray(); writeByte(text.size); write(text)
        }
    })))
    @Test fun neroVersionsAndUnicode() {
        for (version in 0..1) {
            val chapters = read(nero(version))
            assertEquals(listOf(0L, 30_000L, 60_000L), chapters.map { it.startMs })
            assertEquals(listOf("Opening", "Café", "Conclusion"), chapters.map { it.title })
        }
    }
    private fun quickTime(co64: Boolean, fixed: Boolean, mdVersion: Int = 0, extra: ByteArray = byteArrayOf()): ByteArray {
        val samples = listOf("First", "Other", "Third").map { title -> bytes { writeShort(title.length); writeBytes(title) } }
        val mdat = box("mdat", concat(*samples.toTypedArray()))
        val tkhd = box("tkhd", bytes { writeInt(0); writeLong(0); writeInt(7) })
        val mdhd = box("mdhd", bytes {
            writeByte(mdVersion); write(byteArrayOf(0, 0, 0))
            if (mdVersion == 1) { writeLong(0); writeLong(0) } else writeLong(0)
            writeInt(1000); if (mdVersion == 1) writeLong(90_000) else writeInt(90_000)
            writeShort(0x55c4); writeShort(0) // und language, no preferred-locale filtering.
        })
        val stsd = box("stsd", bytes { writeInt(0); writeInt(1); write(box("text", ByteArray(8))) })
        val stsz = box("stsz", bytes { writeInt(0); writeInt(if (fixed) 7 else 0); writeInt(3); if (!fixed) repeat(3) { writeInt(7) } })
        val stts = box("stts", bytes { writeInt(0); writeInt(2); writeInt(2); writeInt(30_000); writeInt(1); writeInt(30_000) })
        val stsc = box("stsc", bytes { writeInt(0); writeInt(2); writeInt(1); writeInt(2); writeInt(1); writeInt(2); writeInt(1); writeInt(1) })
        val offsets = box(if (co64) "co64" else "stco", bytes {
            writeInt(0); writeInt(2)
            if (co64) { writeLong(8); writeLong(22) } else { writeInt(8); writeInt(22) }
        })
        val chapter = box("trak", concat(tkhd, box("mdia", concat(mdhd, box("minf", box("stbl", concat(stsd, stsz, stts, stsc, offsets)))))))
        val audio = box("trak", box("tref", box("chap", bytes { writeInt(7) })))
        return concat(mdat, box("moov", concat(extra, audio, chapter)))
    }
    @Test fun quickTimeMultipleChunkRunsAndOffsetWidths() {
        for (wide in listOf(false, true)) for (fixed in listOf(false, true)) for (version in 0..1) {
            val chapters = read(quickTime(wide, fixed, version))
            assertEquals(listOf("First", "Other", "Third"), chapters.map { it.title })
            assertEquals(listOf(0L, 30_000L, 60_000L), chapters.map { it.startMs })
            assertEquals(90_000L, chapters.last().endMs)
        }
    }
    @Test fun extendedAndZeroLengthBoxes() {
        val data = nero()
        val payload = data.copyOfRange(8, data.size)
        val extended = bytes { writeInt(1); writeBytes("moov"); writeLong(payload.size + 16L); write(payload) }
        assertEquals(3, read(extended).size)
        ByteBuffer.wrap(data).putInt(0)
        assertEquals(3, read(data).size)
    }
    @Test fun malformedAndTruncatedBoxesFailClosed() {
        val valid = quickTime(true, false)
        for (length in listOf(0, 7, 9, valid.size - 1)) assertTrue(read(valid.copyOf(length)).isEmpty())
        assertTrue(read(bytes { writeInt(Int.MAX_VALUE); writeBytes("moov") }).isEmpty())
        assertTrue(read(bytes { writeInt(1); writeBytes("moov"); writeLong(-1) }).isEmpty())
        assertTrue(read(box("mdat", ByteArray(100))).isEmpty())
    }
    @Test fun cachedEmptyAndChangedFilesAreReparsed() {
        val file = File.createTempFile("chapters", ".m4b")
        val cache = File(file.path + ".chapters")
        try {
            file.writeBytes(box("mdat", ByteArray(10)))
            assertTrue(Mp4Chapters.cached(file).isEmpty())
            file.writeBytes(nero())
            assertEquals(3, Mp4Chapters.cached(file).size)
            assertEquals(Mp4Chapters.read(file), Mp4Chapters.cached(file))
            cache.writeText("broken")
            assertEquals(3, Mp4Chapters.cached(file).size)
        } finally { file.delete(); cache.delete() }
    }
    @Test fun unusableChplFallsBackToQuickTimeTrack() {
        val oversized = box("udta", box("chpl", ByteArray(1_500_000)))
        val chapters = read(quickTime(false, true, extra = oversized))
        assertEquals(listOf("First", "Other", "Third"), chapters.map { it.title })
        val truncated = box("udta", box("chpl", bytes { writeByte(1); write(ByteArray(7)); writeByte(9) }))
        assertEquals(3, read(quickTime(true, false, extra = truncated)).size)
    }
    @Test fun versionZeroChplAcceptsReservedBytesLikeFfmpeg() {
        val payload = bytes {
            writeByte(0); write(byteArrayOf(0, 0, 0)); writeInt(0); writeByte(1)
            writeLong(50_000_000L); val t = "Only".toByteArray(); writeByte(t.size); write(t)
        }
        assertEquals(listOf("Only"), Mp4Chapters.parseChpl(payload).map { it.title })
        assertEquals(5_000L, Mp4Chapters.parseChpl(payload).single().startMs)
        assertTrue(Mp4Chapters.parseChpl(payload + byteArrayOf(1)).isEmpty())
    }
    @Test fun oversizedTitlesAreTruncatedAndNoTempFileLeaks() {
        val huge = "é".repeat(40_000) // 80,000 encoded bytes
        assertTrue(Mp4Chapters.cacheTitle(huge).toByteArray().size <= 65_535)
        assertEquals("short", Mp4Chapters.cacheTitle("short"))
        val file = File.createTempFile("chapters", ".m4b")
        val cache = File(file.path + ".chapters")
        try {
            val title = "x".repeat(70_000).toByteArray()
            val payload = bytes { writeByte(1); write(ByteArray(7)); writeByte(1); writeLong(0); writeByte(200); write(title, 0, 200) }
            file.writeBytes(box("moov", box("udta", box("chpl", payload))))
            assertEquals(1, Mp4Chapters.cached(file).size)
            assertTrue(cache.isFile)
            assertFalse(File(cache.path + ".tmp").exists())
        } finally { file.delete(); cache.delete(); File(cache.path + ".tmp").delete() }
    }
}
