package dev.unpaged.android.playback

import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import dev.unpaged.android.UnpagedApplication
import dev.unpaged.android.equalizer.EqualizerConfiguration
import dev.unpaged.android.library.LibraryBook
import dev.unpaged.android.library.LibraryTrack
import dev.unpaged.android.library.LibraryMoment
import dev.unpaged.android.library.SQLiteLibraryStore
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import org.robolectric.Shadows.shadowOf
import java.time.Duration
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
    @Test fun abandonedAndTimedOutQueuesKeepCurrentEmbeddedChapters() {
        for (timeout in listOf(false, true)) for (hasMarkers in listOf(false, true)) {
            withController { controller, engine ->
                val a = book("A", 1.0); val b = book("B", 5.0)
                val aMarkers = mapOf(0 to listOf(ChapterMarker("A opening", 0, 30000), ChapterMarker("A second", 30000, 120000)))
                val initial = controller.beginSessionQueue("X")
                val current = controller.stageSessionQueue(initial, a, items(a), 0, 1000, true, aMarkers)
                assertTrue(controller.setSessionMediaItems(current.mediaItems, 0, 1000))
                val chapters = controller.state.value.chapters
                val token = controller.beginSessionQueue("X")
                val bMarkers = if (hasMarkers) mapOf(0 to listOf(ChapterMarker("B opening", 0, 60000), ChapterMarker("B second", 60000, 120000))) else emptyMap()
                val abandoned = controller.stageSessionQueue(token, b, items(b), 0, 25000, true, bMarkers)
                if (timeout) shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(10))
                else controller.sessionControllerDisconnected("X")
                assertFalse(controller.setSessionMediaItems(abandoned.mediaItems, 0, 25000))
                controller.background()
                assertEquals(chapters, controller.state.value.chapters)
                assertEquals(listOf("A opening", "A second"), chapters.map { it.title })
                assertEquals(listOf(0L, 30000L), chapters.map { it.startMs })
                assertEquals("A:0", engine.items.single().mediaId)
                assertEquals(1.0, controller.equalizer.value.preampDB, 0.0)
            }
        }
    }
    @Test fun removingIncomingNormalPlaybackRejectsLatePreparation() = removalDuringPreparation("play")
    @Test fun removingIncomingMomentPlaybackRejectsLatePreparation() = removalDuringPreparation("moment")
    @Test fun removingIncomingCarPlaybackRejectsLatePreparation() = removalDuringPreparation("car")
    private fun removalDuringPreparation(path: String) {
        val release = CompletableDeferred<Unit>()
        var entered = false
        var completed = false
        withController(mediaReader = {
            entered = true
            withContext(NonCancellable) { release.await() }
            completed = true
            emptyMap<Int, List<ChapterMarker>>() to null
        }) { controller, engine ->
            val a = book("A", 1.0); val b = book("B", 5.0)
            val store = SQLiteLibraryStore(RuntimeEnvironment.getApplication())
            try {
                store.insert(b)
                apply(controller, a, 1000)
                when (path) {
                    "play" -> controller.play(b)
                    "moment" -> controller.playMoment(b, LibraryMoment("m", b.id, 0, 60000, "Moment"))
                    else -> {
                        val token = controller.beginSessionQueue("X")
                        controller.launchIntegration {
                            try {
                                val queue = controller.prepareSessionBook(token, b)
                                controller.setSessionMediaItems(queue.mediaItems, queue.startIndex, queue.startPositionMs)
                            } catch (_: IllegalStateException) { }
                        }
                    }
                }
                await { entered }
                controller.removed(b.id)
                release.complete(Unit)
                await { completed }
                controller.background()
                assertEquals("A", controller.state.value.book?.id)
                assertEquals("A:0", engine.items.single().mediaId)
                assertEquals(1000L, controller.state.value.positionMs)
                assertEquals(1.0, controller.equalizer.value.preampDB, 0.0)
            } finally { store.close() }
        }
    }
    @Test fun removingStagedCarBookRejectsQueueButOtherRemovalPreservesRequest() {
        withController { controller, engine ->
            val a = book("A", 1.0); val b = book("B", 5.0)
            apply(controller, a, 1000)
            val token = controller.beginSessionQueue("X")
            val queue = controller.stageSessionQueue(token, b, items(b), 0, 25000, true)
            controller.removed("unrelated")
            controller.removed(b.id)
            assertFalse(controller.setSessionMediaItems(queue.mediaItems, 0, 25000))
            assertEquals("A:0", engine.items.single().mediaId)
            val next = controller.beginSessionQueue("X")
            val valid = controller.stageSessionQueue(next, b, items(b), 0, 30000, true)
            controller.removed("unrelated")
            assertTrue(controller.setSessionMediaItems(valid.mediaItems, 0, 30000))
        }
    }
    @Test fun removingPreparedMomentBeforeEngineAttachmentRejectsPendingAction() {
        var prepared = false
        withController(mediaReader = { prepared = true; emptyMap<Int, List<ChapterMarker>>() to null }, attach = false) { controller, engine ->
            val b = book("B", 5.0)
            controller.playMoment(b, LibraryMoment("m", b.id, 0, 60000, "Moment"))
            await { prepared }
            controller.removed(b.id)
            controller.attach(engine.player)
            assertNull(controller.state.value.book)
            assertFalse(controller.state.value.loading)
            assertTrue(engine.items.isEmpty())
        }
    }
    private fun await(condition: () -> Boolean) {
        val until = System.nanoTime() + 5_000_000_000L
        while (!condition() && System.nanoTime() < until) {
            shadowOf(Looper.getMainLooper()).idle(); Thread.sleep(10)
        }
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue("Async operation completed", condition())
    }
    private fun items(book: LibraryBook) = listOf(MediaItem.Builder().setMediaId("${book.id}:0").setUri("file:///1.wav").build())
    private fun apply(controller: PlayerController, book: LibraryBook, position: Long) {
        val token = controller.beginSessionQueue("X")
        val queue = controller.stageSessionQueue(token, book, items(book), 0, position, true)
        controller.setSessionMediaItems(queue.mediaItems, queue.startIndex, queue.startPositionMs)
    }
    private fun withController(mediaReader: (suspend (LibraryBook) -> Pair<Map<Int, List<ChapterMarker>>, ByteArray?>)? = null,
        attach: Boolean = true, block: (PlayerController, Engine) -> Unit) {
        val app = RuntimeEnvironment.getApplication() as UnpagedApplication
        shadowOf(app).declareComponentUnbindable(android.content.ComponentName(app, PlaybackService::class.java))
        val controller = PlayerController(app, mediaReader)
        val engine = Engine()
        if (attach) controller.attach(engine.player)
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
                "addListener", "removeListener", "play", "prepare" -> null
                else -> error("Unexpected engine operation: ${method.name}")
            }
        } as Player
    }
}
