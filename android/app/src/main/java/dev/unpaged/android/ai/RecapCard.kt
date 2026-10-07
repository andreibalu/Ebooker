package dev.unpaged.android.ai

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.unpaged.android.UnpagedApplication
import dev.unpaged.android.UnpagedPreferences
import dev.unpaged.android.library.LibraryBook
import kotlinx.coroutines.*

@Composable
fun RecapCard(book: LibraryBook) {
    val context = LocalContext.current
    val ai = (context.applicationContext as UnpagedApplication).ai
    val status by ai.status.collectAsStateWithLifecycle()
    val model by ai.models.state.collectAsStateWithLifecycle()
    val preferences = remember { UnpagedPreferences(context) }
    dev.unpaged.android.preferenceRevision(preferences)
    val cache = remember { RecapCache(context) }
    val headline = preferences.text("shortenSummary", "false") == "true"
    var recap by remember(book.id, book.currentTrackIndex, book.currentPositionMs, headline) { mutableStateOf(cache.read(book, headline)) }
    var loading by remember { mutableStateOf(false) }
    var error by remember(book.id, book.currentTrackIndex, book.currentPositionMs) { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(book.id) { ai.refresh() }
    val enabled = status == GeneratorStatus.AVAILABLE && model.installed && preferences.text("useLocalAIFeatures", "false") == "true" && preferences.text("useSmartSummary", "false") == "true"
    if (!enabled) return
    if (!book.isDownloaded) {
        Text("Audio for this book isn't on this phone.", Modifier.testTag("recap.unavailable"), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.onSurface.copy(alpha = .06f), RoundedCornerShape(16.dp)).padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Text(if (headline) recap?.headline ?: "Your progress" else "Your progress", Modifier.weight(1f), fontSize = 14.sp, fontWeight = FontWeight.Medium)
            if (loading) CircularProgressIndicator(Modifier.size(20.dp).testTag("recap.loading"), strokeWidth = 2.dp)
            else if (recap == null) IconButton(onClick = {
                scope.launch {
                    loading = true; error = null
                    try {
                        val result = ai.recap(book, book.currentTrackIndex, book.currentPositionMs, headline)
                        cache.save(book, result); recap = result
                    } catch (e: CancellationException) { throw e }
                    catch (e: Exception) { error = if (!book.isDownloaded) "Audio for this book isn't on this phone." else "Couldn't generate a recap. Please try again." }
                    finally { loading = false }
                }
            }, modifier = Modifier.testTag("recap.generate")) { Icon(Icons.Default.AutoAwesome, "Generate recap", Modifier.size(18.dp)) }
        }
        recap?.let { value -> Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.onSurface.copy(alpha = .04f), RoundedCornerShape(12.dp)).padding(12.dp).testTag("recap.result"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) { Icon(Icons.Default.AutoAwesome, null, Modifier.size(14.dp)); Text("Where Was I?", fontSize = 12.sp, fontWeight = FontWeight.SemiBold) }
            Text(value.text, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } }
        error?.let { Text(it, Modifier.testTag("recap.error"), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}
