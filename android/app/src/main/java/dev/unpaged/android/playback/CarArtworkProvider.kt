package dev.unpaged.android.playback

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.media.session.MediaSessionManager
import android.net.Uri
import android.os.Binder
import android.os.Build
import android.os.ParcelFileDescriptor
import dev.unpaged.android.library.SQLiteLibraryStore
import dev.unpaged.android.shelves.Classics
import dev.unpaged.android.shelves.SQLiteCatalogStore
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest

internal object BrowserCallerPolicy {
    fun allowed(caller: String, own: String, trusted: Boolean, debug: Boolean) =
        caller == own || trusted || debug || caller in setOf("com.google.android.projection.gearhead", "com.android.car.media")
}

internal object CarArtwork {
    /** Single-row lookups, so listing N covers is O(N) rather than loading every book per cover. */
    fun title(context: android.content.Context, id: String): String? = when {
        id.startsWith("book:") -> SQLiteLibraryStore(context).let { store ->
            try { store.title(id.removePrefix("book:")) } finally { store.close() }
        }
        id.startsWith("catalog:") && id.removePrefix("catalog:") in Classics.ids -> SQLiteCatalogStore(context).let { store ->
            try { store.title(id.removePrefix("catalog:")) } finally { store.close() }
        }
        else -> null
    }
    fun fileName(id: String, title: String) =
        MessageDigest.getInstance("SHA-256").digest("$id\u0000$title".toByteArray()).joinToString("") { "%02x".format(it) } + ".png"
}

/** Car clients can read generated covers, never audio files or arbitrary paths. */
class CarArtworkProvider : ContentProvider() {
    companion object {
        fun uri(context: android.content.Context, mediaId: String): Uri = Uri.Builder()
            .scheme("content").authority("${context.packageName}.car-artwork").appendPath(mediaId).build()
    }
    override fun onCreate() = true
    override fun getType(uri: Uri) = "image/png"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
    @Synchronized override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val context = requireNotNull(context)
        val caller = callingPackage ?: context.packageName.takeIf { Binder.getCallingUid() == android.os.Process.myUid() }
            ?: throw SecurityException("Unknown artwork caller")
        val trusted = if (Build.VERSION.SDK_INT >= 28) context.getSystemService(MediaSessionManager::class.java)
            .isTrustedForMediaControl(MediaSessionManager.RemoteUserInfo(caller, Binder.getCallingPid(), Binder.getCallingUid()))
            else context.checkPermission("android.permission.MEDIA_CONTENT_CONTROL", Binder.getCallingPid(), Binder.getCallingUid()) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!BrowserCallerPolicy.allowed(caller, context.packageName, trusted, debugBrowserAllowed(caller))) throw SecurityException("Artwork access denied")
        if (mode != "r" || uri.authority != "${context.packageName}.car-artwork" || uri.pathSegments.size != 1) throw FileNotFoundException()
        val id = uri.pathSegments.single()
        val title = CarArtwork.title(context, id) ?: throw FileNotFoundException("Unknown book")
        val file = File(File(context.cacheDir, "car-artwork"), CarArtwork.fileName(id, title)).also { it.parentFile?.mkdirs() }
        val directory = file.parentFile!!
        val hash = file.nameWithoutExtension
        if (!file.exists()) {
            val temporary = File(directory, "$hash.tmp")
            temporary.writeBytes(GeneratedArtwork.png(title))
            check(temporary.renameTo(file))
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }
}
