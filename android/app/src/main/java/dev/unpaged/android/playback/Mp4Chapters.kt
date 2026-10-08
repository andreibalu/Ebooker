package dev.unpaged.android.playback

import java.io.File
import java.io.RandomAccessFile
import java.io.DataInputStream
import java.io.DataOutputStream

/** Bounded random-access reader: mdat is never loaded into memory. Unsupported/malformed
 * chapter metadata leaves the existing file/ID3 chapter fallback intact. Language is
 * deliberately unrestricted, including QuickTime's undetermined "und" locale. */
object Mp4Chapters {
    private const val MAX = 10_000
    private data class Box(val type: String, val data: Long, val end: Long)
    fun read(file: File): List<ChapterMarker> = try {
        RandomAccessFile(file, "r").use reader@{ f ->
            fun boxes(start: Long, end: Long): List<Box> {
                val result = mutableListOf<Box>()
                var p = start
                while (p <= end - 8 && result.size < MAX) {
                    f.seek(p)
                    var size = f.readInt().toLong() and 0xffffffffL
                    val type = ByteArray(4).also(f::readFully).toString(Charsets.ISO_8859_1)
                    var header = 8
                    if (size == 1L) { require(p <= end - 16); size = f.readLong(); header = 16 }
                    if (size == 0L) size = end - p
                    require(size >= header && size <= end - p)
                    result += Box(type, p + header, p + size)
                    p += size
                }
                return result
            }
            fun children(b: Box) = boxes(b.data, b.end)
            fun child(b: Box, name: String) = children(b).firstOrNull { it.type == name }
            fun uint(): Long = f.readInt().toLong() and 0xffffffffL
            fun payload(b: Box): ByteArray {
                require(b.end - b.data <= 1024 * 1024)
                f.seek(b.data)
                return ByteArray((b.end - b.data).toInt()).also(f::readFully)
            }
            val moov = boxes(0, f.length()).firstOrNull { it.type == "moov" } ?: return@reader emptyList<ChapterMarker>()
            val nero = child(moov, "udta")?.let { child(it, "chpl") } ?: child(moov, "chpl")
            if (nero != null) {
                // A malformed Nero list must not hide a valid QuickTime chapter track.
                val result = runCatching { parseChpl(payload(nero)) }.getOrNull().orEmpty()
                if (result.isNotEmpty()) return@reader result
            }
            val tracks = children(moov).filter { it.type == "trak" }
            val chapterIDs = tracks.flatMap { t ->
                child(t, "tref")?.let { child(it, "chap") }?.let { b ->
                    require((b.end - b.data) % 4 == 0L)
                    f.seek(b.data)
                    List(((b.end - b.data) / 4).toInt().coerceAtMost(MAX)) { uint() }
                }.orEmpty()
            }.toSet()
            for (track in tracks) {
                val tkhd = child(track, "tkhd") ?: continue
                f.seek(tkhd.data)
                val version = f.readUnsignedByte()
                f.seek(tkhd.data + if (version == 1) 20 else 12)
                val id = uint()
                if (id !in chapterIDs) continue
                val mdia = child(track, "mdia") ?: continue
                val mdhd = child(mdia, "mdhd") ?: continue
                f.seek(mdhd.data)
                val mdVersion = f.readUnsignedByte()
                f.seek(mdhd.data + if (mdVersion == 1) 20 else 12)
                val timescale = uint()
                require(timescale > 0)
                val stbl = child(mdia, "minf")?.let { child(it, "stbl") } ?: continue
                val stsd = child(stbl, "stsd") ?: continue
                require(stsd.end - stsd.data >= 16)
                val formats = boxes(stsd.data + 8, stsd.end)
                if (formats.none { it.type == "text" || it.type == "tx3g" }) continue
                val stsz = child(stbl, "stsz") ?: continue
                f.seek(stsz.data + 4)
                val constantSize = uint()
                val count = uint().also { require(it in 1..MAX.toLong()) }.toInt()
                require(constantSize != 0L || stsz.end - f.filePointer >= count * 4L)
                val sizes = List(count) { if (constantSize > 0) constantSize else uint() }
                val stts = child(stbl, "stts") ?: continue
                f.seek(stts.data + 4)
                val timeCount = uint().also { require(it in 1..MAX.toLong()) }.toInt()
                require(stts.end - f.filePointer >= timeCount * 8L)
                val durations = mutableListOf<Long>()
                repeat(timeCount) {
                    val n = uint().also { require(it <= count - durations.size) }.toInt()
                    val duration = uint()
                    repeat(n) { durations += duration }
                }
                require(durations.size == count)
                val stsc = child(stbl, "stsc") ?: continue
                f.seek(stsc.data + 4)
                val mapCount = uint().also { require(it in 1..MAX.toLong()) }.toInt()
                require(stsc.end - f.filePointer >= mapCount * 12L)
                val mapping = List(mapCount) { Triple(uint(), uint(), uint()) }
                require(mapping.first().first == 1L && mapping.zipWithNext().all { it.first.first < it.second.first })
                val offsetsBox = child(stbl, "stco") ?: child(stbl, "co64") ?: continue
                f.seek(offsetsBox.data + 4)
                val chunkCount = uint().also { require(it in 1..MAX.toLong()) }.toInt()
                require(offsetsBox.end - f.filePointer >= chunkCount * if (offsetsBox.type == "co64") 8L else 4L)
                val offsets = List(chunkCount) { if (offsetsBox.type == "co64") f.readLong() else uint() }
                var sample = 0
                var time = 0L
                val result = mutableListOf<ChapterMarker>()
                offsets.forEachIndexed { chunk, offset ->
                    var pos = offset
                    val perChunk = mapping.lastOrNull { it.first <= chunk + 1L }?.second ?: 0
                    require(perChunk in 1..count.toLong())
                    repeat(perChunk.toInt()) {
                        require(sample < count)
                        val size = sizes[sample]
                        require(size in 2..65536 && pos >= 0 && pos <= f.length() - size)
                        f.seek(pos)
                        val length = f.readUnsignedShort()
                        require(length <= size - 2)
                        val bytes = ByteArray(length).also(f::readFully)
                        val title = if (bytes.size >= 2 && ((bytes[0] == 0xfe.toByte() && bytes[1] == 0xff.toByte()) ||
                                    (bytes[0] == 0xff.toByte() && bytes[1] == 0xfe.toByte())))
                            bytes.toString(Charsets.UTF_16) else bytes.toString(Charsets.UTF_8)
                        val end = Math.addExact(time, durations[sample])
                        result += ChapterMarker(title, Math.multiplyExact(time, 1000) / timescale, Math.multiplyExact(end, 1000) / timescale)
                        time = end
                        pos += size
                        sample++
                    }
                }
                require(sample == count)
                if (result.isNotEmpty()) return@reader result
            }
            emptyList<ChapterMarker>()
        }
    } catch (_: Exception) { emptyList() }

    /** Version 1 (and ffmpeg's reading of version 0) carries 4 reserved bytes before the count;
     * a version-0 box without them is also accepted. The layout that consumes the payload exactly wins. */
    internal fun parseChpl(bytes: ByteArray): List<ChapterMarker> {
        val version = bytes.firstOrNull()?.toInt()?.and(0xff) ?: return emptyList()
        val layouts = if (version == 0) listOf(true, false) else listOf(true)
        for (reserved in layouts) {
            val parsed = runCatching {
                DataInputStream(bytes.inputStream()).use { input ->
                    input.skipBytes(4)
                    if (reserved) input.skipBytes(4)
                    val count = input.readUnsignedByte()
                    val markers = (0 until count).map {
                        val start = input.readLong()
                        require(start >= 0)
                        val title = ByteArray(input.readUnsignedByte()).also(input::readFully).toString(Charsets.UTF_8)
                        ChapterMarker(title, start / 10_000, start / 10_000)
                    }
                    require(input.available() == 0)
                    markers
                }
            }.getOrNull()
            if (parsed != null) return parsed
        }
        return emptyList()
    }

    /** writeUTF is limited to 65535 encoded bytes; cut on a character boundary. */
    internal fun cacheTitle(title: String): String {
        var text = title
        while (text.isNotEmpty() && modifiedUtf8Length(text) > 65_535) text = text.take(text.length - maxOf(1, (modifiedUtf8Length(text) - 65_535) / 3))
        return text
    }
    private fun modifiedUtf8Length(text: String) = text.sumOf { c -> when { c.code in 1..0x7f -> 1; c.code <= 0x7ff -> 2; else -> 3 }.toInt() }

    /** Sidecar belongs to the copied audio directory and moves/deletes with the book.
     * Cache misses are read on IO at import and before loading existing local books. */
    fun cached(file: File): List<ChapterMarker> {
        if (file.extension.lowercase() !in setOf("m4b", "m4a", "mp4")) return emptyList()
        val cache = File(file.parentFile, file.name + ".chapters")
        val hit = runCatching {
            DataInputStream(cache.inputStream().buffered()).use { input ->
                require(input.readInt() == 1 && input.readLong() == file.length() && input.readLong() == file.lastModified())
                val count = input.readInt().also { require(it in 0..MAX) }
                List(count) { ChapterMarker(input.readUTF(), input.readLong(), input.readLong()) }
            }
        }.getOrNull()
        if (hit != null) return hit
        val markers = read(file)
        val temp = File(cache.path + ".tmp")
        val saved = runCatching {
            DataOutputStream(temp.outputStream().buffered()).use { out ->
                out.writeInt(1); out.writeLong(file.length()); out.writeLong(file.lastModified()); out.writeInt(markers.size)
                markers.forEach { out.writeUTF(cacheTitle(it.title)); out.writeLong(it.startMs); out.writeLong(it.endMs) }
            }
            temp.renameTo(cache)
        }.getOrDefault(false)
        if (!saved) temp.delete()
        return markers
    }
}
