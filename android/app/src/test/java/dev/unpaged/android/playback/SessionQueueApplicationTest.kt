package dev.unpaged.android.playback

import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import dev.unpaged.android.UnpagedApplication
import dev.unpaged.android.equalizer.EqualizerConfiguration
import dev.unpaged.android.library.LibraryBook
import dev.unpaged.android.library.LibraryTrack
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.lang.reflect.Proxy

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = UnpagedApplication::class)
@androidx.annotation.OptIn(UnstableApi::class)
class SessionQueueApplicationTest {
    private fun book(id: String, preamp: Double) = LibraryBook(id, id, "Author",
        listOf(LibraryTrack("Track", "1.wav", "1.wav", 120000, id)),
        equalizerJson = EqualizerConfiguration(preampDB = preamp).json())

    @Test fun unrelatedDisconnectCommitsMatchingBookQueuePositionAndEqualizerTogether() {
        withController { controller, engine ->
            val a = book("A", 1.0); val b = book("B", 5.0)
            apply(controller, a, 1000)
            val token = controller.beginSessionQueue("X")
            val queue = controller.stageSessionQueue(token, b, items(b), 0, 25000, true)
            assertEquals("A", controller.state.value.book?.id)
            assertEquals(1.0, controller.equalizer.value.preampDB, 0.0)
            controller.sessionControllerDisconnected("Y")
            engine.beforeSet = {
                assertEquals("B", controller.state.value.book?.id)
                assertEquals(5.0, controller.equalizer.value.preampDB, 0.0)
            }
            controller.setSessionMediaItems(queue.mediaItems, queue.startIndex, queue.startPositionMs)
            assertEquals("B:0", engine.items.single().mediaId)
            assertEquals("B", controller.state.value.book?.id)
            assertEquals(25000L, controller.state.value.positionMs)
            assertEquals(5.0, controller.equalizer.value.preampDB, 0.0)
        }
    }
    @Test fun disconnectedOrSupersededQueuesCannotReplaceCurrentEngineOrBook() {
        withController { controller, engine ->
            val a = book("A", 1.0); val b = book("B", 5.0)
            apply(controller, a, 1000)
            val token = controller.beginSessionQueue("X")
            val stale = controller.stageSessionQueue(token, b, items(b), 0, 25000, true)
            controller.sessionControllerDisconnected("X")
            controller.setSessionMediaItems(stale.mediaItems, 0, 25000)
            assertEquals("A:0", engine.items.single().mediaId)
            val current = controller.beginSessionQueue("Y")
            val next = controller.stageSessionQueue(current, b, items(b), 0, 30000, true)
            controller.setSessionMediaItems(stale.mediaItems, 0, 25000)
            assertEquals("A", controller.state.value.book?.id)
            assertEquals(1.0, controller.equalizer.value.preampDB, 0.0)
            controller.setSessionMediaItems(next.mediaItems, 0, 30000)
            assertEquals("B", controller.state.value.book?.id)
            assertEquals(30000L, controller.state.value.positionMs)
        }
    }
    private fun items(book: LibraryBook) = listOf(MediaItem.Builder().setMediaId("${book.id}:0").setUri("file:///1.wav").build())
    private fun apply(controller: PlayerController, book: LibraryBook, position: Long) {
        val token = controller.beginSessionQueue("X")
        val queue = controller.stageSessionQueue(token, book, items(book), 0, position, true)
        controller.setSessionMediaItems(queue.mediaItems, queue.startIndex, queue.startPositionMs)
    }
    private fun withController(block: (PlayerController, Engine) -> Unit) {
        val controller = PlayerController(RuntimeEnvironment.getApplication())
        val engine = Engine()
        controller.attach(engine.player)
        try { block(controller, engine) } finally { controller.detach() }
    }
    /** Only the engine operations used by queue application and progress snapshots. */
    private class Engine {
        var items = emptyList<MediaItem>()
        var position = 0L
        var parameters = PlaybackParameters.DEFAULT
        var beforeSet: () -> Unit = {}
        val player = Proxy.newProxyInstance(Player::class.java.classLoader, arrayOf(Player::class.java)) { _, method, args ->
            when (method.name) {
                "setMediaItems" -> { beforeSet(); @Suppress("UNCHECKED_CAST")
                    items = args!![0] as List<MediaItem>; position = args[2] as Long; null }
                "getCurrentMediaItemIndex" -> 0
                "getCurrentPosition" -> position
                "getDuration" -> 120000L
                "getPlaybackState" -> Player.STATE_READY
                "isPlaying" -> false
                "getPlaybackParameters" -> parameters
                "setPlaybackSpeed" -> { parameters = PlaybackParameters(args!![0] as Float); null }
                "addListener", "removeListener" -> null
                else -> error("Unexpected engine operation: ${method.name}")
            }
        } as Player
    }
}
