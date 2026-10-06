package dev.unpaged.android

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** Color+Theme.swift: cream, cardWhite, amber and shared surface geometry. */
object UnpagedTheme {
    val cardShape = RoundedCornerShape(22.dp)
    val settingsShape = RoundedCornerShape(18.dp)
    val detailShape = RoundedCornerShape(24.dp)
    val disclosureShape = RoundedCornerShape(20.dp)
    val cardShadow = 1.dp
    val favorite = Color(0xFFFF3B30)
}

@Composable
fun UnpagedTheme(preferences: UnpagedPreferences, content: @Composable () -> Unit) {
    preferenceRevision(preferences)
    val dark = when (preferences.text("appAppearance", "system")) {
        "dark" -> true
        "light" -> false
        else -> isSystemInDarkTheme()
    }
    val colors = if (dark) darkColorScheme(onSurface = Color.White, onBackground = Color.White,
        primary = Color(0xFFE59A19), background = Color(0xFF1C1C1F), surface = Color(0xFF2B2B30),
        surfaceVariant = Color(0xFF3E3E43), onSurfaceVariant = Color(0xFF98989E))
    else lightColorScheme(onSurface = Color.Black, onBackground = Color.Black, primary = Color(0xFFCC8632),
        background = Color(0xFFF7F4ED), surface = Color(0xFFFFFCF7), surfaceVariant = Color(0xFFEDEBE5),
        onSurfaceVariant = Color(0xFF858589))
    MaterialTheme(colorScheme = colors, content = content)
}
