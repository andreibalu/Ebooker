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
        darkColorScheme(primary = Color(0xFFE4B775), background = Color(0xFF171613),
            surface = Color(0xFF171613), surfaceVariant = Color(0xFF302B23))
    } else {
        lightColorScheme(primary = Color(0xFF80531A), background = Color(0xFFFFFBF5),
            surface = Color(0xFFFFFBF5), surfaceVariant = Color(0xFFF1E7D8))
    }
    MaterialTheme(colorScheme = colors) { LibraryScreen() }
}
