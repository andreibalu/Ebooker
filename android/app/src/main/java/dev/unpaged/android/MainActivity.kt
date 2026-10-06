package dev.unpaged.android

import android.os.Bundle
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
    }
}

@Composable
private fun UnpagedApp() {
    val context = androidx.compose.ui.platform.LocalContext.current
    val preferences = androidx.compose.runtime.remember { UnpagedPreferences(context) }
    UnpagedTheme(preferences) { LibraryScreen(preferences = preferences) }
}
