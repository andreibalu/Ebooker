package dev.unpaged.android.playback

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Airplay
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.mediarouter.app.SystemOutputSwitcherDialogController
import androidx.compose.runtime.*

/** API30+ system output switcher. The affordance is absent when the platform cannot open it. */
@Composable
internal fun OutputRouteButton(size: Int) {
    val context = LocalContext.current
    var available by remember { mutableStateOf(android.os.Build.VERSION.SDK_INT >= 30) }
    if (available) {
        IconButton(onClick = { available = SystemOutputSwitcherDialogController.showDialog(context) }, modifier = Modifier.size(size.dp)) {
            Icon(Icons.Default.Airplay, "Audio output", Modifier.size(20.dp))
        }
    }
}
