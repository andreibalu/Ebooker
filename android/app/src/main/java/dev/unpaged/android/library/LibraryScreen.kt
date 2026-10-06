package dev.unpaged.android.library

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
    val onImport = { picker.launch(arrayOf("*/*")) }
    val canImport = !state.loading && !state.busy && state.error != LibraryFailure.LOAD
    BackHandler(enabled = selectedId != null && state.pending == null) { selectedId = null }

    Scaffold(Modifier.semantics { testTagsAsResourceId = true }) { insets ->
        Column(Modifier.fillMaxSize().padding(insets)) {
            if (selected == null) LibraryHeader(state.books.size, canImport, onImport)
            else Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { selectedId = null }) { Text(stringResource(R.string.back)) }
                Text(selected.title, Modifier.weight(1f), fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
            when {
                state.loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                state.preparing -> Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    CircularProgressIndicator()
                    Text(stringResource(R.string.preparing_tracks, state.completed, state.total))
                    Text(stringResource(R.string.copying_audio))
                    TextButton(onClick = model::cancelPreparation) { Text(stringResource(R.string.cancel)) }
                }
                selected != null -> BookDetails(selected, state.busy) { removeId = selected.id }
                state.books.isEmpty() -> EmptyLibrary(canImport, onImport)
                else -> LazyVerticalGrid(GridCells.Adaptive(160.dp), Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(20.dp, 32.dp), horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    items(state.books, key = { it.id }) { book -> LibraryBookCard(book) { selectedId = book.id } }
                }
            }
        }
    }
    state.pending?.let { ImportReview(it, state.busy, model::save, model::discard) }
    state.books.firstOrNull { it.id == removeId }?.let { book ->
        AlertDialog(onDismissRequest = { if (!state.busy) removeId = null },
            title = { Text(stringResource(R.string.remove_title)) }, text = { Text(stringResource(R.string.remove_hint, book.title)) },
            confirmButton = { TextButton(enabled = !state.busy, onClick = {
                model.remove(book); removeId = null; selectedId = null
            }) { Text(stringResource(R.string.remove)) } },
            dismissButton = { TextButton(enabled = !state.busy, onClick = { removeId = null }) { Text(stringResource(R.string.cancel)) } })
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
            })) }, confirmButton = { TextButton(onClick = {
                if (error == LibraryFailure.LOAD) model.reload() else model.dismissError()
            }) { Text(stringResource(if (error == LibraryFailure.LOAD) R.string.retry else R.string.ok)) } })
    }
}

@Composable
private fun BookDetails(book: LibraryBook, busy: Boolean, remove: () -> Unit) {
    var expanded by rememberSaveable(book.id) { mutableStateOf(false) }
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item {
            Surface(shape = RoundedCornerShape(28.dp), shadowElevation = 3.dp) {
                Row(Modifier.fillMaxWidth().padding(18.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    GeneratedBookCover(book.title, Modifier.size(130.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(book.title, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
                        Text(book.author.ifBlank { stringResource(R.string.unknown_author) }, fontSize = 15.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(shortDuration(book.durationMs), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(R.string.playback_next), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        item {
            Surface(shape = RoundedCornerShape(28.dp), shadowElevation = 4.dp) {
                TextButton(onClick = { expanded = !expanded }, modifier = Modifier.fillMaxWidth().testTag("book.tracks")) {
                    Text(pluralStringResource(R.plurals.book_summary, book.tracks.size, book.tracks.size,
                        shortDuration(book.durationMs)), Modifier.padding(12.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (expanded) items(book.tracks.withIndex().toList(), key = { it.index }) { (index, track) ->
            Surface(shape = RoundedCornerShape(16.dp)) {
                Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("${index + 1}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(track.title, Modifier.weight(1f))
                    Text(trackDuration(track.durationMs), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                }
            }
        }
        item { TextButton(enabled = !busy, onClick = remove) {
            Text(stringResource(R.string.remove_book), color = MaterialTheme.colorScheme.error)
        } }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ImportReview(pending: PendingImport, busy: Boolean, save: (String, String) -> Unit, discard: () -> Unit) {
    var title by rememberSaveable(pending.id) { mutableStateOf(pending.suggestedTitle) }
    var author by rememberSaveable(pending.id) { mutableStateOf(pending.suggestedAuthor) }
    val currentBusy by rememberUpdatedState(busy)
    val titleLabel = stringResource(R.string.title)
    val authorLabel = stringResource(R.string.author)
    ModalBottomSheet(onDismissRequest = { if (!busy) discard() }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true,
            confirmValueChange = { value -> !currentBusy || value != SheetValue.Hidden }),
        contentColor = MaterialTheme.colorScheme.onSurface,
        containerColor = if (isSystemInDarkTheme()) Color(0xFF1C1C1E) else Color(0xFFF2F2F7)) {
        Column(Modifier.fillMaxHeight(.92f).imePadding().semantics { testTagsAsResourceId = true }) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(enabled = !busy, onClick = discard, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)) { Text(stringResource(R.string.cancel)) }
                Text(stringResource(R.string.import_book), Modifier.weight(1f), fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                TextButton(enabled = !busy && title.isNotBlank(), onClick = { save(title, author) }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)) {
                    Text(stringResource(R.string.add_to_library), fontSize = 13.sp)
                }
            }
            LazyColumn(Modifier.fillMaxWidth(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                item { Text(stringResource(R.string.details), Modifier.padding(start = 16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
                item {
                    Surface(shape = RoundedCornerShape(14.dp)) {
                        Column {
                            val fieldColors = TextFieldDefaults.colors(focusedContainerColor = MaterialTheme.colorScheme.surface,
                                unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                                focusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                                unfocusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent)
                            TextField(title, { title = it }, Modifier.fillMaxWidth().testTag("import.title").semantics { contentDescription = titleLabel }, enabled = !busy,
                                placeholder = { Text(stringResource(R.string.title)) }, singleLine = true, colors = fieldColors)
                            HorizontalDivider(Modifier.padding(start = 16.dp))
                            TextField(author, { author = it }, Modifier.fillMaxWidth().testTag("import.author").semantics { contentDescription = authorLabel }, enabled = !busy,
                                placeholder = { Text(stringResource(R.string.author)) }, singleLine = true, colors = fieldColors)
                            HorizontalDivider(Modifier.padding(start = 16.dp))
                            ReviewValue(stringResource(R.string.files), pending.tracks.size.toString())
                            HorizontalDivider(Modifier.padding(start = 16.dp))
                            ReviewValue(stringResource(R.string.total_length), shortDuration(pending.tracks.sumOf { it.durationMs }))
                        }
                    }
                }
                item { Text(stringResource(R.string.imported_files), Modifier.padding(start = 16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
                items(pending.tracks.withIndex().toList(), key = { it.index }) { (_, track) ->
                    Surface(shape = RoundedCornerShape(14.dp)) {
                        Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Column(Modifier.weight(1f)) {
                                Text(track.title)
                                Text(track.originalName, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                            }
                            Text(trackDuration(track.durationMs), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ReviewValue(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label); Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
