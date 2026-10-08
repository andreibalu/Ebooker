package dev.unpaged.android.playback

import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import dev.unpaged.android.UnpagedApplication
import dev.unpaged.android.library.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.lang.reflect.Proxy

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = UnpagedApplication::class)
@androidx.annotation.OptIn(UnstableApi::class)
class PlayerMetadataTest {
    private val app get() = RuntimeEnvironment.getApplication() as UnpagedApplication
    private lateinit var controller: PlayerController
    private lateinit var store: SQLiteLibraryStore
    private lateinit var model: LibraryViewModel
    private val items = mutableListOf<MediaItem>()
    private val commands = mutableListOf<String>()
    private var position = 0L
    private var playing = false
    private var speed = 1f
    private val book = LibraryBook("metadata", "Old title", "Author",
        listOf(LibraryTrack("Track", "1.m4b", "1.m4b", 90000, "fingerprint")))
    private val folder get() = File(app.filesDir, "audiobooks/${book.id}")
    private val engine: Player = Proxy.newProxyInstance(Player::class.java.classLoader, arrayOf(Player::class.java)) { _, method, args ->
        when (method.name) {
            "addListener", "removeListener" -> null
            "getMediaItemCount" -> items.size
            "getMediaItemAt" -> items[args!![0] as Int]
            "getCurrentMediaItemIndex" -> 0
            "getCurrentPosition" -> position
            "getDuration" -> 90000L
            "getPlaybackState" -> Player.STATE_READY
            "getPlaybackParameters" -> PlaybackParameters(speed)
            "isPlaying", "getPlayWhenReady" -> playing
            "setMediaItems" -> {
                commands += method.name
                @Suppress("UNCHECKED_CAST") val queue = args!![0] as List<MediaItem>
                items.clear(); items.addAll(queue); position = args[2] as Long; null
            }
            "replaceMediaItem" -> { commands += method.name; items[args!![0] as Int] = args[1] as MediaItem; null }
            "setPlaybackSpeed" -> { commands += method.name; speed = args!![0] as Float; null }
            "play" -> { commands += method.name; playing = true; null }
            "pause", "stop" -> { commands += method.name; playing = false; null }
            "prepare", "clearMediaItems" -> { commands += method.name; null }
            else -> error("Unexpected player command ${method.name}")
        }
    } as Player
    @Before fun setup() {
        // The attached fake engine owns playback; this test doesn't bind a real service.
        shadowOf(app).declareComponentUnbindable(android.content.ComponentName(app, PlaybackService::class.java))
        app.deleteDatabase("library.db")
        folder.deleteRecursively(); folder.mkdirs()
        File(folder, "1.m4b").writeBytes(chapters())
        store = SQLiteLibraryStore(app); store.insert(book)
        controller = app.player; controller.attach(engine)
        model = LibraryViewModel(app)
        await { !model.state.value.loading }
    }
    @After fun cleanup() { controller.detach(); store.close(); folder.deleteRecursively() }
    private fun await(condition: () -> Boolean) {
        val until = System.nanoTime() + 5_000_000_000L
        while (!condition() && System.nanoTime() < until) {
            shadowOf(Looper.getMainLooper()).idle(); Thread.sleep(10)
        }
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue("Async operation completed", condition())
    }
    private fun start() {
        controller.playMoment(book, LibraryMoment("moment", book.id, 0, 35000, "Moment"))
        await { controller.state.value.book?.id == book.id && items.isNotEmpty() }
        commands.clear()
    }
    @Test fun momentPlaybackKeepsEmbeddedChaptersAndCustomArtwork() {
        val cover = GeneratedArtwork.png("Custom")
        File(folder, "cover.png").writeBytes(cover)
        start()
        assertEquals(35000L, controller.state.value.positionMs)
        assertEquals(listOf("Opening", "Second"), controller.state.value.chapters.map { it.title })
        val shown = items.single().mediaMetadata.artworkData!!
        assertTrue(shown.size <= ArtworkThumbnail.MAX_BYTES)
        assertFalse(shown.contentEquals(GeneratedArtwork.png(book.title)))
    }
    @Test fun renameUpdatesActiveTitleWithoutReloadingOrSeeking() {
        start()
        model.rename(book, "  New title  ")
        await { !model.state.value.busy && controller.state.value.book?.title == "New title" }
        assertNull(model.state.value.error)
        assertEquals("New title", items.single().mediaMetadata.title)
        assertEquals("New title", items.single().mediaMetadata.albumTitle)
        assertUninterrupted()
    }
    @Test fun coverReplacementAndRemovalUpdateActiveArtworkWithoutReloading() {
        start()
        val bitmap = android.graphics.Bitmap.createBitmap(2, 2, android.graphics.Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.RED)
        model.saveCover(book, bitmap)
        await { !model.state.value.busy && controller.state.value.book!!.coverRevision > 0 }
        assertNull(model.state.value.error)
        val shown = items.single().mediaMetadata.artworkData!!
        assertTrue(shown.size <= ArtworkThumbnail.MAX_BYTES)
        assertFalse(shown.contentEquals(GeneratedArtwork.png(book.title)))
        assertUninterrupted()
        commands.clear()
        model.saveCover(book, null)
        await { !model.state.value.busy && controller.state.value.book!!.coverRevision == 0L }
        assertArrayEquals(GeneratedArtwork.png(book.title), items.single().mediaMetadata.artworkData)
        assertUninterrupted()
    }
    @Test fun editsToOtherBooksLeaveTheActiveBookAlone() {
        start()
        val other = book.copy(id = "other", title = "Other")
        store.insert(other)
        model.rename(other, "Changed")
        await { !model.state.value.busy }
        assertEquals(book.title, controller.state.value.book!!.title)
        assertTrue(commands.isEmpty())
    }
    private fun assertUninterrupted() {
        assertEquals(listOf("replaceMediaItem"), commands)
        assertEquals(35000L, position)
        assertTrue(playing)
        assertEquals(35000L, controller.state.value.positionMs)
        assertTrue(controller.state.value.playing)
        assertEquals(listOf("Opening", "Second"), controller.state.value.chapters.map { it.title })
    }
    private fun chapters(): ByteArray {
        fun bytes(block: DataOutputStream.() -> Unit) = ByteArrayOutputStream().also { DataOutputStream(it).use(block) }.toByteArray()
        fun box(type: String, data: ByteArray) = bytes { writeInt(data.size + 8); writeBytes(type); write(data) }
        return box("moov", box("udta", box("chpl", bytes {
            writeInt(0x01000000); writeInt(0); writeByte(2)
            listOf("Opening", "Second").forEachIndexed { index, title ->
                writeLong(index * 300_000_000L); writeByte(title.length); writeBytes(title)
            }
        })))
    }
}
