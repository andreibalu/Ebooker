package dev.unpaged.android.playback

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.core.graphics.scale
import java.io.ByteArrayOutputStream
import java.io.File

/** Notification and lock-screen artwork travels over Binder with every MediaItem, so it must stay small.
 * The full-size cover.png is downscaled once to a JPEG cached per file version. */
object ArtworkThumbnail {
    const val SIDE = 512
    const val MAX_BYTES = 150 * 1024

    fun sampleSize(width: Int, height: Int, side: Int = SIDE): Int {
        var sample = 1
        while (width / (sample * 2) >= side && height / (sample * 2) >= side) sample *= 2
        return sample
    }

    fun load(cover: File, cacheDir: File, key: String): ByteArray? {
        if (!cover.isFile) return null
        val cached = File(cacheDir, "$key-${cover.lastModified()}-${cover.length()}.jpg")
        if (cached.isFile && cached.length() in 1..MAX_BYTES) return runCatching { cached.readBytes() }.getOrNull()
        val bytes = runCatching { render(cover) }.getOrNull() ?: return null
        runCatching {
            cacheDir.mkdirs()
            cacheDir.listFiles { f -> f.name.startsWith("$key-") }?.forEach { it.delete() }
            val temp = File(cacheDir, cached.name + ".tmp")
            temp.writeBytes(bytes)
            if (!temp.renameTo(cached)) temp.delete()
        }
        return bytes
    }

    private fun render(cover: File): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(cover.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val decoded = BitmapFactory.decodeFile(cover.path, BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight)
        }) ?: return null
        val scale = minOf(1f, SIDE.toFloat() / maxOf(decoded.width, decoded.height))
        val scaled = if (scale < 1f) decoded.scale((decoded.width * scale).toInt().coerceAtLeast(1),
            (decoded.height * scale).toInt().coerceAtLeast(1)) else decoded
        for (quality in intArrayOf(85, 70, 55, 40)) {
            val out = ByteArrayOutputStream()
            if (scaled.compress(Bitmap.CompressFormat.JPEG, quality, out) && out.size() <= MAX_BYTES) return out.toByteArray()
        }
        return null
    }
}
