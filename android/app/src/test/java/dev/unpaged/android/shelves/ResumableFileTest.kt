package dev.unpaged.android.shelves

import java.net.ServerSocket
import kotlin.concurrent.thread
import java.net.InetSocketAddress
import java.io.File
import java.io.IOException
import org.junit.Assert.*
import org.junit.Test

class ResumableFileTest {
    private val data = ByteArray(250_000) { (it % 251).toByte() }
    private fun scenario(mode: String, action: (String, File, MutableList<String>) -> Unit) {
        val headers = mutableListOf<String>()
        val server = ServerSocket(0, 8, java.net.InetAddress.getByName("127.0.0.1"))
        val serving = thread(isDaemon = true) {
            while (!server.isClosed) {
                val socket = try { server.accept() } catch (_: IOException) { break }
                socket.use {
                    val reader = it.getInputStream().bufferedReader()
                    reader.readLine()
                    val request = generateSequence { reader.readLine()?.takeIf { line -> line.isNotEmpty() } }.toList()
                    val range = request.firstOrNull { line -> line.startsWith("Range:", true) }?.substringAfter(":")?.trim()
                    headers += range ?: "none"
                    val offset = range?.removePrefix("bytes=")?.removeSuffix("-")?.toInt() ?: 0
                    val start = if (mode == "ignore") 0 else offset
                    val stale = offset > 0 && (mode == "stale" || mode == "stale-forever")
                    val code = if (stale) 416 else if (offset > 0 && mode != "ignore") 206 else 200
                    val contentRange = if (stale) "Content-Range: bytes */${data.size}\r\n" else if (mode == "invalid") "Content-Range: bytes 0-9/${data.size}\r\n"
                        else if (code == 206) "Content-Range: bytes $offset-${data.size - 1}/${data.size}\r\n" else ""
                    val output = it.getOutputStream()
                    runCatching {
                        output.write(("HTTP/1.1 $code OK\r\nContent-Length: ${if (stale) 0 else data.size-start}\r\n" +
                            "ETag: \"stable\"\r\nConnection: close\r\n" + contentRange + "\r\n").toByteArray())
                        if (!stale) output.write(data, start, data.size - start)
                        output.flush()
                    }
                }
            }
        }
        val file = File.createTempFile("range", ".part")
        try { action("http://127.0.0.1:${server.localPort}/", file, headers) }
        finally { server.close(); serving.join(1000); file.delete(); File(file.path + ".validator").delete() }
    }
    @Test fun interruptionResumesExactBytes() = scenario("range") { url, file, headers ->
        var copied = 0L
        try {
            ResumableFile.copy(url, file, { if (copied > 0) throw IOException("interrupted") }) { bytes, _ -> copied = bytes }
            fail("Expected interruption")
        } catch (_: IOException) { }
        assertTrue(file.length() in 1 until data.size)
        val offset = file.length()
        ResumableFile.copy(url, file, {}, { _, _ -> })
        assertArrayEquals(data, file.readBytes())
        assertEquals(listOf("none", "bytes=$offset-"), headers)
    }
    @Test fun rangeIgnoringServerRestarts() = scenario("ignore") { url, file, _ ->
        file.writeBytes(data.copyOf(100))
        ResumableFile.copy(url, file, {}, { _, _ -> })
        assertArrayEquals(data, file.readBytes())
    }
    @Test fun wrongOffsetNeverAppends() = scenario("invalid") { url, file, _ ->
        file.writeBytes(data.copyOf(100))
        try { ResumableFile.copy(url, file, {}, { _, _ -> }); fail("Expected invalid range") } catch (_: IOException) { }
        assertEquals(100L, file.length())
    }
    @Test fun staleLargerPartialRestartsFromZero() = scenario("stale") { url, file, headers ->
        file.writeBytes(ByteArray(data.size + 500))
        File(file.path + ".validator").writeText("\"old\"")
        ResumableFile.copy(url, file, {}, { _, _ -> })
        assertArrayEquals(data, file.readBytes())
        assertEquals(listOf("bytes=${data.size + 500}-", "none"), headers)
    }
    @Test fun completePartialStillFinishesWithoutDownload() = scenario("stale") { url, file, headers ->
        file.writeBytes(data)
        ResumableFile.copy(url, file, {}, { _, _ -> })
        assertArrayEquals(data, file.readBytes())
        assertEquals(listOf("bytes=${data.size}-"), headers)
    }
}
