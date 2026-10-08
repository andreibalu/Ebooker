package dev.unpaged.android.library

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.clickable
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ArrowBackIosNew
import androidx.compose.material.icons.automirrored.filled.FormatListBulleted
import androidx.compose.ui.text.style.TextOverflow
import dev.unpaged.android.*
import kotlinx.coroutines.launch
import androidx.compose.foundation.background
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import dev.unpaged.android.activity.*
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import dev.unpaged.android.R
import dev.unpaged.android.playback.*
import dev.unpaged.android.moments.MomentList

@Composable
fun LibraryScreen(preferences: UnpagedPreferences, model: LibraryViewModel = viewModel()) {
    val state by model.state.collectAsStateWithLifecycle()
    val context = androidx.compose.ui.platform.LocalContext.current
    val shelvesSession = remember { dev.unpaged.android.shelves.ShelvesSession.get(context) }
    val downloads by shelvesSession.state.collectAsStateWithLifecycle()
    val player = remember { PlayerController.get(context) }
    val playback by player.state.collectAsStateWithLifecycle()
    val activityStore = remember { SQLiteLibraryStore(context) }
    DisposableEffect(activityStore) { onDispose { activityStore.close() } }
    var sessions by remember { mutableStateOf<List<ReadingSession>>(emptyList()) }
    LaunchedEffect(playback.revision) { sessions = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { activityStore.readingSessions() } }
    val stats = ReadingStats(sessions, state.books.count { it.isFinished })
    var showStats by rememberSaveable { mutableStateOf(false) }
    var fullPlayer by rememberSaveable { mutableStateOf(false) }
    val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    val playBook: (LibraryBook, Int?) -> Unit = { book, track ->
        player.play(book, track)
        fullPlayer = true
        if (android.os.Build.VERSION.SDK_INT >= 33 && preferences.text("notificationPrompted", "false") != "true") {
            preferences.setText("notificationPrompted", "true")
            notificationPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    LaunchedEffect(playback.revision) { if (playback.revision > 0) model.refreshPlayback() }
    val lifecycleOwner = androidx.lifecycle.compose.LocalLifecycleOwner.current
    DisposableEffect(player, lifecycleOwner) {
        val lifecycle = lifecycleOwner.lifecycle
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_STOP) player.background()
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer); player.background() }
    }
    preferenceRevision(preferences)
    var backupLibrary by rememberSaveable { mutableStateOf(false) }
    var locateId by rememberSaveable { mutableStateOf<String?>(null) }
    var settings by rememberSaveable { mutableStateOf(false) }
    val tabs = if (preferences.shelvesFirst()) listOf("Favorites", "Shelves", "Library") else listOf("Favorites", "Library", "Shelves")
    val landing = remember { preferences.text("onboardingLanding", "") }
    val pager = rememberPagerState(initialPage = if (landing.isNotEmpty()) tabs.indexOf(landing).coerceAtLeast(0) else if (preferences.shelvesFirst()) 1 else 0, pageCount = { 3 })
    LaunchedEffect(Unit) { if (landing.isNotEmpty()) preferences.setText("onboardingLanding", "") }
    val scope = rememberCoroutineScope()
    var absDetail by remember { mutableStateOf(false) }
    var absConnect by rememberSaveable { mutableStateOf(false) }
    val absClient = (LocalContext.current.applicationContext as UnpagedApplication).abs
    val absSummary by absClient.summary.collectAsStateWithLifecycle()
    var sortMenu by remember { mutableStateOf(false) }
    val tab = tabs[pager.currentPage]
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    var renameId by rememberSaveable { mutableStateOf<String?>(null) }
    var renameTitle by rememberSaveable { mutableStateOf("") }
    var removeId by rememberSaveable { mutableStateOf<String?>(null) }
    val selected = state.books.firstOrNull { it.id == selectedId }?.let { book ->
        if (playback.book?.id == book.id) playback.book?.copy(isFavorite = book.isFavorite, title = book.title, coverRevision = book.coverRevision) else book
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> model.prepare(uris, state.books.firstOrNull { it.id == locateId }); locateId = null }
    val onImport = { picker.launch(arrayOf("*/*")) }
    val canImport = !state.loading && !state.busy && state.error != LibraryFailure.LOAD
    BackHandler(enabled = selectedId != null && state.pending == null) { selectedId = null }

    Scaffold(Modifier.semantics { testTagsAsResourceId = true }, bottomBar = {
        if (playback.book != null) Column {
            MiniPlayer(playback, player) { fullPlayer = true }
            Spacer(Modifier.windowInsetsBottomHeight(WindowInsets.navigationBars))
        }
    }) { insets ->
        Column(Modifier.fillMaxSize().padding(insets)) {
            if (selected == null && !absDetail) {
                LibraryHeader(state.books.count { it.isInActiveLibrary }, canImport, onImport) { settings = true }
                Column(Modifier.padding(horizontal = 20.dp)) {
                    Row(Modifier.fillMaxWidth().padding(top = 12.dp)) {
                        tabs.forEachIndexed { index, label ->
                            Box(Modifier.weight(1f)) {
                                Column(Modifier.fillMaxWidth().clickable {
                                    if (pager.currentPage == index) sortMenu = true else scope.launch { pager.animateScrollToPage(index) }
                                }.testTag("tab.$label").semantics { role = Role.Tab; this.selected = tab == label }, horizontalAlignment = Alignment.CenterHorizontally) {
                                    Row(Modifier.padding(bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Text(label, fontSize = 15.sp, lineHeight = 18.sp, fontWeight = if (tab == label) FontWeight.SemiBold else FontWeight.Normal,
                                            color = if (tab == label) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                                        if (tab == label) Icon(Icons.Default.KeyboardArrowDown, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    Box(Modifier.fillMaxWidth().height(2.dp).background(if (tab == label) MaterialTheme.colorScheme.onSurface else Color.Transparent))
                                }
                                if (label == "Shelves") dev.unpaged.android.abs.CatalogSourceMenu(preferences, sortMenu && tab == label, { sortMenu = false }, { absConnect = true })
                                else DropdownMenu(expanded = sortMenu && tab == label, modifier = Modifier.semantics { testTagsAsResourceId = true }, onDismissRequest = { sortMenu = false }) {
                                    LibrarySort.entries.forEach { option ->
                                        DropdownMenuItem(text = { Text(option.label) }, onClick = { preferences.setSort(label, option); sortMenu = false },
                                            trailingIcon = { if (preferences.sort(label) == option) Icon(Icons.Default.Check, null) })
                                    }
                                }
                            }
                        }
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = .12f), thickness = .5.dp)
                }
            } else if (selected != null) DetailTopBar(selected, onBack = { selectedId = null }, onPlayer = if (playback.book?.id == selected.id) ({ fullPlayer = true }) else null)
            when {
                state.loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                state.preparing -> Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    CircularProgressIndicator()
                    Text(stringResource(R.string.preparing_tracks, state.completed, state.total))
                    Text(stringResource(R.string.copying_audio))
                    TextButton(onClick = model::cancelPreparation) { Text(stringResource(R.string.cancel)) }
                }
                selected != null -> BookDetails(selected, state.moments[selected.id].orEmpty(), onPlay = { playBook(selected, null) }, onTrack = { playBook(selected, it) }, onMoment = { player.playMoment(selected, it); fullPlayer = true }, onSaveMoment = model::saveMoment, onDeleteMoment = model::deleteMoment, onCover = { model.saveCover(selected, it) })
                else -> HorizontalPager(pager, Modifier.fillMaxSize(), userScrollEnabled = !absDetail) { page ->
                    val pageTab = tabs[page]
                    val books = sortedBooks(if (pageTab == "Favorites") state.books.filter { it.isInActiveLibrary && it.isFavorite } else state.books.filter { it.isInActiveLibrary }, preferences.sort(pageTab))
                    when {
                        pageTab == "Shelves" -> dev.unpaged.android.abs.SourceShelves(preferences, onDetailChanged = { absDetail = it }, onPlay = { playBook(it, null) }, onLibraryChanged = model::refreshCatalogBooks, onViewLibrary = { id -> selectedId = id; scope.launch { pager.scrollToPage(tabs.indexOf("Library")) } })
                        pageTab == "Favorites" && books.isEmpty() && sessions.isEmpty() -> EmptyFavorites()
                        books.isEmpty() && pageTab != "Favorites" -> EmptyLibrary(canImport, onImport) { scope.launch { pager.animateScrollToPage(tabs.indexOf("Shelves")) } }
                        else -> LazyVerticalGrid(GridCells.Fixed(2), Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(horizontal = 20.dp, vertical = if (pageTab == "Favorites" && sessions.isNotEmpty()) 16.dp else 32.dp), horizontalArrangement = Arrangement.spacedBy(16.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            if (pageTab == "Library" && downloads.downloads.isNotEmpty()) item(span = { GridItemSpan(2) }) {
                                SharedDownloads(dev.unpaged.android.shelves.ShelvesSession.get(context)) { catalogID ->
                                    selectedId = state.books.firstOrNull { it.catalogId == catalogID }?.id
                                }
                            }
                            if (pageTab == "Favorites" && sessions.isNotEmpty()) item(span = { GridItemSpan(2) }) { ActivityCard(stats) { showStats = true } }
                            items(books, key = { it.id }) { book -> LibraryBookCard(book, { model.toggleFavorite(book) }, { removeId = book.id }, playing = playback.book?.id == book.id && playback.playing, onResume = { playBook(book, null) }, onRename = { renameId = book.id; renameTitle = book.title }) { selectedId = book.id } }
                        }
                    }
                }
            }
        }
    }
    if (showStats) ReadingStatsScreen(stats) { showStats = false }
    if (fullPlayer && playback.book != null) FullPlayer(player) { fullPlayer = false }
    playback.error?.let { message -> AlertDialog(modifier = Modifier.semantics { testTagsAsResourceId = true }, onDismissRequest = player::dismissError,
        title = { Text("Playback unavailable") }, text = { Text(message) },
        confirmButton = { TextButton(onClick = player::dismissError) { Text("OK") } }) }
    if (absConnect) dev.unpaged.android.abs.ABSConnect(absClient, { absConnect = false }) { preferences.setShelvesSource("audiobookshelf"); absConnect = false }
    val backupSheets: @Composable () -> Unit = {
        if (backupLibrary) dev.unpaged.android.backup.BackedUpLibrary(state.books, state.moments, preferences.backupEnabled(),
            onLocate = { locateId = it.id; picker.launch(arrayOf("*/*")) }, onStream = model::restoreFree,
            onDelete = { player.removed(it.id); model.remove(it, permanent = true) }, absConnected = absSummary != null) { backupLibrary = false }
        state.restoreMatch?.let { book ->
            dev.unpaged.android.backup.RestoreMatchSheet(book, state.moments[book.id].orEmpty().size, state.busy,
                state.restoreMismatch,
                { model.restore(allowMismatch = state.restoreMismatch) },
                if (state.locateTarget != null || state.restoreMismatch) model::discard else model::addAsNew, model::discard)
        }
    }
    if (settings) SettingsScreen(preferences, onOpenShelves = { scope.launch { pager.scrollToPage(tabs.indexOf("Shelves")) } },
        onOpenBackup = { backupLibrary = true }, childSheets = backupSheets) { settings = false }
    else backupSheets()
    state.pending?.takeIf { state.restoreMatch == null }?.let { ImportReview(it, state.busy, { title, author -> model.save(title, author); scope.launch { pager.scrollToPage(tabs.indexOf("Library")) } }, model::discard) }
    state.books.firstOrNull { it.id == renameId }?.let { book ->
        AlertDialog(modifier = Modifier.semantics { testTagsAsResourceId = true }, onDismissRequest = { renameId = null }, title = { Text("Rename Audiobook") },
            text = { OutlinedTextField(renameTitle, { renameTitle = it }, label = { Text("Book title") },
                singleLine = true, modifier = Modifier.testTag("book.rename.title")) },
            confirmButton = { TextButton(enabled = renameTitle.isNotBlank() && !state.busy, onClick = {
                model.rename(book, renameTitle); renameId = null
            }, modifier = Modifier.testTag("book.rename.save")) { Text("Save") } },
            dismissButton = { TextButton(onClick = { renameId = null }) { Text("Cancel") } })
    }
    state.books.firstOrNull { it.id == removeId }?.let { book ->
        AlertDialog(modifier = Modifier.semantics { testTagsAsResourceId = true }, onDismissRequest = { if (!state.busy) removeId = null },
            title = { Text(if (book.absItemID != null || book.isStreamingOnly) "Remove from Library?" else if (book.isFreeBook) "Remove Download?" else if (preferences.backupEnabled()) "Remove from This Phone?" else "Remove from Library?") },
            text = { Text(removalMessage(book, preferences.backupEnabled())) },
            confirmButton = {
                TextButton(enabled = !state.busy, onClick = { player.removed(book.id); model.remove(book); removeId = null; selectedId = null }) {
                    Text(if (book.absItemID != null || book.isStreamingOnly) "Remove from Library" else if (book.isFreeBook) "Remove Download"
                        else if (preferences.backupEnabled()) "Remove from This Phone" else "Remove from Library")
                }
            },
            dismissButton = { TextButton(enabled = !state.busy, onClick = { removeId = null }) { Text(stringResource(R.string.cancel)) } })
    }
    state.error?.let { error ->
        AlertDialog(modifier = Modifier.semantics { testTagsAsResourceId = true }, onDismissRequest = { if (error != LibraryFailure.LOAD) model.dismissError() },
            title = { Text(state.errorTitle) },
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

internal fun sortedBooks(books: List<LibraryBook>, sort: LibrarySort): List<LibraryBook> = when (sort) {
    LibrarySort.RECENT -> books.sortedByDescending { it.lastPlayedAt ?: it.dateAdded }
    LibrarySort.TITLE -> books.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.title })
    LibrarySort.AUTHOR -> books.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.author.ifBlank { it.title } })
    LibrarySort.DURATION -> books.sortedByDescending { it.durationMs }
    LibrarySort.DATE_ADDED -> books.sortedByDescending { it.dateAdded }
}

@Composable
fun DetailTopBar(book: LibraryBook, onBack: () -> Unit, onPlayer: (() -> Unit)? = null) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
        Surface(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart).size(44.dp), shape = CircleShape,
            color = MaterialTheme.colorScheme.surface, border = androidx.compose.foundation.BorderStroke(.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .15f))) {
            Box(contentAlignment = Alignment.Center) { Icon(Icons.Default.ArrowBackIosNew, "Back", Modifier.size(26.dp)) }
        }
        Text(book.title, Modifier.align(Alignment.Center).padding(horizontal = if (onPlayer == null) 50.dp else 78.dp),
            fontSize = 17.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (onPlayer != null) Surface(onClick = onPlayer, modifier = Modifier.align(Alignment.CenterEnd).testTag("book.player"),
            shape = CircleShape, color = MaterialTheme.colorScheme.surface,
            border = androidx.compose.foundation.BorderStroke(.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .15f))) {
            Text("Player", Modifier.padding(horizontal = 16.dp, vertical = 10.dp), fontSize = 17.sp, lineHeight = 20.sp)
        }
    }
}

/** Playback slice supplies these callbacks; unavailable controls retain the reference layout. */
@Composable
fun BookDetails(book: LibraryBook, moments: List<LibraryMoment>,
    onPlay: (() -> Unit)? = null, onTrack: ((Int) -> Unit)? = null,
    onMoment: (LibraryMoment) -> Unit = {}, onSaveMoment: (LibraryMoment) -> Unit = {}, onDeleteMoment: (String) -> Unit = {}, onCover: (android.graphics.Bitmap?) -> Unit = {}) {
    val catalogModel: dev.unpaged.android.shelves.ShelvesViewModel = viewModel()
    val catalogState by catalogModel.state.collectAsStateWithLifecycle()
    var alternative by remember(book.id) { mutableStateOf<dev.unpaged.android.shelves.CatalogBook?>(null) }
    alternative?.let { selected ->
        BackHandler { alternative = null }
        CatalogDetail(selected, catalogState.books, catalogModel, { alternative = null },
            { alternative = it }, { alternative = null })
        return
    }
    var tracksExpanded by rememberSaveable(book.id) { mutableStateOf(false) }
    var momentsExpanded by rememberSaveable(book.id) { mutableStateOf(false) }
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item {
            Surface(shape = UnpagedTheme.detailShape, shadowElevation = UnpagedTheme.cardShadow) {
                Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.Top) {
                        EditableBookCover(book, onCover)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(book.title, fontSize = 20.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold, maxLines = 3)
                            Text(book.author.ifBlank { stringResource(R.string.unknown_author) }, fontSize = 15.sp, lineHeight = 18.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Icon(DriveIcon, null, Modifier.size(10.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                Text(if (book.isAudioMissing) "Audio Missing" else if (!book.isDownloaded) "Streaming" else "${book.storageBytes / (1024 * 1024)} MB", fontSize = 12.sp, lineHeight = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Text("at ${trackDuration(book.currentPositionMs)}", Modifier.testTag("book.position"), fontSize = 12.sp, lineHeight = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Button(onClick = { onPlay?.invoke() }, enabled = onPlay != null, modifier = Modifier.testTag("book.play"),
                                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp), shape = CircleShape,
                                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onSurface, contentColor = MaterialTheme.colorScheme.background,
                                    disabledContainerColor = MaterialTheme.colorScheme.onSurface, disabledContentColor = MaterialTheme.colorScheme.background)) {
                                Icon(Icons.Default.PlayArrow, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
                                Text(if (book.lastPlayedAt == null) "Play" else "Continue", fontSize = 15.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        BookProgress(book.progress)
                        Text(if (book.isFinished) "Finished" else "${kotlin.math.round(book.progress * 100).toInt()}% · ${shortDuration((book.durationMs - book.globalPositionMs).coerceAtLeast(0))} remaining",
                            fontSize = 12.sp, lineHeight = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        if (book.isFreeBook && !book.isDownloaded) item {
            val sessionState by catalogModel.session.state.collectAsStateWithLifecycle()
            Surface(shape = RoundedCornerShape(18.dp), shadowElevation = 2.dp) {
                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Download for Offline", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Text("Save this LibriVox book to listen without internet.", fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    val entry = sessionState.downloads[book.catalogId]
                    if (entry != null) {
                        CatalogDownloadBadge(book.catalogId)
                    } else Button(onClick = {
                        catalogState.books.firstOrNull { it.id == book.catalogId }?.let(catalogModel.session::download)
                    }, modifier = Modifier.fillMaxWidth().testTag("book.download"), shape = CircleShape) { Text("Download for Offline") }
                }
            }
        }
        item {
            Column(verticalArrangement = Arrangement.spacedBy(24.dp)) {
                dev.unpaged.android.ai.RecapCard(book)
                Surface(shape = UnpagedTheme.disclosureShape, shadowElevation = UnpagedTheme.cardShadow) {
                    Column {
                        MomentList(book.id, moments, momentsExpanded, { momentsExpanded = !momentsExpanded }, onMoment, onSaveMoment, onDeleteMoment)
                    }
                }
            }
        }
        item {
            Surface(shape = UnpagedTheme.disclosureShape, shadowElevation = UnpagedTheme.cardShadow) {
                Column {
                    DisclosureRow("${book.tracks.size} ${if (book.tracks.size == 1) "track" else "tracks"}", "book.tracks", Icons.AutoMirrored.Filled.FormatListBulleted, tracksExpanded) { tracksExpanded = !tracksExpanded }
                    if (tracksExpanded) Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        book.tracks.forEachIndexed { index, track ->
                            Surface(shape = RoundedCornerShape(16.dp), shadowElevation = 1.dp) {
                                Row(Modifier.fillMaxWidth().clickable(enabled = onTrack != null) { onTrack?.invoke(index) }
                                    .padding(horizontal = 16.dp, vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Text("${index + 1}", Modifier.width(24.dp), fontSize = 12.sp, lineHeight = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                        Text(track.title, fontSize = 15.sp)
                                        Text(trackDuration(track.durationMs), fontSize = 12.sp, lineHeight = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    Icon(Icons.Default.PlayCircleOutline, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }
        }
        if (book.isFreeBook) item {
            catalogState.books.firstOrNull { it.id == book.catalogId }?.let { catalogBook ->
                AlternativesSection(catalogBook, catalogState.books, catalogModel) { alternative = it }
            }
        }
    }
}

@Composable
private fun DisclosureRow(label: String, tag: String, icon: androidx.compose.ui.graphics.vector.ImageVector, expanded: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).testTag(tag).padding(horizontal = 16.dp, vertical = 18.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onSurface.copy(alpha = .25f))
        Text(label, Modifier.weight(1f), fontSize = 15.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Icon(if (expanded) Icons.Default.KeyboardArrowDown else Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurface.copy(alpha = .55f))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ImportReview(pending: PendingImport, busy: Boolean, save: (String, String) -> Unit, discard: () -> Unit) {
    val reviewContext = LocalContext.current
    val preview by produceState<android.graphics.Bitmap?>(null, pending.id) {
        value = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            android.graphics.BitmapFactory.decodeFile(java.io.File(reviewContext.filesDir,
                "audiobooks/.staging/${pending.id}/cover.png").absolutePath)
        }
    }
    var title by rememberSaveable(pending.id) { mutableStateOf(pending.suggestedTitle) }
    var author by rememberSaveable(pending.id) { mutableStateOf(pending.suggestedAuthor) }
    val currentBusy by rememberUpdatedState(busy)
    val titleLabel = stringResource(R.string.title)
    val authorLabel = stringResource(R.string.author)
    ModalBottomSheet(onDismissRequest = { if (!busy) discard() }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true,
            confirmValueChange = { value -> !currentBusy || value != SheetValue.Hidden }),
        contentColor = MaterialTheme.colorScheme.onSurface,
        containerColor = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxHeight(.92f).imePadding().semantics { testTagsAsResourceId = true }) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(enabled = !busy, onClick = discard, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)) { Text(stringResource(R.string.cancel)) }
                Text(stringResource(R.string.import_book), Modifier.weight(1f), fontSize = 17.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold)
                TextButton(enabled = !busy && title.isNotBlank(), onClick = { save(title, author) }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)) {
                    Text(stringResource(R.string.add_to_library), fontSize = 13.sp)
                }
            }
            LazyColumn(Modifier.fillMaxWidth(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                item { Text(stringResource(R.string.details), Modifier.padding(start = 16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 17.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold) }
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
                item { Text(stringResource(R.string.imported_files), Modifier.padding(start = 16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 17.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold) }
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

/** Mirrors the iOS delete alert copy; Backed-up Library stands in for the iCloud Library. */
private fun removalMessage(book: LibraryBook, backup: Boolean) = when {
    book.absItemID != null -> "Removes this book from Unpaged. It stays on your Audiobookshelf server, and you can add it again from Shelves."
    book.isStreamingOnly -> if (backup) "Removes this book from your library on this phone. Your progress and moments stay in Backed-up Library, and you can stream it again anytime."
        else "This will remove the book from your library. You can add it again from Shelves."
    book.isFreeBook -> if (backup) "Removes the download from this phone. Your progress and moments stay in Backed-up Library, and you can stream or download it again anytime."
        else "This will remove the downloaded audiobook. You can download it again from Shelves."
    backup -> "Removes the audio from this phone. The book stays in Backed-up Library, and you can restore it anytime."
    else -> "Removes this book and Unpaged's copy of its audio. The original files on your phone are not touched."
}
