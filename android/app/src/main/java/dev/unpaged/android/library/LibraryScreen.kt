package dev.unpaged.android.library

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.unpaged.android.R

@Composable
fun LibraryScreen(model: LibraryViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    var removeId by rememberSaveable { mutableStateOf<String?>(null) }
    val selected = state.books.firstOrNull { it.id == selectedId }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments(), model::prepare)
    BackHandler(enabled = selectedId != null && state.pending == null) { selectedId = null }

    Scaffold { insets ->
        Column(Modifier.fillMaxSize().padding(insets)) {
            Column(Modifier.padding(horizontal = 24.dp, vertical = 16.dp)) {
                Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineLarge,
                    fontFamily = FontFamily.Serif)
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(stringResource(if (selected == null) R.string.your_library else R.string.book_details),
                        style = MaterialTheme.typography.titleMedium)
                    if (selected == null) TextButton(enabled = !state.loading && !state.busy && state.error != LibraryFailure.LOAD,
                        onClick = { picker.launch(arrayOf("*/*")) }) { Text(stringResource(R.string.import_book)) }
                    else TextButton(onClick = { selectedId = null }) { Text(stringResource(R.string.back)) }
                }
                HorizontalDivider()
            }
            when {
                state.loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                state.preparing -> Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    CircularProgressIndicator()
                    Text(stringResource(R.string.preparing_tracks, state.completed, state.total))
                    Text(stringResource(R.string.copying_audio))
                    TextButton(onClick = model::cancelPreparation) { Text(stringResource(R.string.cancel)) }
                }
                selected != null -> LazyColumn(Modifier.fillMaxSize().padding(horizontal = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    item {
                        Text(selected.title, fontFamily = FontFamily.Serif, style = MaterialTheme.typography.headlineMedium)
                        if (selected.author.isNotBlank()) Text(selected.author, style = MaterialTheme.typography.bodyLarge)
                        Text(bookSummary(selected), style = MaterialTheme.typography.bodyMedium)
                        Spacer(Modifier.height(12.dp))
                        Text(stringResource(R.string.playback_next), style = MaterialTheme.typography.bodyMedium)
                    }
                    items(selected.tracks.withIndex().toList(), key = { it.index }) { (index, track) ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            Text("${index + 1}", color = MaterialTheme.colorScheme.primary)
                            Column(Modifier.weight(1f)) {
                                Text(track.title, fontFamily = FontFamily.Serif, style = MaterialTheme.typography.titleMedium)
                                Text(durationLabel(track.durationMs), style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                    item {
                        TextButton(enabled = !state.busy, onClick = { removeId = selected.id }) {
                            Text(stringResource(R.string.remove_book), color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
                state.books.isEmpty() -> Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text(stringResource(R.string.empty_library), fontFamily = FontFamily.Serif,
                        style = MaterialTheme.typography.headlineMedium)
                    Text(stringResource(R.string.empty_library_hint))
                    Button(enabled = !state.busy && state.error != LibraryFailure.LOAD,
                        onClick = { picker.launch(arrayOf("*/*")) }) { Text(stringResource(R.string.choose_audio)) }
                }
                else -> LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    items(state.books, key = { it.id }) { book ->
                        Row(Modifier.fillMaxWidth().clickable { selectedId = book.id }.padding(horizontal = 24.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Surface(Modifier.size(56.dp, 76.dp), shape = RoundedCornerShape(4.dp),
                                color = MaterialTheme.colorScheme.surfaceVariant) {
                                Box(contentAlignment = Alignment.Center) {
                                    Text(book.title.take(1), fontFamily = FontFamily.Serif,
                                        style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.primary)
                                }
                            }
                            Spacer(Modifier.width(16.dp))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(book.title, fontFamily = FontFamily.Serif, style = MaterialTheme.typography.titleLarge,
                                    maxLines = 2, overflow = TextOverflow.Ellipsis)
                                if (book.author.isNotBlank()) Text(book.author, style = MaterialTheme.typography.bodyMedium)
                                Text(bookSummary(book), style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }

    state.pending?.let { pending ->
        ImportReview(pending, state.busy, model::save, model::discard)
    }
    state.books.firstOrNull { it.id == removeId }?.let { book ->
        AlertDialog(onDismissRequest = { if (!state.busy) removeId = null },
            title = { Text(stringResource(R.string.remove_title)) },
            text = { Text(stringResource(R.string.remove_hint, book.title)) },
            confirmButton = { TextButton(enabled = !state.busy, onClick = {
                model.remove(book); removeId = null; selectedId = null
            }) { Text(stringResource(R.string.remove)) } },
            dismissButton = { TextButton(enabled = !state.busy, onClick = { removeId = null }) {
                Text(stringResource(R.string.cancel))
            } })
    }
    state.error?.let { error ->
        AlertDialog(onDismissRequest = { if (error != LibraryFailure.LOAD) model.dismissError() },
            title = { Text(stringResource(R.string.could_not_complete)) },
            text = { Text(stringResource(when (error) {
                LibraryFailure.INVALID_AUDIO -> R.string.invalid_audio
                LibraryFailure.DUPLICATE -> R.string.duplicate_book
                LibraryFailure.TITLE -> R.string.title_required
                LibraryFailure.READ -> R.string.read_failed
                LibraryFailure.STORAGE -> R.string.storage_failed
                LibraryFailure.LOAD -> R.string.load_failed
            })) },
            confirmButton = { TextButton(onClick = {
                if (error == LibraryFailure.LOAD) model.reload() else model.dismissError()
            }) { Text(stringResource(if (error == LibraryFailure.LOAD) R.string.retry else R.string.ok)) } })
    }
}

@Composable
private fun ImportReview(pending: PendingImport, busy: Boolean, save: (String, String) -> Unit, discard: () -> Unit) {
    var title by rememberSaveable(pending.id) { mutableStateOf(pending.suggestedTitle) }
    var author by rememberSaveable(pending.id) { mutableStateOf(pending.suggestedAuthor) }
    AlertDialog(onDismissRequest = { if (!busy) discard() },
        title = { Text(stringResource(R.string.import_book), fontFamily = FontFamily.Serif) },
        text = {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item { Text(pluralStringResource(R.plurals.import_review_hint, pending.tracks.size, pending.tracks.size)) }
                item { OutlinedTextField(title, { title = it }, enabled = !busy,
                    label = { Text(stringResource(R.string.title)) }, singleLine = true) }
                item { OutlinedTextField(author, { author = it }, enabled = !busy,
                    label = { Text(stringResource(R.string.author)) }, singleLine = true) }
                items(pending.tracks.withIndex().toList(), key = { it.index }) { (index, track) ->
                    Text("${index + 1}. ${track.title}", style = MaterialTheme.typography.bodySmall)
                }
            }
        },
        confirmButton = { TextButton(enabled = !busy && title.isNotBlank(), onClick = { save(title, author) }) {
            Text(stringResource(R.string.add_to_library))
        } },
        dismissButton = { TextButton(enabled = !busy, onClick = discard) { Text(stringResource(R.string.cancel)) } })
}

@Composable
private fun bookSummary(book: LibraryBook): String = pluralStringResource(R.plurals.book_summary, book.tracks.size,
    book.tracks.size, durationLabel(book.durationMs))

@Composable
private fun durationLabel(milliseconds: Long): String {
    val seconds = milliseconds / 1000
    return if (seconds >= 3600) stringResource(R.string.hours_minutes, seconds / 3600, (seconds % 3600) / 60)
        else stringResource(R.string.minutes_seconds, seconds / 60, seconds % 60)
}
