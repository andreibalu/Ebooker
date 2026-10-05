package dev.unpaged.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp

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
        darkColorScheme(primary = Color(0xFFE4B775))
    } else {
        lightColorScheme(primary = Color(0xFF80531A), background = Color(0xFFFFFBF5))
    }
    MaterialTheme(colorScheme = colors) {
        Scaffold { contentPadding ->
            Column(
                modifier = Modifier.fillMaxSize().padding(contentPadding).padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Text(
                    text = stringResource(R.string.app_name),
                    style = MaterialTheme.typography.headlineLarge.copy(fontFamily = FontFamily.Serif),
                )
                Text(stringResource(R.string.your_library), style = MaterialTheme.typography.titleMedium)
                Text(stringResource(R.string.empty_library), style = MaterialTheme.typography.bodyLarge)
            }
        }
    }
}
