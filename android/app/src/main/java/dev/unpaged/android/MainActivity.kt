package dev.unpaged.android

import android.os.Bundle
import android.content.Intent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import dev.unpaged.android.playback.CarLibrary
import dev.unpaged.android.playback.PlayerController
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import dev.unpaged.android.library.LibraryScreen

open class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { UnpagedApp() }
        if (savedInstanceState == null) consumePlaybackIntent(intent)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumePlaybackIntent(intent)
    }
    private fun consumePlaybackIntent(request: Intent) {
        val query = when (request.action) {
            "dev.unpaged.android.PLAY_LATEST_BOOK" -> ""
            "android.media.action.MEDIA_PLAY_FROM_SEARCH" -> request.getStringExtra(android.app.SearchManager.QUERY).orEmpty()
            else -> return
        }
        // Consume before asynchronous lookup. Rotation and ordinary relaunch cannot replay it. The lookup
        // runs on the player's app-lifetime scope so destroying this activity cannot drop the request.
        request.action = Intent.ACTION_MAIN
        request.removeExtra(android.app.SearchManager.QUERY)
        val context = applicationContext
        PlayerController.get(context).launchIntegration {
            val player = PlayerController.get(context)
            try {
                CarLibrary(context).use { library ->
                    val id = withContext(Dispatchers.IO) { library.search(query).firstOrNull()?.mediaId }
                        ?: error(if (query.isBlank()) "Your Library Is Empty" else "No matches for \"$query\"")
                    player.play(library.resolve(id))
                }
            } catch (error: Exception) {
                if (error is kotlinx.coroutines.CancellationException) throw error
                player.integrationError(error.message ?: "Couldn't open book")
            }
        }
    }
}

@Composable
private fun UnpagedApp() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val preferences = androidx.compose.runtime.remember { UnpagedPreferences(context) }
    preferenceRevision(preferences)
    UnpagedTheme(preferences) {
        if (preferences.onboardingComplete()) LibraryScreen(preferences = preferences) else OnboardingScreen(preferences)
    }
}
