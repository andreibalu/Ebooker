package dev.unpaged.android.playback

import android.app.PendingIntent
import android.content.Intent
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import android.content.Context
import androidx.core.net.toUri
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import dev.unpaged.android.MainActivity

@androidx.annotation.OptIn(UnstableApi::class)
class PlaybackService : MediaLibraryService() {
    private var session: MediaLibrarySession? = null
    private lateinit var callback: CarSessionCallback
    private lateinit var engine: ExoPlayer
    override fun onCreate() {
        super.onCreate()
        val controller = PlayerController.get(this)
        val renderers = object : DefaultRenderersFactory(this) {
            override fun buildAudioSink(context: Context, enableFloatOutput: Boolean, enableAudioTrackPlaybackParams: Boolean): AudioSink =
                DefaultAudioSink.Builder(context).setEnableFloatOutput(false)
                    .setAudioProcessors(arrayOf(controller.equalizerProcessor)).build()
        }
        val abs = (application as dev.unpaged.android.UnpagedApplication).abs
        val source = androidx.media3.datasource.ResolvingDataSource.Factory(
            androidx.media3.datasource.DefaultDataSource.Factory(this)) { spec ->
            if (spec.key?.startsWith("abs:") == true) {
                val url = kotlinx.coroutines.runBlocking { abs.playbackURL(spec.uri.toString()) }
                spec.withUri(url.toUri())
            } else spec
        }
        engine = ExoPlayer.Builder(this, renderers)
            .setMediaSourceFactory(androidx.media3.exoplayer.source.DefaultMediaSourceFactory(source))
            .setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_SPEECH).build(), true)
            .setHandleAudioBecomingNoisy(true).setWakeMode(C.WAKE_MODE_NETWORK).build()
        val sessionPlayer = object : ForwardingPlayer(engine) {
            override fun setMediaItems(items: List<androidx.media3.common.MediaItem>, startIndex: Int, startPositionMs: Long) =
                controller.setSessionMediaItems(items, startIndex, startPositionMs)
            override fun seekBack() = controller.skip(false)
            override fun seekForward() = controller.skip(true)
            override fun seekToNextMediaItem() = controller.next()
            override fun seekToPreviousMediaItem() = controller.previous()
            override fun seekToNext() = controller.next()
            override fun seekToPrevious() = controller.previous()
            override fun getSeekBackIncrement() = controller.preferences.seconds("skipBackSeconds", 30) * 1000L
            override fun getSeekForwardIncrement() = controller.preferences.seconds("skipForwardSeconds", 30) * 1000L
        }
        val activity = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        callback = CarSessionCallback(this, controller)
        session = MediaLibrarySession.Builder(this, sessionPlayer, callback).setSessionActivity(activity)
            .setCustomLayout(CarSessionCallback.buttons()).setMediaButtonPreferences(CarSessionCallback.buttons()).build()
        controller.attach(engine)
        callback.watchChapters(requireNotNull(session))
    }
    internal fun allowed(info: MediaSession.ControllerInfo): Boolean =
        BrowserCallerPolicy.allowed(info.packageName, packageName, info.isTrusted, debugBrowserAllowed(info.packageName))
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? =
        if (allowed(controllerInfo)) session else null
    override fun onTaskRemoved(rootIntent: Intent?) {
        PlayerController.get(this).background()
        super.onTaskRemoved(rootIntent)
    }
    override fun onDestroy() {
        PlayerController.get(this).detach()
        callback.close()
        session?.release(); engine.release(); session = null
        super.onDestroy()
    }
}
