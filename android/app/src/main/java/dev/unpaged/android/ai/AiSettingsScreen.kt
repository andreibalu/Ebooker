package dev.unpaged.android.ai

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.unpaged.android.UnpagedPreferences
import dev.unpaged.android.UnpagedTheme
import dev.unpaged.android.preferenceRevision
import kotlinx.coroutines.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AiSettingsScreen(ai: AiCoordinator, preferences: UnpagedPreferences, dismiss: () -> Unit) {
    val status by ai.status.collectAsStateWithLifecycle()
    val model by ai.models.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val uri = LocalUriHandler.current
    var consent by rememberSaveable { mutableStateOf(false) }
    var delete by rememberSaveable { mutableStateOf(false) }
    var systemBytes by remember { mutableLongStateOf(0) }
    var systemJob by remember { mutableStateOf<Job?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    preferenceRevision(preferences)
    LaunchedEffect(Unit) { while (true) { ai.refresh(); delay(2000) } }
    ModalBottomSheet(onDismissRequest = dismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = MaterialTheme.colorScheme.background, modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("ai.settings")) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).testTag("ai.scroll").padding(20.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row { Text("On-device AI", Modifier.weight(1f), fontSize = 26.sp, fontWeight = FontWeight.Bold); TextButton(onClick = dismiss, modifier = Modifier.testTag("ai.done")) { Text("Done") } }
            Text("Smart moments and recaps run on your phone. Audio, transcripts and generated text stay on this device.", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Surface(shape = UnpagedTheme.settingsShape) { Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Gemini Nano", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Text(when (status) {
                    GeneratorStatus.AVAILABLE -> "Ready · System model"
                    GeneratorStatus.DOWNLOADABLE -> "System model download required"
                    GeneratorStatus.DOWNLOADING -> "Downloading system model…"
                    GeneratorStatus.UNAVAILABLE -> "On-device AI isn't supported on this phone."
                }, Modifier.testTag("ai.systemStatus"), fontSize = 13.sp)
                if (status == GeneratorStatus.DOWNLOADABLE || status == GeneratorStatus.DOWNLOADING) {
                    if (systemJob?.isActive == true || status == GeneratorStatus.DOWNLOADING) {
                        LinearProgressIndicator(Modifier.fillMaxWidth()); Text("$systemBytes bytes downloaded")
                    }
                    if (systemJob?.isActive != true) TextButton(onClick = { systemJob = scope.launch {
                        try { ai.generator.download { systemBytes = it }; ai.refresh() }
                        catch (e: CancellationException) { throw e } catch (_: Exception) { error = "Couldn't download the system model. Please try again." }
                    } }, modifier = Modifier.testTag("ai.systemDownload")) { Text("Download system model") }
                }
            } }
            // Unsupported phones cannot use the model, so do not offer its 60 MB download.
            if (status != GeneratorStatus.UNAVAILABLE) Surface(shape = UnpagedTheme.settingsShape) { Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Whisper multilingual base", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Text("Speech model · 59.7 MB · MIT license", fontSize = 13.sp)
                TextButton(onClick = { uri.openUri(SpeechModelStore.LICENSE) }, modifier = Modifier.testTag("ai.license")) { Text("View license") }
                Text(if (model.installed) "Installed · Verified" else "Download once to transcribe local audiobook passages.", Modifier.testTag("ai.modelStatus"), fontSize = 13.sp)
                if (model.downloading) {
                    LinearProgressIndicator(progress = { model.bytes.toFloat() / SpeechModelStore.SIZE }, modifier = Modifier.fillMaxWidth().testTag("ai.progress"))
                    Text("${model.bytes / 1_000_000} / 59.7 MB")
                    TextButton(onClick = ai.models::cancel, modifier = Modifier.testTag("ai.cancel")) { Text("Cancel") }
                } else if (model.installed) TextButton(onClick = { delete = true }, modifier = Modifier.testTag("ai.delete")) { Text("Delete speech model", color = MaterialTheme.colorScheme.error) }
                else Button(onClick = { consent = true }, modifier = Modifier.testTag("ai.download"), shape = RoundedCornerShape(16.dp)) { Text(if (model.error == null) "Download speech model" else "Retry download") }
                model.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            } }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            if (status != GeneratorStatus.UNAVAILABLE) Surface(shape = UnpagedTheme.settingsShape) { Column(Modifier.padding(16.dp)) {
                val ready = status == GeneratorStatus.AVAILABLE && model.installed
                AiToggle("Use local AI features", "On-device AI for local audiobook passages", "useLocalAIFeatures", preferences, ready)
                if (preferences.text("useLocalAIFeatures", "false") == "true") {
                AiToggle("Smart moment naming", "Suggest names for saved moments based on the audio", "useSmartMomentNaming", preferences, ready)
                AiToggle("Smart summary", "Summarize where you left off on the book detail screen", "useSmartSummary", preferences, ready)
                if (preferences.text("useSmartSummary", "false") == "true") AiToggle("Short progress headline", "Replace Your progress with a 3–4 word summary", "shortenSummary", preferences, ready)
                }
            } }
        }
    }
    if (consent) AlertDialog(onDismissRequest = { consent = false }, title = { Text("Download speech model?") },
        text = { Text("Whisper multilingual base uses 59.7 MB of storage and is licensed under MIT. At least 77 MB of free space is required. Only the model file is downloaded; your audio and transcripts stay on your phone.") },
        modifier = Modifier.semantics { testTagsAsResourceId = true },
        confirmButton = { TextButton(onClick = { consent = false; ai.models.downloadWithConsent() }, modifier = Modifier.testTag("ai.consent")) { Text("Download") } },
        dismissButton = { TextButton(onClick = { consent = false }) { Text("Cancel") } })
    if (delete) AlertDialog(onDismissRequest = { delete = false }, title = { Text("Delete speech model?") }, text = { Text("Smart moments and recaps will be unavailable until you download it again. Your saved moments stay in your library.") },
        modifier = Modifier.semantics { testTagsAsResourceId = true },
        confirmButton = { TextButton(onClick = { delete = false; scope.launch { ai.models.delete() } }, modifier = Modifier.testTag("ai.confirmDelete")) { Text("Delete") } },
        dismissButton = { TextButton(onClick = { delete = false }) { Text("Cancel") } })
}
@Composable
private fun AiToggle(title: String, description: String, key: String, preferences: UnpagedPreferences, enabled: Boolean) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) { Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium); Text(description, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        Switch(preferences.text(key, "false") == "true", { preferences.setAiPreference(key, it) }, enabled = enabled, modifier = Modifier.testTag("ai.$key"))
    }
}
