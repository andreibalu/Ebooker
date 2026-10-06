package dev.unpaged.android.library

import java.io.File
import java.io.InputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.Locale

data class LibraryTrack(
    val title: String,
    val originalName: String,
    val storedName: String,
    val durationMs: Long,
    val fingerprint: String,
)

data class LibraryBook(
    val id: String,
    val title: String,
    val author: String,
    val tracks: List<LibraryTrack>,
) {
    val durationMs: Long get() = tracks.sumOf { it.durationMs }
}

data class PendingImport(
    val id: String,
    val suggestedTitle: String,
    val suggestedAuthor: String,
    val tracks: List<LibraryTrack>,
)

interface ImportDocument {
    val displayName: String
    fun open(): InputStream
}

data class AudioMetadata(val durationMs: Long, val title: String? = null,
                         val artist: String? = null, val album: String? = null)

fun interface AudioMetadataReader { fun read(file: File): AudioMetadata }

/** Numeric filename runs compare without integer overflow; ties remain stable. */
object NaturalFilenameOrder : Comparator<String> {
    private val runs = Regex("[0-9]+|[^0-9]+")
    override fun compare(a: String, b: String): Int {
        val left = runs.findAll(a.lowercase(Locale.ROOT)).map { it.value }.toList()
        val right = runs.findAll(b.lowercase(Locale.ROOT)).map { it.value }.toList()
        for ((l, r) in left.zip(right)) {
            val result = if (l[0].isDigit() && r[0].isDigit()) {
                val ln = l.trimStart('0').ifEmpty { "0" }
                val rn = r.trimStart('0').ifEmpty { "0" }
                ln.length.compareTo(rn.length).takeIf { it != 0 } ?: ln.compareTo(rn)
            } else l.compareTo(r)
            if (result != 0) return result
        }
        return left.size.compareTo(right.size)
    }
}

object TrackIdentity {
    private const val CHUNK = 1024 * 1024
    /** iOS-compatible head/tail + u64LE(size) + u64LE(duration milliseconds). */
    fun fingerprint(file: File, durationMs: Long): String {
        require(durationMs >= 0)
        val digest = MessageDigest.getInstance("SHA-256")
        RandomAccessFile(file, "r").use { input ->
            val size = input.length()
            fun read(count: Int) {
                val bytes = ByteArray(count)
                input.readFully(bytes)
                digest.update(bytes)
            }
            if (size <= 2L * CHUNK) read(size.toInt()) else {
                read(CHUNK)
                input.seek(size - CHUNK)
                read(CHUNK)
            }
            digest.update(ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN)
                .putLong(size).putLong(durationMs).array())
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun matches(a: List<LibraryTrack>, b: List<LibraryTrack>): Boolean =
        a.isNotEmpty() && a.groupingBy { it.fingerprint }.eachCount() ==
            b.groupingBy { it.fingerprint }.eachCount()
}

class ImportProblem(val reason: Reason) : Exception() {
    enum class Reason { EMPTY, INVALID_AUDIO, DUPLICATE, TITLE, STORAGE }
}
