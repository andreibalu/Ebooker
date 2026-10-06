package dev.unpaged.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import dev.unpaged.android.library.LibraryScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { UnpagedApp() }
    }
}

@Composable
private fun UnpagedApp() {
    val colors = if (isSystemInDarkTheme()) {
        darkColorScheme(onSurface = Color.White, onBackground = Color.White, primary = Color(0xFFE59A19), background = Color(0xFF1C1C1F),
            surface = Color(0xFF2B2B30), surfaceVariant = Color(0xFF2B2B30), onSurfaceVariant = Color(0xFFAAAAAE))
    } else {
        lightColorScheme(onSurface = Color.Black, onBackground = Color.Black, primary = Color(0xFFCC8632), background = Color(0xFFF7F4ED),
            surface = Color(0xFFFFFCF7), surfaceVariant = Color(0xFFEAE7DF), onSurfaceVariant = Color(0xFF6C6C70))
    }
    MaterialTheme(colorScheme = colors) { LibraryScreen() }
}
