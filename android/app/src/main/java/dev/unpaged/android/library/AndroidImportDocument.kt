package dev.unpaged.android.library

import android.content.ContentResolver
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.io.IOException
import java.io.InputStream

class AndroidImportDocument(private val resolver: ContentResolver, private val uri: Uri) : ImportDocument {
    override val displayName: String = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME),
        null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(0) else null
    } ?: "Audio file"

    override fun open(): InputStream = resolver.openInputStream(uri) ?: throw IOException()
}

class AndroidAudioMetadataReader : AudioMetadataReader {
    override fun read(file: File): AudioMetadata {
        try {
            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(file.absolutePath)
                if ((0 until extractor.trackCount).none {
                        extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
                    }) throw ImportProblem(ImportProblem.Reason.INVALID_AUDIO)
            } finally { extractor.release() }
            val reader = MediaMetadataRetriever()
            try {
                reader.setDataSource(file.absolutePath)
                if (!File(file.parentFile, "cover.png").exists()) reader.embeddedPicture?.let { bytes ->
                    val options = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                    options.inJustDecodeBounds = false
                    var sample = 1
                    while (maxOf(options.outWidth, options.outHeight) / sample > 2048) sample *= 2
                    options.inSampleSize = sample
                    val bitmap = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                    if (bitmap != null) java.io.FileOutputStream(File(file.parentFile, "cover.png")).use { output ->
                        bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output); output.fd.sync()
                    }
                }
                fun text(key: Int) = reader.extractMetadata(key)
                return AudioMetadata(
                    text(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0,
                    text(MediaMetadataRetriever.METADATA_KEY_TITLE),
                    text(MediaMetadataRetriever.METADATA_KEY_ARTIST),
                    text(MediaMetadataRetriever.METADATA_KEY_ALBUM),
                )
            } finally { reader.release() }
        } catch (error: ImportProblem) { throw error }
        catch (_: IOException) { throw ImportProblem(ImportProblem.Reason.INVALID_AUDIO) }
        catch (_: RuntimeException) { throw ImportProblem(ImportProblem.Reason.INVALID_AUDIO) }
    }
}
