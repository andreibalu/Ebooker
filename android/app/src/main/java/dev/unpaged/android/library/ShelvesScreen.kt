package dev.unpaged.android.library

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag

/** Source browsing is supplied by the Shelves slice. */
@Composable
fun ShelvesScreen() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("Shelves", Modifier.testTag("shelves.placeholder")) }
}
