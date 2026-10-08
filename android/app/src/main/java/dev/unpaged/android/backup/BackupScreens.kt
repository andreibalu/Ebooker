package dev.unpaged.android.backup

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.unpaged.android.library.*

fun openSystemBackupSettings(context: Context) {
    try { context.startActivity(Intent("android.settings.BACKUP_SETTINGS")) }
    catch (_: ActivityNotFoundException) { context.startActivity(Intent(Settings.ACTION_SETTINGS)) }
}

enum class BackupBucket(val title: String) {
    PHONE("On This Phone"), STREAMING("Streaming"), MISSING("Audio Missing"), REMOVED("Removed Free Books");
    companion object {
        fun of(book: LibraryBook): BackupBucket = when {
            book.isArchived && book.isFreeBook -> REMOVED
            book.isDownloaded -> PHONE
            book.isStreamingOnly -> STREAMING
            else -> MISSING
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackedUpLibrary(books: List<LibraryBook>, moments: Map<String, List<LibraryMoment>>, enabled: Boolean,
    onLocate: (LibraryBook) -> Unit, onStream: (LibraryBook) -> Unit,
    onDelete: (LibraryBook) -> Unit, absConnected: Boolean = false, onDone: () -> Unit) {
    var delete by remember { mutableStateOf<LibraryBook?>(null) }
    ModalBottomSheet(onDismissRequest = onDone, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxHeight(.95f).semantics { testTagsAsResourceId = true }) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Backed-up Library", Modifier.weight(1f), fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                TextButton(onClick = onDone, modifier = Modifier.testTag("backup.library.done")) { Text("Done") }
            }
            LazyColumn(Modifier.fillMaxWidth().testTag("backup.library"), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                item {
                    Text(if (enabled) "Library metadata is included in Android backup when Backup by Google is on. Audio files are not included. This list does not confirm a completed backup."
                        else "Turn on Back Up Library in Settings to include library metadata in Android backup.", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (books.isEmpty()) item { Text("Your backup library is empty. Import a book to get started.") }
                BackupBucket.entries.forEach { bucket ->
                    val rows = books.filter { BackupBucket.of(it) == bucket }.sortedByDescending { it.lastPlayedAt ?: it.dateAdded }
                    if (rows.isNotEmpty()) {
                        item { Text(bucket.title, Modifier.padding(top = 16.dp, bottom = 4.dp).testTag("backup.bucket.${bucket.name}"), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        items(rows, key = { it.id }) { book ->
                            val swipe = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
                                if (value == SwipeToDismissBoxValue.EndToStart) delete = book
                                false
                            })
                            SwipeToDismissBox(swipe, enableDismissFromStartToEnd = false,
                                enableDismissFromEndToStart = !book.isFreeBook && book.absItemID == null,
                                backgroundContent = { Box(Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.CenterEnd) { Text("Delete", color = MaterialTheme.colorScheme.error) } }) {
                                Surface(shape = RoundedCornerShape(12.dp)) {
                                    Row(Modifier.fillMaxWidth().testTag("backup.row.${book.id}").padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                        LibraryBookCover(book, Modifier.size(44.dp), cornerRadius = 6)
                                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                            Text(book.title, fontSize = 16.sp, fontWeight = FontWeight.Medium, maxLines = 2)
                                            Text(book.author.ifBlank { "Unknown Author" }, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                            val count = moments[book.id].orEmpty().size
                                            val metadata = listOfNotNull(
                                                if (count > 0) "$count ${if (count == 1) "moment" else "moments"}" else null,
                                                if (book.progress > 0) "${kotlin.math.round(book.progress * 100).toInt()}%" else null
                                            ).joinToString(" · ")
                                            if (metadata.isNotEmpty()) Text(metadata, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                        when (bucket) {
                                            BackupBucket.MISSING -> OutlinedButton(onClick = { onLocate(book) }, modifier = Modifier.testTag("backup.locate.${book.id}"), contentPadding = PaddingValues(horizontal = 10.dp)) { Text("Locate…", fontSize = 12.sp) }
                                            BackupBucket.REMOVED -> if (book.tracks.any { it.remoteUrl != null }) OutlinedButton(onClick = { onStream(book) }, modifier = Modifier.testTag("backup.stream.${book.id}"), contentPadding = PaddingValues(horizontal = 10.dp)) { Text("Stream", fontSize = 12.sp) }
                                            BackupBucket.STREAMING -> Text(if (book.absItemID != null && !absConnected) "Reconnect server" else "Streaming", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                            BackupBucket.PHONE -> Unit
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    delete?.let { book -> AlertDialog(onDismissRequest = { delete = null }, modifier = Modifier.semantics { testTagsAsResourceId = true }, title = { Text("Remove from Backup?") },
        text = { Text("Permanently removes '${book.title}' and its progress, moments, and EQ from your library and future backups. This can't be undone.") },
        confirmButton = { TextButton(onClick = { onDelete(book); delete = null }, modifier = Modifier.testTag("backup.delete")) { Text("Delete Permanently") } },
        dismissButton = { TextButton(onClick = { delete = null }) { Text("Cancel") } }) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RestoreMatchSheet(book: LibraryBook, count: Int, busy: Boolean, mismatch: Boolean,
    restore: () -> Unit, add: () -> Unit, cancel: () -> Unit) {
    ModalBottomSheet(onDismissRequest = { if (!busy) cancel() }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).semantics { testTagsAsResourceId = true }.padding(16.dp).padding(bottom = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Backup match", Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                TextButton(onClick = cancel, enabled = !busy) { Text("Cancel") }
            }
            LibraryBookCover(book, Modifier.size(140.dp), cornerRadius = 14)
            Text(if (mismatch) "These files do not match the backup copy" else "Looks like '${book.title}'", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
            Text(if (mismatch) "Adopting them replaces its audio while keeping its progress and moments." else "Restore your progress, moments, and settings from backup?", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .08f)) {
                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (book.author.isNotBlank()) RestoreMetadataRow(Icons.Default.Person, book.author)
                    RestoreMetadataRow(Icons.Default.Bookmark, "$count ${if (count == 1) "moment" else "moments"}", Modifier.testTag("backup.match.moments"))
                    if (book.progress > 0) RestoreMetadataRow(Icons.Default.BarChart, "${kotlin.math.round(book.progress * 100).toInt()}% through")
                    book.lastPlayedAt?.let { RestoreMetadataRow(Icons.Default.Schedule, "Last played ${relativePlayedAt(it)}") }
                }
            }
            Button(onClick = restore, enabled = !busy, modifier = Modifier.fillMaxWidth().testTag("backup.restore"), shape = RoundedCornerShape(14.dp), contentPadding = PaddingValues(vertical = 14.dp), colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onSurface, contentColor = MaterialTheme.colorScheme.background)) {
                Text(if (mismatch) "Adopt These Files" else "Restore from Backup", fontWeight = FontWeight.SemiBold)
            }
            OutlinedButton(onClick = add, enabled = !busy, modifier = Modifier.fillMaxWidth().testTag("backup.addNew")) { Text(if (mismatch) "Choose Different Files" else "Add as New") }
        }
    }
}

@Composable
private fun RestoreMetadataRow(icon: ImageVector, text: String, modifier: Modifier = Modifier) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(text, modifier, fontSize = 14.sp)
    }
}
