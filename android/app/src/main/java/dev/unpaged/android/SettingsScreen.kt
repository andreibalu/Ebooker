package dev.unpaged.android

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.selectable
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private data class ListeningPreference(val title: String, val caption: String, val key: String,
    val default: Int, val options: List<Pair<Int, String>>)
private val listeningPreferences = listOf(
    ListeningPreference("On Resume", "Rewind a bit when you press play after a break", "resumeBacktrackSeconds", 60,
        listOf(0 to "Resume exactly", 15 to "Resume 15 seconds earlier", 30 to "Resume 30 seconds earlier", 60 to "Resume 1 minute earlier")),
    ListeningPreference("Save Moment Offset", "How far back the timestamp is set when you save a moment", "momentBacktrackSeconds", 0,
        listOf(0 to "Save at current position", 15 to "15 seconds earlier", 30 to "30 seconds earlier", 60 to "1 minute earlier", 120 to "2 minutes earlier")),
    ListeningPreference("Skip Backward", "How far the back button jumps", "skipBackSeconds", 30,
        listOf(15 to "15 seconds", 30 to "30 seconds", 45 to "45 seconds")),
    ListeningPreference("Skip Forward", "How far the forward button jumps", "skipForwardSeconds", 30,
        listOf(15 to "15 seconds", 30 to "30 seconds", 45 to "45 seconds")),
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(preferences: UnpagedPreferences, onOpenShelves: (() -> Unit)? = null, onDone: () -> Unit) {
    preferenceRevision(preferences)
    var expanded by rememberSaveable { mutableStateOf<String?>(null) }
    var absSettings by rememberSaveable { mutableStateOf(false) }
    val absClient = (androidx.compose.ui.platform.LocalContext.current.applicationContext as UnpagedApplication).abs
    val uri = LocalUriHandler.current
    ModalBottomSheet(onDismissRequest = onDone, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false),
        containerColor = MaterialTheme.colorScheme.background, contentColor = MaterialTheme.colorScheme.onSurface,
        shape = RoundedCornerShape(topStart = 40.dp, topEnd = 40.dp),
        dragHandle = { Box(Modifier.padding(top = 6.dp, bottom = 12.dp).width(58.dp).height(3.dp).background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .5f), CircleShape)) }) {
        Column(Modifier.fillMaxHeight(.94f).semantics { testTagsAsResourceId = true }) {
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Settings", Modifier.weight(1f), fontSize = 26.sp, lineHeight = 31.sp, fontWeight = FontWeight.Bold)
                Surface(onClick = onDone, shape = CircleShape, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .4f)) {
                    Text("Done", Modifier.padding(horizontal = 16.dp, vertical = 7.dp), fontSize = 13.sp, lineHeight = 16.sp,
                        fontWeight = FontWeight.SemiBold, color = androidx.compose.ui.graphics.Color.White)
                }
            }
            Column(Modifier.verticalScroll(rememberScrollState()).testTag("settings.scroll").padding(horizontal = 16.dp)
                .padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                Column {
                    SectionHeader("SOURCES", "Your own shelf.")
                    val summary by absClient.summary.collectAsStateWithLifecycle()
                    Surface(shape = UnpagedTheme.settingsShape, shadowElevation = UnpagedTheme.cardShadow) {
                        Row(Modifier.fillMaxWidth().clickable { absSettings = true }.testTag("settings.audiobookshelf").padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surfaceVariant) { Icon(Icons.AutoMirrored.Filled.LibraryBooks, null, Modifier.padding(12.dp).size(22.dp)) }
                            Column(Modifier.weight(1f)) {
                                Text("Audiobookshelf Server", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                                Text(summary?.let { "${it.username ?: "API key"} · ${java.net.URI(it.server).authority}" } ?: "Connect your server", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                Column {
                    SectionHeader("PLAYBACK", "Listening preferences.")
                    Surface(shape = UnpagedTheme.settingsShape, shadowElevation = UnpagedTheme.cardShadow) {
                        Column {
                            Column(Modifier.padding(horizontal = 16.dp, vertical = 13.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                SettingLabel("Open To", "The library that greets you when you launch Unpaged")
                                Segments(listOf("Shelves", "Library"), if (preferences.shelvesFirst()) "Shelves" else "Library", "home") {
                                    preferences.setShelvesFirst(it == "Shelves")
                                }
                            }
                            Hairline()
                            listeningPreferences.forEachIndexed { index, option ->
                                val selected = preferences.seconds(option.key, option.default)
                                Column {
                                    Row(Modifier.fillMaxWidth().clickable { expanded = if (expanded == option.key) null else option.key }
                                        .testTag("settings.picker.${option.title}").padding(horizontal = 16.dp, vertical = 13.dp),
                                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                        Column(Modifier.weight(1.5f)) { SettingLabel(option.title, option.caption) }
                                        Text(option.options.first { it.first == selected }.second, Modifier.weight(1f), fontSize = 14.sp, lineHeight = 17.sp,
                                            textAlign = TextAlign.End, color = if (expanded == option.key) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                                        Icon(if (expanded == option.key) Icons.Default.KeyboardArrowDown else Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                            null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    if (expanded == option.key) Column(Modifier.padding(horizontal = 10.dp).padding(bottom = 10.dp),
                                        verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        option.options.forEach { (value, label) ->
                                            Row(Modifier.fillMaxWidth().background(if (value == selected) MaterialTheme.colorScheme.primary.copy(alpha = .12f)
                                                else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = .5f), RoundedCornerShape(10.dp))
                                                .clickable { preferences.setSeconds(option.key, value); expanded = null }
                                                .testTag("settings.option.${option.key}.$value").padding(horizontal = 12.dp, vertical = 9.dp)) {
                                                Text(label, Modifier.weight(1f), fontSize = 14.sp)
                                                if (value == selected) Icon(Icons.Default.Check, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                                            }
                                        }
                                    }
                                    if (index < listeningPreferences.lastIndex) Hairline()
                                }
                            }
                        }
                    }
                }
                Column {
                    SectionHeader("APP", "Appearance & tour.")
                    Surface(shape = UnpagedTheme.settingsShape, shadowElevation = UnpagedTheme.cardShadow) {
                        Column(Modifier.padding(horizontal = 16.dp, vertical = 13.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            TextButton(onClick = { onDone(); preferences.setOnboardingComplete(false) }, modifier = Modifier.testTag("settings.resetOnboarding")) { Text("Reset Onboarding", color = MaterialTheme.colorScheme.onSurface) }
                            SettingLabel("Appearance", "Follow your phone, or always use light or dark")
                            Segments(listOf("System", "Light", "Dark"), preferences.text("appAppearance", "system").replaceFirstChar { it.uppercase() }, "appearance") {
                                preferences.setText("appAppearance", it.lowercase())
                            }
                        }
                    }
                }
                // iOS Support contains only the excluded coffee purchase. Keep its non-payment legal rows.
                Column {
                    SectionHeader("ABOUT", "The fine print.")
                    Surface(shape = UnpagedTheme.settingsShape, shadowElevation = UnpagedTheme.cardShadow) {
                        Column {
                            LegalRow("Privacy Policy") { uri.openUri("https://gist.github.com/andreibalu/aca2af2e2176cc453175f708b2481262") }
                            Hairline()
                            LegalRow("Terms of Use") { uri.openUri("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") }
                        }
                    }
                }
            }
        }
    }
    if (absSettings) dev.unpaged.android.abs.ABSServerSettings(absClient, preferences, onOpenShelves = { absSettings = false; onDone(); onOpenShelves?.invoke() }) { absSettings = false }
}

@Composable
private fun SectionHeader(eyebrow: String, headline: String) {
    Column(Modifier.padding(start = 4.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(eyebrow, fontSize = 10.5.sp, lineHeight = 13.sp, letterSpacing = 1.5.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(headline, fontSize = 20.sp, lineHeight = 24.sp, fontWeight = FontWeight.Bold, letterSpacing = (-.2).sp)
    }
}

@Composable
private fun SettingLabel(title: String, caption: String) {
    Text(title, fontSize = 15.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium)
    Text(caption, fontSize = 11.sp, lineHeight = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun Hairline() { HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = .08f), thickness = .5.dp) }

@Composable
private fun Segments(labels: List<String>, selected: String, prefix: String, onSelect: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant, CircleShape).padding(4.dp)) {
        labels.forEach { label ->
            Row(Modifier.weight(1f).background(if (selected == label) MaterialTheme.colorScheme.primary else androidx.compose.ui.graphics.Color.Transparent, CircleShape)
                .selectable(selected = selected == label, role = Role.RadioButton, onClick = { onSelect(label) }).testTag("settings.$prefix.$label").padding(vertical = 10.dp),
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                val icon = when (label) { "System" -> Icons.Default.Contrast; "Light" -> Icons.Default.LightMode; "Dark" -> Icons.Default.DarkMode
                    "Shelves" -> Icons.AutoMirrored.Filled.LibraryBooks; else -> Icons.Default.Layers }
                val color = if (selected == label) androidx.compose.ui.graphics.Color.White else MaterialTheme.colorScheme.onSurfaceVariant
                Icon(icon, null, Modifier.size(16.dp), tint = color)
                Spacer(Modifier.width(6.dp))
                Text(label, fontSize = 14.sp, lineHeight = 17.sp, fontWeight = FontWeight.SemiBold, color = color)
            }
        }
    }
}

@Composable
private fun LegalRow(title: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).testTag("settings.legal.$title").padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), fontSize = 15.sp)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
