package dev.unpaged.android.library

import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.semantics.semantics
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.unpaged.android.UnpagedPreferences
import dev.unpaged.android.shelves.*
import kotlinx.coroutines.launch

@Composable
fun ShelvesScreen(onLibraryChanged: () -> Unit = {}, onViewLibrary: (String) -> Unit = {}, model: ShelvesViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()
    val sessionState by model.session.state.collectAsStateWithLifecycle()
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    var collectionId by rememberSaveable { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val preferences = remember { UnpagedPreferences(context) }
    var collectionsHidden by rememberSaveable { mutableStateOf(preferences.collectionsHidden()) }
    val selected = (state.books + state.results).firstOrNull { it.id == selectedId }
    val collection = Collections.all.firstOrNull { it.id == collectionId }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner, model) {
        model.resume()
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) model.pause()
            if (event == Lifecycle.Event.ON_START) model.resume()
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer); model.pause() }
    }
    LaunchedEffect(sessionState.libraryRevision) { if (sessionState.libraryRevision > 0) onLibraryChanged() }
    BackHandler(selectedId != null || collectionId != null) {
        if (selectedId != null) selectedId = null else collectionId = null
    }
    Column(Modifier.fillMaxSize().testTag("shelves.screen")) {
        when {
            selected != null -> CatalogDetail(selected, state.books, model, { selectedId = null },
                { selectedId = it.id }, { id -> selectedId = null; collectionId = null; onViewLibrary(id) })
            collection != null -> {
                ShelvesBack(collection.title) { collectionId = null }
                Text(collection.subtitle, Modifier.padding(horizontal = 20.dp, vertical = 12.dp), fontSize = 15.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                val byId = state.books.associateBy { it.id }
                val books = collection.ids.mapNotNull { byId[it] }
                if (state.collectionLoading && books.isEmpty()) CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally))
                else if (books.isEmpty()) ShelvesEmpty(if (state.offline) "No Internet Connection" else "Couldn’t Load Collection",
                    "This collection needs a connection the first time to load its books from LibriVox.") { model.collection(collection) }
                else LazyColumn(Modifier.testTag("shelves.collection")) {
                    itemsIndexed(books, key = { _, b -> b.id }) { index, book -> CatalogRow(book, index, model) { selectedId = book.id } }
                    item { CollectionColophon() }
                }
            }
            else -> {
                SearchAndFilters(state, model)
                StatusLine(state, model)
                if (state.loading && state.books.isEmpty()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                else if (state.books.isEmpty() && state.offline) ShelvesEmpty("No Internet Connection",
                    "Shelves needs a connection the first time to load audiobooks from LibriVox. Connect to Wi‑Fi or cellular and tap Retry.", model::refresh)
                else if (state.books.isEmpty() && state.error != null) ShelvesEmpty("Couldn’t Load Shelves", state.error!!, model::refresh)
                else LazyColumn(Modifier.fillMaxSize().testTag("shelves.list"), contentPadding = PaddingValues(bottom = 24.dp)) {
                    if (state.filtered) {
                        if (!state.searching) item {
                            SectionHeader("Found · ${state.results.size} Recording${if (state.results.size == 1) "" else "s"}")
                        }
                        if (state.results.isEmpty() && !state.searching) item {
                            ShelvesEmpty("Nothing on this shelf.", "Try a different title or author, or clear a filter.") {
                                model.query(""); model.language(null); model.genre(null); model.length(null)
                            }
                        }
                        itemsIndexed(state.results, key = { _, b -> b.id }) { index, book -> CatalogRow(book, index, model) { selectedId = book.id } }
                    } else {
                        val pick = state.books.firstOrNull { it.id == Classics.pick(model.day) }
                        if (pick != null) item { Hero(pick) { selectedId = pick.id } }
                        item { SharedDownloads(model.session) { selectedId = it } }
                        item { SectionHeader("Collections", if (collectionsHidden) Icons.AutoMirrored.Filled.KeyboardArrowRight else Icons.Default.KeyboardArrowDown) {
                            collectionsHidden = !collectionsHidden
                            preferences.setCollectionsHidden(collectionsHidden)
                        } }
                        if (!collectionsHidden) item {
                            LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                items(Collections.all, key = { it.id }) { shelf -> CollectionCard(shelf) {
                                    collectionId = shelf.id; model.collection(shelf)
                                } }
                            }
                        }
                        item { SectionHeader("Popular Classics") }
                        val byId = state.books.associateBy { it.id }
                        val ordered = state.featuredIDs.mapNotNull { byId[it] }.filter { it.id != pick?.id }
                        itemsIndexed(ordered, key = { _, b -> b.id }) { index, book -> CatalogRow(book, index, model) { selectedId = book.id } }
                        item { Colophon() }
                    }
                }
            }
        }
    }
    sessionState.error?.let { message -> AlertDialog(modifier = Modifier.semantics { testTagsAsResourceId = true }, onDismissRequest = model.session::dismissError,
        title = { Text("Could Not Complete") }, text = { Text(message) },
        confirmButton = { TextButton(onClick = model.session::dismissError) { Text("OK") } }) }
}

@Composable
private fun SearchAndFilters(state: ShelvesState, model: ShelvesViewModel) {
    Column(Modifier.padding(horizontal = 20.dp).padding(top = 16.dp)) {
        OutlinedTextField(state.query, model::query, Modifier.fillMaxWidth().testTag("shelves.search"), singleLine = true,
            placeholder = { Text("Search titles & authors…", fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, fontSize = 15.sp) },
            leadingIcon = { Icon(Icons.Default.Search, null, Modifier.size(20.dp)) },
            trailingIcon = { if (state.query.isNotEmpty()) IconButton(onClick = { model.query("") }) { Icon(Icons.Default.Close, "Clear search") } },
            shape = CircleShape, textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Serif, fontSize = 15.sp),
            colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                focusedContainerColor = MaterialTheme.colorScheme.surface, unfocusedBorderColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .12f), focusedBorderColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .3f)))
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp), modifier = Modifier.padding(top = 10.dp, bottom = 8.dp)) {
            FilterMenu("LANGUAGE", state.language, ((if (state.ready) emptyList() else ShelvesViewModel.languages) + state.books.map { it.language }).filter { it.isNotBlank() }.distinct().sorted(), model::language)
            FilterMenu("GENRE", state.genre, if (state.ready) state.books.flatMap { it.genres }.groupingBy { it }.eachCount().entries.sortedByDescending { it.value }.take(40).map { it.key }.sorted() else (ShelvesViewModel.genres + state.books.flatMap { it.genres }).distinct().sorted(), model::genre)
            FilterMenu("LENGTH", state.length, ShelvesViewModel.lengths, model::length)
        }
    }
}
@Composable
private fun FilterMenu(label: String, selected: String?, options: List<String>, onSelect: (String?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Column(Modifier.clickable { expanded = true }.testTag("shelves.filter.$label")) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Eyebrow(label, MaterialTheme.colorScheme.onSurface)
                Icon(Icons.Default.KeyboardArrowDown, null, Modifier.size(15.dp))
            }
            Box(Modifier.width(82.dp).height(2.dp).background(if (selected != null) MaterialTheme.colorScheme.primary else Color.Transparent))
        }
        DropdownMenu(expanded, onDismissRequest = { expanded = false }, modifier = Modifier.semantics { testTagsAsResourceId = true }) {
            DropdownMenuItem(text = { Text(when (label) { "LANGUAGE" -> "All Languages"; "GENRE" -> "All Genres"; else -> "Any Length" }) }, onClick = { expanded = false; onSelect(null) }, trailingIcon = { if (selected == null) Icon(Icons.Default.Check, null) })
            options.forEach { option -> DropdownMenuItem(text = { Text(option) }, onClick = { expanded = false; onSelect(option) },
                trailingIcon = { if (selected == option) Icon(Icons.Default.Check, null) }) }
        }
    }
}
@Composable
private fun StatusLine(state: ShelvesState, model: ShelvesViewModel) {
    val text = when {
        state.searching -> "Searching LibriVox…"
        state.offline -> if (state.filtered) "Offline — showing saved matches." else "Offline — showing saved books."
        state.partial -> {
            val scope = if (state.books.isEmpty()) "from books saved so far" else "from ${state.books.size} books saved so far"
            if (state.preparing) "Partial results $scope — the full catalog is still downloading." else "Partial results $scope."
        }
        state.preparing -> if (state.ready) "Checking for new books…" else "Preparing offline search… ${state.books.size} saved"
        state.error != null -> state.error
        else -> null
    } ?: return
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 4.dp, bottom = 14.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (state.searching || state.preparing && !state.offline && !state.partial) CircularProgressIndicator(Modifier.size(13.dp), strokeWidth = 1.dp)
        else Icon(if (state.offline) Icons.Default.WifiOff else Icons.Default.ErrorOutline, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
        Text(text, Modifier.weight(1f), fontSize = 12.sp, fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic,
            color = MaterialTheme.colorScheme.onSurfaceVariant, lineHeight = 16.sp)
        if (state.offline || state.error != null) Text("RETRY", Modifier.clickable(onClick = model::refresh).testTag("shelves.retry"),
            fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.5.sp)
    }
}
@Composable
private fun Eyebrow(text: String, color: Color = MaterialTheme.colorScheme.onSurfaceVariant) {
    Text(text.uppercase(java.util.Locale.ROOT), fontSize = 10.sp, lineHeight = 13.sp, letterSpacing = 1.5.sp, fontWeight = FontWeight.SemiBold, color = color)
}
@Composable
private fun Hero(book: CatalogBook, onOpen: () -> Unit) {
    Surface(onClick = onOpen, modifier = Modifier.padding(horizontal = 20.dp).padding(bottom = 10.dp).testTag("shelves.hero"),
        shape = RoundedCornerShape(20.dp), shadowElevation = 2.dp) {
        Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
            GeneratedBookCover(book.title, Modifier.size(96.dp).rotate(-2.5f), 10)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Eyebrow("Today's Pick · ${book.duration}", MaterialTheme.colorScheme.primary)
                Text(book.title, fontSize = 19.sp, lineHeight = 23.sp, fontWeight = FontWeight.Medium, fontFamily = FontFamily.Serif, maxLines = 2)
                Text("by ${book.author}", fontSize = 12.sp, fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                Text(plainDescription(book.description), fontSize = 12.sp, lineHeight = 16.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
            }
        }
    }
}
@Composable
private fun SectionHeader(text: String, icon: androidx.compose.ui.graphics.vector.ImageVector? = null, onClick: () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 18.dp, bottom = 12.dp).then(if (icon != null) Modifier.clickable(onClick = onClick) else Modifier),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        if (icon != null) Icon(icon, "Toggle collections", Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        HorizontalDivider(Modifier.weight(1f), thickness = .5.dp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = .18f))
    }
}
@Composable
private fun CollectionCard(shelf: BookCollection, open: () -> Unit) {
    val icon = when (shelf.id) { "ancient-wisdom" -> Icons.Default.Grass; "gothic-horror" -> Icons.Default.NightsStay
        "detective-mystery" -> Icons.Default.Search; "grand-adventures" -> Icons.Default.Map; "love-society" -> Icons.Default.Favorite; else -> Icons.Default.Schedule }
    Surface(onClick = open, shape = RoundedCornerShape(14.dp), shadowElevation = 1.dp, modifier = Modifier.testTag("shelves.collection.${shelf.id}")) {
        Column(Modifier.width(160.dp).height(96.dp).padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(icon, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary)
            Text(shelf.title, fontSize = 15.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            Text("${shelf.ids.size} books", fontSize = 11.sp, lineHeight = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
@Composable
private fun CatalogRow(book: CatalogBook, index: Int, model: ShelvesViewModel, open: () -> Unit) {
    val session by model.session.state.collectAsStateWithLifecycle()
    Column {
        Row(Modifier.fillMaxWidth().clickable(onClick = open).testTag("shelves.book.${book.id}").padding(horizontal = 20.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(13.dp)) {
            Text("%02d".format(java.util.Locale.ROOT, index + 1), Modifier.width(24.dp), fontSize = 15.sp, fontFamily = FontFamily.Serif,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .5f))
            GeneratedBookCover(book.title, Modifier.size(48.dp), 7)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(book.title, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium, fontSize = 15.sp, lineHeight = 18.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(book.author, fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Eyebrow("${book.duration} · ${book.sizeMB} MB", MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .6f))
                session.downloads[book.id]?.let { DownloadLine(it) }
            }
            IconButton(onClick = { model.session.sample(book) }, enabled = model.session.connected() || session.sampleId == book.id,
                modifier = Modifier.size(32.dp).testTag("shelves.sample.${book.id}")) {
                if (session.sampleId == book.id && session.sampleLoading) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 1.dp)
                else Icon(if (session.sampleId == book.id) Icons.Default.StopCircle else Icons.Default.PlayCircleOutline,
                    if (session.sampleId == book.id) "Stop Sample" else "Play 20s Sample", Modifier.size(24.dp))
            }
        }
        HorizontalDivider(thickness = .5.dp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = .12f))
    }
}
@Composable
private fun ShelvesBack(title: String, back: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
        Text(title, Modifier.weight(1f).padding(end = 20.dp), fontSize = 18.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
@Composable
private fun ShelvesEmpty(title: String, message: String, retry: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, fontFamily = FontFamily.Serif, fontSize = 19.sp)
        Text(message, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        TextButton(onClick = retry) { Text("Retry", color = MaterialTheme.colorScheme.onSurface) }
    }
}
@Composable
private fun CollectionColophon() {
    Text("Free books courtesy of LibriVox — public domain audio recorded by volunteers.",
        Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp), fontSize = 11.sp,
        color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
}
@Composable
private fun Colophon() {
    Text("Every book here is read by LibriVox volunteers and free in the public domain — yours to keep, forever.",
        Modifier.padding(24.dp), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
}
internal fun plainDescription(html: String): String = android.text.Html.fromHtml(html, android.text.Html.FROM_HTML_MODE_COMPACT).toString().trim()

@Composable
private fun DownloadLine(entry: DownloadEntry) {
    when {
        entry.complete -> Text("Downloaded", fontSize = 11.sp)
        entry.error != null -> Text(entry.error, fontSize = 11.sp, color = MaterialTheme.colorScheme.error)
        else -> {
            if (entry.totalTracks == 0) Text("Preparing…", fontSize = 11.sp)
            else {
                LinearProgressIndicator(progress = { entry.progress }, Modifier.fillMaxWidth())
                Text(if (entry.progress >= 1) "Finishing…" else "Track ${entry.currentTrack} of ${entry.totalTracks}", fontSize = 11.sp)
            }
        }
    }
}

@Composable
internal fun CatalogDownloadBadge(catalogId: String?) {
    if (catalogId == null) return
    val context = LocalContext.current
    val session = remember { ShelvesSession.get(context) }
    val state by session.state.collectAsStateWithLifecycle()
    state.downloads[catalogId]?.let { entry ->
        Column {
            DownloadLine(entry)
            if (!entry.complete) TextButton(onClick = {
                if (entry.error == null) session.cancel(catalogId) else session.retryDownload(catalogId)
            }) { Text(if (entry.error == null) "Cancel Download" else "Try Again", color = MaterialTheme.colorScheme.onSurface, fontSize = 11.sp) }
        }
    }
}

@Composable
internal fun CatalogDetail(book: CatalogBook, books: List<CatalogBook>, model: ShelvesViewModel, back: () -> Unit,
    open: (CatalogBook) -> Unit, viewLibrary: (String) -> Unit) {
    val session by model.session.state.collectAsStateWithLifecycle()
    var expanded by rememberSaveable(book.id) { mutableStateOf(false) }
    var adding by remember(book.id) { mutableStateOf(false) }
    var error by remember(book.id) { mutableStateOf<String?>(null) }
    var identity by remember(book.id) { mutableStateOf<LibraryBook?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(book.id, session.libraryRevision) { identity = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { model.session.identity(book.id) } }
    ShelvesBack(book.title, back)
    LazyColumn(Modifier.fillMaxSize().testTag("shelves.detail"), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                GeneratedBookCover(book.title, Modifier.size(110.dp), 12)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(book.title, fontSize = 20.sp, lineHeight = 24.sp, fontWeight = FontWeight.Bold)
                    Text(book.author, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("◷ ${book.duration}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("↓ ${book.sizeMB} MB", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(book.language, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        item {
            OutlinedButton(onClick = { model.session.sample(book) }, modifier = Modifier.testTag("shelves.sample.detail"), enabled = model.session.connected() || session.sampleId == book.id,
                shape = CircleShape, border = null, colors = ButtonDefaults.outlinedButtonColors(containerColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .06f), contentColor = MaterialTheme.colorScheme.onSurface)) {
                Icon(if (session.sampleId == book.id) Icons.Default.Stop else Icons.Default.PlayArrow, null, Modifier.size(16.dp))
                Text(if (session.sampleId == book.id) "Stop Sample" else "Play 20s Sample", fontSize = 15.sp)
            }
        }
        if (book.description.isNotBlank()) item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("About", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Text(plainDescription(book.description), fontSize = 15.sp, lineHeight = 20.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = if (expanded) Int.MAX_VALUE else 4, overflow = TextOverflow.Ellipsis)
                Text(if (expanded) "Show less" else "Show more", Modifier.clickable { expanded = !expanded }, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }
        }
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val entry = session.downloads[book.id]
                if (entry != null && !entry.complete) {
                    DownloadLine(entry)
                    if (entry.error != null) Row {
                        OutlinedButton(onClick = { model.session.download(book) }) { Text("Try Again") }
                        TextButton(onClick = { model.session.dismissDownload(book.id) }) { Text("Dismiss") }
                    }
                    else TextButton(onClick = { model.session.cancel(book.id) }) { Text("Cancel Download") }
                } else if (identity?.isDownloaded != true) {
                    Button(onClick = { model.session.download(book) }, Modifier.fillMaxWidth().testTag("shelves.download"), shape = RoundedCornerShape(10.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Color.Black, contentColor = Color.White)) {
                        Icon(Icons.Default.DownloadForOffline, null); Spacer(Modifier.width(8.dp)); Text("Download Free Book")
                    }
                }
                if (identity == null) OutlinedButton(onClick = {
                    adding = true; error = null
                    scope.launch {
                        try { identity = model.session.add(book) } catch (cancel: kotlinx.coroutines.CancellationException) { throw cancel }
                        catch (failure: Exception) { error = failure.message ?: "Couldn't add this book. Please try again." }
                        finally { adding = false }
                    }
                }, enabled = !adding, modifier = Modifier.fillMaxWidth().testTag("shelves.add"), shape = RoundedCornerShape(10.dp),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .2f)),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)) {
                    Icon(Icons.Default.AddCircleOutline, null); Spacer(Modifier.width(8.dp)); Text(if (adding) "Adding to library…" else "Add to Library")
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 12.sp) }
                identity?.let { added ->
                    Text("Added to Your Library", color = Color(0xFF30A758), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.CenterHorizontally))
                    OutlinedButton(onClick = { viewLibrary(added.id) }, Modifier.fillMaxWidth(), colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)) { Text("View in Library") }
                }
            }
        }
        item { AlternativesSection(book, books, model) { open(it) } }
    }
}

@Composable
internal fun AlternativesSection(book: CatalogBook, books: List<CatalogBook>, model: ShelvesViewModel, open: (CatalogBook) -> Unit) {
    val alternatives = OtherRecordings.alternatives(book, books)
    if (alternatives.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Other Recordings", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text("${alternatives.size}", fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text("Same book, different narrators. Play a sample to compare.", fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        alternatives.forEach { other ->
            val session by model.session.state.collectAsStateWithLifecycle()
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.weight(1f).clickable { open(other) }.testTag("shelves.book.${other.id}"),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    GeneratedBookCover(other.title, Modifier.size(44.dp), cornerRadius = 8)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(OtherRecordings.label(other.title) ?: "Original", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        Text(other.duration, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(16.dp))
                }
                IconButton({ model.session.sample(other) }, enabled = model.session.connected() || session.sampleId == other.id,
                    modifier = Modifier.size(30.dp).testTag("shelves.alternative.sample.${other.id}")) {
                    Icon(if (session.sampleId == other.id) Icons.Default.StopCircle else Icons.Default.PlayCircleOutline, "Play sample")
                }
            }
        }
    }
}

@Composable
internal fun SharedDownloads(session: ShelvesSession, open: (String) -> Unit = {}) {
    val state by session.state.collectAsStateWithLifecycle()
    if (state.downloads.isNotEmpty()) Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Downloads · ${state.downloads.size}", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            HorizontalDivider(Modifier.weight(1f))
        }
        state.downloads.entries.sortedBy { it.value.title }.forEach { (id, entry) ->
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(entry.title, Modifier.weight(1f).clickable { open(id) }.testTag("download.open.$id"), fontSize = 15.sp)
                    when {
                        entry.error != null -> {
                            TextButton({ session.retryDownload(id) }, Modifier.testTag("download.retry.$id")) { Text("Retry") }
                            TextButton({ session.dismissDownload(id) }, Modifier.testTag("download.dismiss.$id")) { Text("Dismiss") }
                        }
                        !entry.complete -> TextButton({ session.cancel(id) }, Modifier.testTag("download.cancel.$id")) { Text("Cancel") }
                    }
                }
                DownloadLine(entry)
            }
        }
    }
}
