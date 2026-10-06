package dev.unpaged.android.abs

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.unpaged.android.*
import dev.unpaged.android.library.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch

@Composable
fun SourceShelves(preferences: UnpagedPreferences, onLibraryChanged: () -> Unit, onViewLibrary: (String) -> Unit, onPlay: (LibraryBook) -> Unit = {}) {
    val client = (LocalContext.current.applicationContext as UnpagedApplication).abs
    val summary by client.summary.collectAsStateWithLifecycle()
    preferenceRevision(preferences)
    var connect by rememberSaveable { mutableStateOf(false) }
    var settings by rememberSaveable { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    LaunchedEffect(client) { runCatching { client.reload() } }
    val source = preferences.shelvesSource(summary != null)
    Column {
        Box(Modifier.padding(horizontal = 20.dp)) {
            TextButton(onClick = { menu = true }, modifier = Modifier.testTag("shelves.source")) {
                Text(if (source == "audiobookshelf") "Audiobookshelf ▾" else "LibriVox ▾", color = MaterialTheme.colorScheme.onSurface)
            }
            DropdownMenu(menu, { menu = false }, modifier = Modifier.semantics { testTagsAsResourceId = true }) {
                DropdownMenuItem(text = { Text("LibriVox") }, onClick = { preferences.setShelvesSource("librivox"); menu = false }, modifier = Modifier.testTag("shelves.source.librivox"))
                DropdownMenuItem(text = { Text("Audiobookshelf") }, onClick = {
                    menu = false
                    if (summary == null) connect = true else preferences.setShelvesSource("audiobookshelf")
                }, modifier = Modifier.testTag("shelves.source.audiobookshelf"))
            }
        }
        if (source == "audiobookshelf") ABSBrowse(client, preferences, { settings = true }, onLibraryChanged, onViewLibrary, onPlay)
        else ShelvesScreen(onLibraryChanged, onViewLibrary)
    }
    if (connect) ABSConnect(client, { connect = false }) { preferences.setShelvesSource("audiobookshelf"); connect = false }
    if (settings) ABSServerSettings(client, preferences) { settings = false }
}

@Composable
private fun ABSFullScreen(onClose: () -> Unit, content: @Composable () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Box(Modifier.safeDrawingPadding().semantics { testTagsAsResourceId = true }) { content() }
        }
    }
}

@Composable
fun ABSConnect(client: ABSClient, onClose: () -> Unit, onConnected: () -> Unit) {
    var server by rememberSaveable { mutableStateOf(client.summary.value?.server ?: "") }
    var username by rememberSaveable { mutableStateOf("") }
    // Passwords and API keys deliberately never enter savedInstanceState.
    var password by remember { mutableStateOf("") }
    var key by remember { mutableStateOf("") }
    var api by rememberSaveable { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var warning by remember { mutableStateOf(false) }
    var acknowledged by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    fun submit() {
        focus.clearFocus()
        val url = try { ABSRules.serverURL(server) } catch (e: Exception) { error = ABSRules.message(e, server, api); return }
        if (ABSRules.insecureWarning(url, acknowledged, client.summary.value?.server)) { warning = true; return }
        busy = true; error = null
        scope.launch {
            try {
                if (api) client.apiKey(url, key) else client.login(url, username, password)
                password = ""; key = ""; onConnected()
            } catch (e: Exception) { error = ABSRules.message(e, java.net.URI(url).authority, api) }
            finally { busy = false }
        }
    }
    ABSFullScreen(onClose) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().testTag("abs.connect").padding(horizontal = 28.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { TextButton(onClick = onClose, enabled = !busy) { Text("Cancel") } }
            Eyebrow("AUDIOBOOKSHELF")
            Text("Bring your own shelf.", fontFamily = FontFamily.Serif, fontSize = 32.sp, lineHeight = 37.sp)
            Text("Connect your Audiobookshelf server to browse and stream your library in Unpaged.", fontFamily = FontFamily.Serif, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row {
                TextButton(onClick = { api = false; error = null }) { Text("Sign in", color = if (!api) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant) }
                TextButton(onClick = { api = true; error = null }) { Text("API key", color = if (api) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            ABSField("Server", server, "abs.connect.server", false, busy) { server = it; acknowledged = null; error = null }
            if (api) {
                ABSField("API key", key, "abs.connect.apiKey", true, busy) { key = it; error = null }
                Text("Create one in Audiobookshelf under Settings → API Keys.", fontSize = 12.sp)
            } else {
                ABSField("Username", username, "abs.connect.username", false, busy) { username = it; error = null }
                ABSField("Password", password, "abs.connect.password", true, busy) { password = it; error = null }
            }
            error?.let { Text(it, Modifier.testTag("abs.connect.error"), color = MaterialTheme.colorScheme.error, fontSize = 13.sp) }
            Button(onClick = { submit() }, enabled = !busy && server.isNotBlank() && (if (api) key.isNotBlank() else username.isNotBlank() && password.isNotEmpty()),
                modifier = Modifier.fillMaxWidth().testTag("abs.connect.submit"), colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onSurface, contentColor = MaterialTheme.colorScheme.background)) {
                Text(if (busy) "Connecting…" else "Connect")
            }
            Text("Your login stays on this phone, encrypted with Android Keystore.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(24.dp))
        }
        if (warning) AlertDialog(onDismissRequest = { warning = false }, title = { Text("This server isn't using HTTPS") },
            text = { Text("Your password and listening activity will be sent unencrypted. Only continue if you trust the network between this phone and the server.") },
            confirmButton = { TextButton(onClick = { acknowledged = ABSRules.serverURL(server); warning = false; submit() }) { Text("Continue") } },
            dismissButton = { TextButton(onClick = { warning = false }) { Text("Cancel") } })
    }
}

@Composable
private fun ABSField(label: String, value: String, tag: String, secure: Boolean, busy: Boolean, change: (String) -> Unit) {
    OutlinedTextField(value, change, Modifier.fillMaxWidth().testTag(tag), label = { Text(label) }, singleLine = true, enabled = !busy,
        shape = RoundedCornerShape(12.dp), visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None)
}
@Composable private fun Eyebrow(text: String) { Text(text, fontSize = 10.sp, letterSpacing = 1.5.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant) }

@Composable
fun ABSServerSettings(client: ABSClient, preferences: UnpagedPreferences, onOpenShelves: (() -> Unit)? = null, onClose: () -> Unit) {
    val summary by client.summary.collectAsStateWithLifecycle()
    var connect by rememberSaveable { mutableStateOf(false) }
    var confirm by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(client) { runCatching { client.reload() } }
    ABSFullScreen(onClose) {
        Column(Modifier.fillMaxSize().padding(20.dp).testTag("abs.settings"), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Audiobookshelf", Modifier.weight(1f), fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
                TextButton(onClick = onClose) { Text("Done") }
            }
            Surface(shape = UnpagedTheme.settingsShape) {
                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Eyebrow(if (summary == null) "NOT CONNECTED" else "CONNECTED")
                    Text(summary?.server ?: "Bring your own shelf.", fontFamily = FontFamily.Serif, fontSize = 22.sp)
                    if (summary != null) {
                        Text("Signed in as ${summary?.username ?: "API key"}")
                        Text("Method: ${if (summary?.apiKey == true) "API key" else "Username & password"}")
                    } else Text("Connect your Audiobookshelf server to browse and stream your library in Unpaged.")
                }
            }
            if (summary != null) {
                Button(onClick = { preferences.setShelvesSource("audiobookshelf"); onClose(); onOpenShelves?.invoke() }) { Text("Open in Shelves") }
                TextButton(onClick = { confirm = true }, modifier = Modifier.testTag("abs.settings.disconnect")) { Text("Disconnect", color = MaterialTheme.colorScheme.error) }
            } else Button(onClick = { connect = true }) { Text("Connect a Server") }
            Text("Your login stays on this phone, encrypted with Android Keystore. Books stream straight from your server; Unpaged sends your listening position back to it.", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
        if (confirm) AlertDialog(modifier = Modifier.semantics { testTagsAsResourceId = true }, onDismissRequest = { confirm = false }, title = { Text("Disconnect from your server?") },
            text = { Text("Unpaged forgets this login. Books you added stay in your Library, but won't play until you connect again.") },
            confirmButton = { TextButton(onClick = { scope.launch {
                try { client.disconnect(); preferences.setShelvesSource("librivox"); confirm = false; onClose() }
                catch (_: Exception) { error = "Could not forget this login. Please try again."; confirm = false }
            } }, modifier = Modifier.testTag("abs.settings.disconnect.confirm")) { Text("Disconnect") } },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Cancel") } })
    }
    if (connect) ABSConnect(client, { connect = false }) { connect = false }
}

@Composable
private fun ABSBrowse(client: ABSClient, preferences: UnpagedPreferences, onSettings: () -> Unit, onChanged: () -> Unit, onViewLibrary: (String) -> Unit, onPlay: (LibraryBook) -> Unit) {
    var libraries by remember { mutableStateOf<List<ABSLibrary>>(emptyList()) }
    var items by remember { mutableStateOf<List<ABSItem>>(emptyList()) }
    var progress by remember { mutableStateOf<Map<String, ABSProgress>>(emptyMap()) }
    var selectedLibrary by rememberSaveable { mutableStateOf(preferences.text("absSelectedLibraryID", "")) }
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    val selected = items.firstOrNull { it.id == selectedId }
    var query by rememberSaveable { mutableStateOf("") }
    var busy by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    var picker by remember { mutableStateOf(false) }
    var reconnect by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<ABSFailure?>(null) }
    val connection by client.summary.collectAsStateWithLifecycle()
    LaunchedEffect(selectedLibrary, revision) {
        busy = true; error = null; failure = null
        try {
            libraries = client.libraries()
            val library = libraries.firstOrNull { it.id == selectedLibrary } ?: libraries.firstOrNull()
            if (library != null) {
                // Keep the preferred id in preferences without restarting this in-flight load.
                preferences.setText("absSelectedLibraryID", library.id)
                items = client.items(library.id)
                progress = runCatching { client.allProgress() }.getOrDefault(emptyMap())
            } else items = emptyList()
        } catch (e: Exception) { error = ABSRules.message(e, client.summary.value?.server ?: "the server"); failure = (e as? ABSException)?.failure }
        finally { busy = false }
    }
    if (reconnect) ABSConnect(client, { reconnect = false }) { reconnect = false; revision++ }
    BackHandler(selectedId != null) { selectedId = null }
    if (selected != null) {
        ABSDetail(client, selected!!, onChanged, onViewLibrary, onPlay) { selectedId = null }
        return
    }
    val filtered = items.filter { query.isBlank() || it.title.contains(query.trim(), true) || it.author.contains(query.trim(), true) }.sortedBy { it.title.lowercase() }
    LazyColumn(Modifier.fillMaxSize().testTag("abs.browse"), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) { Eyebrow("AUDIOBOOKSHELF · ${connection?.server?.let { java.net.URI(it).authority } ?: "Not connected"}") }
                TextButton(onClick = onSettings, modifier = Modifier.testTag("abs.browse.settings")) { Text("Server") }
            }
        }
        item {
            Box {
                TextButton(onClick = { picker = true }, modifier = Modifier.testTag("abs.libraryPicker")) { Text((libraries.firstOrNull { it.id == selectedLibrary }?.name ?: libraries.firstOrNull()?.name ?: "Your library") + " ▾", fontFamily = FontFamily.Serif, fontSize = 30.sp, color = MaterialTheme.colorScheme.onSurface) }
                DropdownMenu(picker, { picker = false }) { libraries.forEach { library ->
                    DropdownMenuItem(text = { Text(library.name) }, onClick = { selectedLibrary = library.id; query = ""; picker = false })
                } }
            }
        }
        item { OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().testTag("abs.search"), placeholder = { Text("Search titles & authors…") }, singleLine = true, shape = RoundedCornerShape(12.dp)) }
        if (busy) item { CircularProgressIndicator() }
        error?.let { message -> item {
            val signedOut = failure in listOf(ABSFailure.BAD_CREDENTIALS, ABSFailure.EXPIRED_TOKEN, ABSFailure.INACTIVE_API_KEY, ABSFailure.NOT_CONNECTED)
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(if (signedOut) "Your sign-in has expired." else if (failure == ABSFailure.OFFLINE) "You're offline." else "Couldn't load your shelf.", fontFamily = FontFamily.Serif, fontSize = 25.sp)
                Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton(onClick = { if (signedOut) reconnect = true else revision++ }) { Text(if (signedOut) "Reconnect" else "Try Again") }
            }
        } }
        if (!busy && error == null && libraries.isEmpty()) item { Column {
            Text("Nothing to shelve yet.", fontFamily = FontFamily.Serif, fontSize = 25.sp)
            Text("This server has no audiobook libraries. Podcast libraries aren't shown in Unpaged.")
            TextButton(onClick = { revision++ }) { Text("Refresh") }
        } }
        if (query.isBlank()) {
            val continuing = items.filter { progress[it.id]?.let { p -> !p.finished && !p.hidden && p.currentMs > 0 } == true }.sortedByDescending { progress[it.id]?.updated }
            if (continuing.isNotEmpty()) {
                item { Text("Continue Listening", fontWeight = FontWeight.SemiBold) }
                item { LazyRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) { items(continuing, key = { it.id }) { book ->
                    Column(Modifier.width(130.dp).clickable { selectedId = book.id }) { ABSCover(client, book, Modifier.size(130.dp)); Text(book.title, fontFamily = FontFamily.Serif, maxLines = 2) }
                } } }
            }
            if (items.size > 12) {
                item { Text("Recently Added", fontWeight = FontWeight.SemiBold) }
                item { LazyRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) { items(items.sortedByDescending { it.addedAt }.take(12), key = { it.id }) { book ->
                    Column(Modifier.width(130.dp).clickable { selectedId = book.id }) { ABSCover(client, book, Modifier.size(130.dp)); Text(book.title, maxLines = 2) }
                } } }
            }
        }
        item { Row { Text(if (query.isBlank()) "All Books" else "Search Results", Modifier.weight(1f), fontWeight = FontWeight.SemiBold); Text("${filtered.size}", color = MaterialTheme.colorScheme.onSurfaceVariant) }; HorizontalDivider(Modifier.padding(top = 8.dp)) }
        items(filtered.chunked(3), key = { row -> row.first().id }) { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                row.forEach { book ->
                    Column(Modifier.weight(1f).clickable { selectedId = book.id }.testTag("abs.book.${book.id}"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        ABSCover(client, book, Modifier.fillMaxWidth().aspectRatio(1f))
                        Text(book.title, fontFamily = FontFamily.Serif, fontSize = 14.sp, lineHeight = 17.sp, maxLines = 3)
                        Text(book.author, fontFamily = FontFamily.Serif, fontSize = 12.sp, maxLines = 2, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        if (!busy && error == null && filtered.isEmpty() && libraries.isNotEmpty()) item { Column {
            Text(if (query.isBlank()) "This shelf is empty." else "No titles or authors match \"$query\".", fontFamily = FontFamily.Serif)
            if (query.isBlank()) TextButton(onClick = { revision++ }) { Text("Refresh") }
        } }
    }
}

@Composable
internal fun ABSCover(client: ABSClient, item: ABSItem, modifier: Modifier) {
    val connection by client.summary.collectAsStateWithLifecycle()
    var bitmap by remember(item.id, connection?.server) { mutableStateOf<android.graphics.Bitmap?>(null) }
    LaunchedEffect(item.id, item.hasCover, connection?.server) { if (item.hasCover) bitmap = withContext(Dispatchers.IO) { client.cover(item.id) } }
    if (bitmap == null) GeneratedBookCover(item.title, modifier)
    else Image(bitmap!!.asImageBitmap(), "Cover for ${item.title}", modifier.clip(RoundedCornerShape(16.dp)), contentScale = ContentScale.Crop)
}

@Composable
private fun ABSDetail(client: ABSClient, summary: ABSItem, onChanged: () -> Unit, onViewLibrary: (String) -> Unit, onPlay: (LibraryBook) -> Unit, onBack: () -> Unit) {
    val context = LocalContext.current
    val store = remember { SQLiteLibraryStore(context) }
    DisposableEffect(store) { onDispose { store.close() } }
    var item by remember(summary.id) { mutableStateOf(summary) }
    var existing by remember { mutableStateOf<LibraryBook?>(null) }
    var progress by remember { mutableStateOf<ABSProgress?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(summary.id) {
        existing = withContext(Dispatchers.IO) { store.books().firstOrNull { it.absItemID == summary.id } }
        try { item = client.item(summary.id); progress = client.progress(summary.id) }
        catch (e: Exception) { error = ABSRules.message(e, client.summary.value?.server ?: "the server") }
    }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("Back") }
            Text(item.title, Modifier.weight(1f), maxLines = 1, fontWeight = FontWeight.SemiBold)
        }
        var expanded by rememberSaveable(summary.id) { mutableStateOf(false) }
        val current = existing?.globalPositionMs ?: progress?.currentMs ?: 0
        val description = android.text.Html.fromHtml(item.description, android.text.Html.FROM_HTML_MODE_LEGACY).toString().trim()
        fun add(play: Boolean) {
            busy = true
            scope.launch {
                try {
                    val book = existing ?: client.add(item, store)
                    existing = book; onChanged(); error = null
                    if (play) onPlay(book)
                } catch (e: Exception) { error = ABSRules.message(e, client.summary.value?.server ?: "the server") }
                finally { busy = false }
            }
        }
        LazyColumn(Modifier.fillMaxSize().testTag("abs.detail"), contentPadding = PaddingValues(24.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
            item { Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { ABSCover(client, item, Modifier.size(230.dp)) } }
            item {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val minutes = item.durationMs / 60000
                    val duration = if (minutes == 0L) "under 1 min" else if (minutes < 60) "$minutes min" else "${minutes / 60} hr ${minutes % 60} min"
                    Eyebrow("$duration · ${item.chapters.size.takeIf { it > 0 } ?: item.tracks.size} CHAPTERS")
                    Text(item.title, fontFamily = FontFamily.Serif, fontSize = 30.sp, lineHeight = 35.sp, textAlign = TextAlign.Center)
                    if (item.subtitle.isNotBlank()) Text(item.subtitle, fontFamily = FontFamily.Serif, fontStyle = androidx.compose.ui.text.font.FontStyle.Italic, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(item.author, fontFamily = FontFamily.Serif)
                    if (item.narrator.isNotBlank()) Text("Read by ${item.narrator}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (existing != null) Text("In your Library", Modifier.testTag("abs.added"), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (existing?.isFinished == true || existing == null && progress?.finished == true) Text("Finished")
                    else if (current > 0 && item.durationMs > 0) Text("${(100 * current / item.durationMs).coerceIn(1, 99)}% listened", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            item {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(onClick = { add(true) }, enabled = !busy, modifier = Modifier.fillMaxWidth().testTag("abs.play"),
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onSurface, contentColor = MaterialTheme.colorScheme.background)) {
                        Text(if (busy) "Working…" else if (current > 0 && existing?.isFinished != true) "Resume" else "Play")
                    }
                    if (existing == null) OutlinedButton(onClick = { add(false) }, enabled = !busy, modifier = Modifier.fillMaxWidth().testTag("abs.add")) { Text("Add to Library", color = MaterialTheme.colorScheme.onSurface) }
                    else TextButton(onClick = { existing?.let { onViewLibrary(it.id) } }, modifier = Modifier.testTag("abs.viewLibrary")) { Text("View in Library") }
                    Text("Streams from your server. Nothing is downloaded.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    error?.let { Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center) }
                }
            }
            if (description.isNotEmpty()) item {
                Text("About this book", Modifier.padding(bottom = 12.dp), fontWeight = FontWeight.SemiBold); HorizontalDivider(Modifier.padding(bottom = 12.dp))
                Text(description, fontFamily = FontFamily.Serif, lineHeight = 23.sp, maxLines = if (expanded) Int.MAX_VALUE else 5)
                if (description.length > 280) TextButton(onClick = { expanded = !expanded }) { Text(if (expanded) "Show less" else "Show more") }
            }
        }
    }
}
