package dev.unpaged.android.shelves

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI

/** A partial response must match the requested byte offset before it can be appended.
 * If-Range prevents mixing versions when a server supplies an ETag/Last-Modified.
 * Servers ignoring Range restart the file rather than corrupting the recording. */
object ResumableFile {
    fun copy(url: String, file: File, checkActive: () -> Unit, progress: (Long, Long) -> Unit) {
        if (!attempt(url, file, checkActive, progress)) {
            // The partial file is longer than the recording (or otherwise stale): restart from zero, once.
            file.delete(); File(file.path + ".validator").delete()
            check(attempt(url, file, checkActive, progress)) { "The download could not be restarted." }
        }
    }
    /** Returns false only when the server rejected a stale offset and the caller should restart. */
    private fun attempt(url: String, file: File, checkActive: () -> Unit, progress: (Long, Long) -> Unit): Boolean {
        val validator = File(file.path + ".validator")
        val offset = file.length()
        val connection = URI(url).toURL().openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 15_000
        connection.setRequestProperty("Accept-Encoding", "identity")
        if (offset > 0) {
            connection.setRequestProperty("Range", "bytes=$offset-")
            if (validator.exists()) connection.setRequestProperty("If-Range", validator.readText())
        }
        try {
            checkActive()
            val code = connection.responseCode
            if (code == 416 && offset > 0) {
                val total = Regex("bytes \\*/(\\d+)").matchEntire(connection.getHeaderField("Content-Range") ?: "")?.groupValues?.get(1)?.toLongOrNull()
                if (total == offset) { progress(offset, offset); return true }
                return false
            }
            if (code != 200 && code != 206) throw IOException("The recording server returned HTTP $code.")
            val range = connection.getHeaderField("Content-Range")
            val matched = Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(range ?: "")
            val append = code == 206
            val total: Long
            if (append) {
                val values = matched?.groupValues ?: throw IOException("Invalid download range.")
                val start = values[1].toLong()
                val end = values[2].toLong()
                total = values[3].toLong()
                if (start != offset || end < start || end >= total ||
                    (connection.contentLengthLong >= 0 && connection.contentLengthLong != end - start + 1))
                    throw IOException("Invalid download range.")
            } else total = connection.contentLengthLong
            val token = connection.getHeaderField("ETag")?.takeUnless { it.startsWith("W/") }
                ?: connection.getHeaderField("Last-Modified")
            if (token != null) validator.writeText(token) else validator.delete()
            var copied = if (append) offset else 0L
            connection.inputStream.use { input ->
                FileOutputStream(file, append).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        checkActive()
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        copied += count
                        progress(copied, total)
                    }
                    output.fd.sync()
                }
            }
            if (copied <= 0 || (total >= 0 && copied != total)) throw IOException("The download was incomplete. Please try again.")
            return true
        } finally { connection.disconnect() }
    }
}
