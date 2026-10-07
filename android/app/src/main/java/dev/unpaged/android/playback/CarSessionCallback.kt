package dev.unpaged.android.playback

import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.*
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map

@androidx.annotation.OptIn(UnstableApi::class)
internal class CarSessionCallback(private val service: PlaybackService, private val player: PlayerController) : MediaLibrarySession.Callback {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val library = CarLibrary(service)
    private val commands = CarCommands(player.preferences, { player.state.value.book != null },
        player::draftMoment, player::saveMoment, player::markProgress, { player.state.value.speed }, player::speed)
    companion object {
        const val SAVE_MOMENT = "dev.unpaged.SAVE_MOMENT"
        const val MARK_PROGRESS = "dev.unpaged.MARK_PROGRESS"
        const val CYCLE_SPEED = "dev.unpaged.CYCLE_SPEED"
        val actions = listOf(CYCLE_SPEED, SAVE_MOMENT, MARK_PROGRESS)
        fun buttons() = listOf(
            Triple(CYCLE_SPEED, "Playback Rate", CommandButton.ICON_PLAYBACK_SPEED),
            Triple(SAVE_MOMENT, "Save Moment", CommandButton.ICON_BOOKMARK_FILLED),
            Triple(MARK_PROGRESS, "Mark Progress", CommandButton.ICON_FLAG_FILLED)
        ).map { (action, title, icon) -> CommandButton.Builder(icon).setDisplayName(title)
            .setSessionCommand(SessionCommand(action, Bundle.EMPTY)).build() }
    }
    fun close() { scope.cancel(); library.close() }
    /** The Chapters tab comes and goes with the loaded book, and its rows follow the book's chapters. */
    fun watchChapters(session: MediaLibrarySession) {
        scope.launch {
            player.state.map { it.book?.id to it.chapters }.distinctUntilChanged().drop(1).collect { (_, chapters) ->
                session.notifyChildrenChanged(CarLibrary.ROOT, CarLibrary.tabs.size + if (player.state.value.book != null) 1 else 0, null)
                session.notifyChildrenChanged(CarLibrary.CHAPTERS, chapters.size, null)
            }
        }
    }
    private fun <T> async(block: suspend () -> T): ListenableFuture<T> {
        val future = SettableFuture.create<T>()
        val job = scope.launch { try { future.set(block()) } catch (error: Exception) { future.setException(error) } }
        future.addListener({ if (future.isCancelled) job.cancel() }, androidx.core.content.ContextCompat.getMainExecutor(service))
        return future
    }
    private suspend fun <T> read(block: () -> T) = withContext(Dispatchers.IO) { block() }
    override fun onConnect(session: MediaSession, controller: MediaSession.ControllerInfo): MediaSession.ConnectionResult {
        if (!service.allowed(controller)) return MediaSession.ConnectionResult.reject()
        val commands = MediaSession.ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS.buildUpon()
        actions.forEach { commands.add(SessionCommand(it, Bundle.EMPTY)) }
        return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
            .setAvailableSessionCommands(commands.build()).setCustomLayout(buttons()).setMediaButtonPreferences(buttons()).build()
    }
    override fun onGetLibraryRoot(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, params: LibraryParams?) = async {
        if (!service.allowed(browser)) LibraryResult.ofError(SessionError.ERROR_PERMISSION_DENIED)
        else LibraryResult.ofItem(CarLibrary.folder(CarLibrary.ROOT, "Unpaged"), LibraryParams.Builder()
            .setExtras(Bundle().apply { putBoolean("android.media.browse.SEARCH_SUPPORTED", true) }).build())
    }
    override fun onGetChildren(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, parentId: String,
        page: Int, pageSize: Int, params: LibraryParams?) = async {
        try { LibraryResult.ofItemList(if (parentId == CarLibrary.CHAPTERS) CarLibrary.page(library.children(parentId), page, pageSize)
            else read { CarLibrary.page(library.children(parentId), page, pageSize) }, params) }
        catch (_: IllegalArgumentException) { LibraryResult.ofError(SessionError.ERROR_BAD_VALUE) }
    }
    override fun onGetItem(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, mediaId: String) = async {
        val item = if (mediaId.startsWith("chapter:")) library.item(mediaId) else read { library.item(mediaId) }
        item?.let { LibraryResult.ofItem(it, null) } ?: LibraryResult.ofError(SessionError.ERROR_BAD_VALUE)
    }
    override fun onSubscribe(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, parentId: String, params: LibraryParams?) = async {
        val items = if (parentId == CarLibrary.CHAPTERS) library.children(parentId) else read { library.children(parentId) }
        session.notifyChildrenChanged(browser, parentId, items.size, params)
        LibraryResult.ofVoid(params)
    }
    override fun onSearch(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String, params: LibraryParams?) = async {
        val count = read { library.search(query).size }
        session.notifySearchResultChanged(browser, query, count, params)
        LibraryResult.ofVoid(params)
    }
    override fun onGetSearchResult(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String,
        page: Int, pageSize: Int, params: LibraryParams?) = async {
        try { LibraryResult.ofItemList(read { CarLibrary.page(library.search(query), page, pageSize) }, params) }
        catch (_: IllegalArgumentException) { LibraryResult.ofError(SessionError.ERROR_BAD_VALUE) }
    }
    private suspend fun queue(session: MediaSession, controller: MediaSession.ControllerInfo, request: MediaItem): MediaSession.MediaItemsWithStartPosition {
        try {
            val query = request.requestMetadata.searchQuery
            val id = if (query != null) read { library.search(query).firstOrNull()?.mediaId }
                ?: error("No matches for \"$query\"") else request.mediaId
            if (id.startsWith("chapter:")) {
                val chapter = player.state.value.chapters.getOrNull(id.removePrefix("chapter:").toIntOrNull() ?: -1)
                    ?: error("This chapter is no longer available.")
                return MediaSession.MediaItemsWithStartPosition((0 until session.player.mediaItemCount).map { session.player.getMediaItemAt(it) },
                    chapter.trackIndex, chapter.startMs)
            }
            return player.prepareSessionBook(library.resolve(id))
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            val message = error.message ?: "Couldn't open book"
            session.sendError(controller, SessionError(SessionError.ERROR_IO, message))
            throw androidx.media3.common.PlaybackException(message, error,
                if (message == "No internet connection") androidx.media3.common.PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED
                else androidx.media3.common.PlaybackException.ERROR_CODE_IO_UNSPECIFIED)
        }
    }
    override fun onSetMediaItems(session: MediaSession, controller: MediaSession.ControllerInfo, mediaItems: List<MediaItem>, startIndex: Int, startPositionMs: Long) = async {
        require(mediaItems.size == 1) { "Choose one audiobook" }
        queue(session, controller, mediaItems.single())
    }
    override fun onAddMediaItems(session: MediaSession, controller: MediaSession.ControllerInfo, mediaItems: List<MediaItem>): ListenableFuture<List<MediaItem>> = async {
        require(mediaItems.size == 1) { "Choose one audiobook" }
        val resolved = queue(session, controller, mediaItems.single())
        // Add/search requests select a book, not tracks to append to another audiobook.
        session.player.setMediaItems(resolved.mediaItems, resolved.startIndex, resolved.startPositionMs)
        session.player.prepare(); session.player.play()
        emptyList()
    }
    override fun onPlaybackResumption(session: MediaSession, controller: MediaSession.ControllerInfo) = async {
        queue(session, controller, MediaItem.Builder().setRequestMetadata(MediaItem.RequestMetadata.Builder().setSearchQuery("").build()).build())
    }
    override fun onCustomCommand(session: MediaSession, controller: MediaSession.ControllerInfo, customCommand: SessionCommand, args: Bundle) = async {
        commands.perform(customCommand.customAction)
    }
}
