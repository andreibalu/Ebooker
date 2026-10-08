package dev.unpaged.android.abs

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.border
import androidx.compose.ui.unit.DpOffset
import androidx.compose.foundation.BorderStroke
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.foundation.text.BasicTextField
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
import dev.unpaged.android.SheetDoneButton
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
fun SourceShelves(preferences: UnpagedPreferences, onLibraryChanged: () -> Unit, onViewLibrary: (String) -> Unit, onPlay: (LibraryBook) -> Unit = {}, onDetailChanged: (Boolean) -> Unit = {}) {
    val client = (LocalContext.current.applicationContext as UnpagedApplication).abs
    val summary by client.summary.collectAsStateWithLifecycle()
    preferenceRevision(preferences)
    LaunchedEffect(client) { runCatching { client.reload() } }
    if (preferences.shelvesSource(summary != null) == "audiobookshelf")
        ABSBrowse(client, preferences, onLibraryChanged, onViewLibrary, onPlay, onDetailChanged)
    else ShelvesScreen(onLibraryChanged, onViewLibrary)
}

@Composable
fun CatalogSourceMenu(preferences: UnpagedPreferences, expanded: Boolean, onDismiss: () -> Unit, onConnect: () -> Unit) {
    val client = (LocalContext.current.applicationContext as UnpagedApplication).abs
    val summary by client.summary.collectAsStateWithLifecycle()
    val source = preferences.shelvesSource(summary != null)
    DropdownMenu(expanded, onDismiss, offset = DpOffset(0.dp, (-28).dp), shape = RoundedCornerShape(28.dp), containerColor = MaterialTheme.colorScheme.surface,
        modifier = Modifier.width(250.dp).border(.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .18f), RoundedCornerShape(28.dp)).semantics { testTagsAsResourceId = true }) {
        Text("Catalog source", Modifier.padding(horizontal = 24.dp, vertical = 10.dp), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        listOf("librivox" to "LibriVox", "audiobookshelf" to "Audiobookshelf").forEach { (id, title) ->
            DropdownMenuItem(text = { Column {
                Text(title, fontSize = 17.sp, fontWeight = FontWeight.Normal)
                if (id == "audiobookshelf" && summary == null) Text("Connect your server", fontSize = 13.sp, fontWeight = FontWeight.Normal, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } }, leadingIcon = { Box(Modifier.size(22.dp)) { if (source == id) Icon(Icons.Default.Check, null, tint = MaterialTheme.colorScheme.onSurface) } },
                onClick = { onDismiss(); if (id == "audiobookshelf" && summary == null) onConnect() else preferences.setShelvesSource(id) },
                modifier = Modifier.testTag("shelves.source.$id"))
        }
    }
}

@Composable
private fun ABSFullScreen(onClose: () -> Unit, content: @Composable () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Box(Modifier.safeDrawingPadding().semantics { testTagsAsResourceId = true }) { content() }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ABSConnectSheet(onClose: () -> Unit, content: @Composable () -> Unit) {
    ModalBottomSheet(onDismissRequest = onClose, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        shape = RoundedCornerShape(topStart = 40.dp, topEnd = 40.dp), dragHandle = null,
        containerColor = MaterialTheme.colorScheme.background, contentColor = MaterialTheme.colorScheme.onSurface) {
        Box(Modifier.fillMaxWidth().fillMaxHeight(.94f).semantics { testTagsAsResourceId = true }) { content() }
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
    ABSConnectSheet(onClose) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().testTag("abs.connect").padding(horizontal = 28.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row(Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 4.dp)) {
                OutlinedButton(onClick = onClose, enabled = !busy, colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.onSurface), border = BorderStroke(.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .2f))) { Text("Cancel", fontSize = 17.sp, fontWeight = FontWeight.Normal) }
            }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Eyebrow("AUDIOBOOKSHELF")
            Text("Bring your own shelf.", fontFamily = FontFamily.Serif, fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold)
            Text("Connect your Audiobookshelf server to browse and stream your library in Unpaged.", fontFamily = FontFamily.Serif, fontSize = 16.sp, lineHeight = 21.sp, letterSpacing = 0.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            ABSField("Server", server, "abs.connect.server", false, busy) { server = it; acknowledged = null; error = null }
            Column {
                Row(horizontalArrangement = Arrangement.spacedBy(22.dp)) {
                    listOf(false to "Sign in", true to "API key").forEach { (mode, title) ->
                        Column(Modifier.clickable { api = mode; error = null }) {
                            Text(title, Modifier.padding(vertical = 10.dp), fontSize = 15.sp, fontWeight = if (api == mode) FontWeight.SemiBold else FontWeight.Normal,
                                color = if (api == mode) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                            Box(Modifier.width(48.dp).height(2.dp).background(if (api == mode) MaterialTheme.colorScheme.onSurface else Color.Transparent))
                        }
                    }
                }
                HorizontalDivider(thickness = .5.dp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = .18f))
            }
            if (api) {
                ABSField("API key", key, "abs.connect.apiKey", true, busy) { key = it; error = null }
                Text("Create one in Audiobookshelf under Settings → API Keys.", fontSize = 12.sp)
            } else {
                ABSField("Username", username, "abs.connect.username", false, busy) { username = it; error = null }
                ABSField("Password", password, "abs.connect.password", true, busy) { password = it; error = null }
            }
            error?.let { Text(it, Modifier.testTag("abs.connect.error"), color = MaterialTheme.colorScheme.error, fontSize = 13.sp) }
            Button(onClick = { submit() }, enabled = !busy && server.isNotBlank() && (if (api) key.isNotBlank() else username.isNotBlank() && password.isNotEmpty()),
                modifier = Modifier.padding(top = 12.dp).fillMaxWidth().height(50.dp).testTag("abs.connect.submit"), shape = RoundedCornerShape(14.dp), colors = amberButtonColors()) {
                Text(if (busy) "Connecting…" else "Connect", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                Icon(Icons.Default.Lock, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("Your login stays on this phone, encrypted with Android Keystore.", fontSize = 12.sp, lineHeight = 16.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
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
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Eyebrow(label.uppercase())
        val placeholder = when (label) { "Server" -> "https://abs.example.com"; "Username" -> "Your Audiobookshelf username"; else -> label }
        Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surface,
            border = BorderStroke(.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .14f))) {
            BasicTextField(value, change, Modifier.fillMaxWidth().testTag(tag).padding(14.dp), singleLine = true, enabled = !busy,
                textStyle = LocalTextStyle.current.copy(fontSize = 17.sp, lineHeight = 20.sp, color = MaterialTheme.colorScheme.onSurface),
                visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
                decorationBox = { input -> Box { if (value.isEmpty()) Text(placeholder, fontSize = 17.sp, lineHeight = 20.sp, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .35f)); input() } })
        }
    }
}
@Composable private fun amberButtonColors() = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary, contentColor = Color.White,
    disabledContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = .45f), disabledContentColor = Color.White)
@Composable private fun ABSSection(title: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        HorizontalDivider(Modifier.weight(1f), thickness = .5.dp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = .18f))
    }
}
@Composable private fun Eyebrow(text: String) { Text(text, fontSize = 11.sp, letterSpacing = 1.2.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant) }

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
                TextButton(onClick = onClose, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)) { Icon(Icons.AutoMirrored.Filled.ArrowBack, null, Modifier.size(18.dp)); Text("Settings") }
                Text("Audiobookshelf", Modifier.weight(1f), fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                SheetDoneButton(onClick = onClose, filled = true)
            }
            Surface(shape = UnpagedTheme.settingsShape, shadowElevation = UnpagedTheme.cardShadow) {
                Column(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Eyebrow(if (summary == null) "NOT CONNECTED" else "CONNECTED")
                        Text(summary?.server?.let { java.net.URI(it).authority } ?: "Bring your own shelf.", fontFamily = FontFamily.Serif, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                        if (summary == null) Text("Connect your Audiobookshelf server to browse and stream your library in Unpaged.", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (summary != null) listOf("Server" to summary!!.server, "Signed in as" to (summary!!.username ?: "API key"), "Method" to if (summary!!.apiKey) "API key" else "Username & password").forEach { (label, value) ->
                        HorizontalDivider(thickness = .5.dp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = .12f))
                        Row(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(label, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(value, Modifier.weight(1f), fontSize = 14.sp, textAlign = TextAlign.End, maxLines = 1)
                        }
                    }
                }
            }
            if (summary != null) {
                Button(onClick = { preferences.setShelvesSource("audiobookshelf"); onClose(); onOpenShelves?.invoke() }, modifier = Modifier.fillMaxWidth().height(50.dp).testTag("abs.settings.openInShelves"), shape = RoundedCornerShape(14.dp), colors = amberButtonColors()) { Text("Open in Shelves", fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
                TextButton(onClick = { confirm = true }, modifier = Modifier.fillMaxWidth().testTag("abs.settings.disconnect")) { Text("Disconnect", color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.SemiBold) }
            } else Button(onClick = { connect = true }, modifier = Modifier.fillMaxWidth().height(50.dp), shape = RoundedCornerShape(14.dp), colors = amberButtonColors()) { Text("Connect a Server") }
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
private fun ABSBrowse(client: ABSClient, preferences: UnpagedPreferences, onChanged: () -> Unit, onViewLibrary: (String) -> Unit, onPlay: (LibraryBook) -> Unit, onDetailChanged: (Boolean) -> Unit) {
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
    LaunchedEffect(selectedId) { onDetailChanged(selectedId != null) }
    DisposableEffect(Unit) { onDispose { onDetailChanged(false) } }
    BackHandler(selectedId != null) { selectedId = null }
    if (selected != null) {
        ABSDetail(client, selected, onChanged, { id -> selectedId = null; onDetailChanged(false); onViewLibrary(id) }, onPlay) { selectedId = null }
        return
    }
    val filtered = items.filter { query.isBlank() || it.title.contains(query.trim(), true) || it.author.contains(query.trim(), true) }.sortedBy { it.title.lowercase() }
    LazyColumn(Modifier.fillMaxSize().testTag("abs.browse"), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Eyebrow("AUDIOBOOKSHELF · ${connection?.server?.let { java.net.URI(it).authority } ?: "Not connected"}")
                Box {
                    Row(Modifier.clickable { picker = true }.testTag("abs.libraryPicker"), verticalAlignment = Alignment.CenterVertically) {
                        Text(libraries.firstOrNull { it.id == selectedLibrary }?.name ?: libraries.firstOrNull()?.name ?: "Your library", fontFamily = FontFamily.Serif, fontSize = 28.sp, fontWeight = FontWeight.Bold)
                        Icon(Icons.Default.KeyboardArrowDown, null, Modifier.padding(start = 6.dp).size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    DropdownMenu(picker, { picker = false }) { libraries.forEach { library ->
                        DropdownMenuItem(text = { Text(library.name) }, onClick = { selectedLibrary = library.id; query = ""; picker = false })
                    } }
                }
            }
        }
        item {
            Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surface, border = BorderStroke(.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .14f))) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Default.Search, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    BasicTextField(query, { query = it }, Modifier.weight(1f).testTag("abs.search"), singleLine = true,
                        textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Serif, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface),
                        decorationBox = { input -> Box { if (query.isEmpty()) Text("Search titles & authors…", fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .35f)); input() } })
                }
            }
        }
        if (busy) item { CircularProgressIndicator(Modifier.testTag("abs.loading")) }
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
                item { ABSSection("Continue Listening") }
                item { LazyRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) { items(continuing, key = { it.id }) { book ->
                    Column(Modifier.width(128.dp).clickable { selectedId = book.id }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        ABSCover(client, book, Modifier.size(128.dp))
                        Box(Modifier.fillMaxWidth().height(3.dp).clip(CircleShape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = .1f))) {
                            Box(Modifier.fillMaxWidth((if (book.durationMs > 0) (progress[book.id]?.currentMs ?: 0).toFloat() / book.durationMs else 0f).coerceIn(0f, 1f)).fillMaxHeight().background(MaterialTheme.colorScheme.primary))
                        }
                        Text(book.title, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, letterSpacing = 0.sp, lineHeight = 18.sp, maxLines = 2)
                        Text(book.author, fontFamily = FontFamily.Serif, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                } } }
            }
            if (items.size > 12) {
                item { ABSSection("Recently Added") }
                item { LazyRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) { items(items.sortedByDescending { it.addedAt }.take(12), key = { it.id }) { book ->
                    Column(Modifier.width(128.dp).clickable { selectedId = book.id }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        ABSCover(client, book, Modifier.size(128.dp))
                        Text(book.title, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, letterSpacing = 0.sp, lineHeight = 18.sp, maxLines = 2)
                        Text(book.author, fontFamily = FontFamily.Serif, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                } } }
            }
        }
        item { ABSSection(if (query.isBlank()) "All Books" else "Search Results") }
        items(filtered.chunked(3), key = { row -> row.first().id }) { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                row.forEach { book ->
                    Column(Modifier.weight(1f).clickable { selectedId = book.id }.testTag("abs.book.${book.id}"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        ABSCover(client, book, Modifier.fillMaxWidth().aspectRatio(1f))
                        Text(book.title, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, letterSpacing = 0.sp, lineHeight = 18.sp, maxLines = 3)
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
internal fun ABSCover(client: ABSClient, item: ABSItem, modifier: Modifier, cornerRadius: Int = 8) {
    val connection by client.summary.collectAsStateWithLifecycle()
    var bitmap by remember(item.id, connection?.server) { mutableStateOf<android.graphics.Bitmap?>(null) }
    LaunchedEffect(item.id, item.hasCover, connection?.server) { if (item.hasCover) bitmap = withContext(Dispatchers.IO) { client.cover(item.id) } }
    val coverModifier = modifier.shadow(6.dp, RoundedCornerShape(cornerRadius.dp)).clip(RoundedCornerShape(cornerRadius.dp))
    if (bitmap == null) GeneratedBookCover(item.title, coverModifier, cornerRadius = cornerRadius)
    else Image(bitmap!!.asImageBitmap(), "Cover for ${item.title}", coverModifier, contentScale = ContentScale.Crop)
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
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, top = 10.dp, bottom = 10.dp)) {
            Surface(onClick = onBack, modifier = Modifier.size(44.dp).testTag("abs.back"), shape = CircleShape,
                color = MaterialTheme.colorScheme.surface, border = BorderStroke(.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .2f))) {
                Box(contentAlignment = Alignment.Center) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", Modifier.size(24.dp)) }
            }
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
        LazyColumn(Modifier.fillMaxSize().testTag("abs.detail"), contentPadding = PaddingValues(start = 24.dp, end = 24.dp, top = 20.dp, bottom = 120.dp), verticalArrangement = Arrangement.spacedBy(26.dp)) {
            item { Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { ABSCover(client, item, Modifier.size(230.dp).shadow(18.dp, RoundedCornerShape(12.dp)), cornerRadius = 12) } }
            item {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val minutes = item.durationMs / 60000
                    val duration = if (minutes == 0L) "under 1 min" else if (minutes < 60) "$minutes min" else "${minutes / 60} hr ${minutes % 60} min"
                    val chapters = item.chapters.size.takeIf { it > 0 } ?: item.tracks.size
                    Eyebrow("$duration · $chapters ${if (chapters == 1) "CHAPTER" else "CHAPTERS"}")
                    Text(item.title, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, fontSize = 28.sp, lineHeight = 33.sp, textAlign = TextAlign.Center)
                    if (item.subtitle.isNotBlank()) Text(item.subtitle, fontFamily = FontFamily.Serif, fontStyle = androidx.compose.ui.text.font.FontStyle.Italic, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(item.author, fontFamily = FontFamily.Serif, fontSize = 17.sp, letterSpacing = 0.sp)
                    if (item.narrator.isNotBlank()) Text("Read by ${item.narrator}", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(Modifier.clickable(enabled = existing != null) { existing?.let { onViewLibrary(it.id) } }.testTag("abs.viewLibrary"),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (existing != null) {
                            Icon(Icons.Default.Check, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text("In your Library", Modifier.testTag("abs.added"), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            if (current > 0 || existing?.isFinished == true) Text("·", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (existing?.isFinished == true || existing == null && progress?.finished == true) Text("Finished", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        else if (current > 0 && item.durationMs > 0) Text("${(100 * current / item.durationMs).coerceIn(1, 99)}% listened", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            item {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(onClick = { add(true) }, enabled = !busy, modifier = Modifier.fillMaxWidth().height(50.dp).testTag("abs.play"), shape = RoundedCornerShape(14.dp),
                        colors = amberButtonColors()) {
                        Icon(Icons.Default.PlayArrow, null, Modifier.size(20.dp)); Spacer(Modifier.width(10.dp))
                        Text(if (busy) "Working…" else if (current > 0 && existing?.isFinished != true) "Resume" else "Play", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    }
                    if (existing == null) OutlinedButton(onClick = { add(false) }, enabled = !busy, modifier = Modifier.fillMaxWidth().height(50.dp).testTag("abs.add"), shape = RoundedCornerShape(14.dp), border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .22f))) { Text("Add to Library", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface) }
                    Text("Streams from your server. Nothing is downloaded.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    error?.let { Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center) }
                }
            }
            if (description.isNotEmpty()) item {
                Column {
                ABSSection("About this book"); Spacer(Modifier.height(12.dp))
                Text(description, fontFamily = FontFamily.Serif, fontSize = 17.sp, letterSpacing = 0.sp, lineHeight = 23.sp, maxLines = if (expanded) Int.MAX_VALUE else 5)
                if (description.length > 280) TextButton(onClick = { expanded = !expanded }) { Text(if (expanded) "Show less" else "Show more") }
                }
            }
        }
    }
}
