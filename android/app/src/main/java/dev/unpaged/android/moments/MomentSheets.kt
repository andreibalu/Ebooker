package dev.unpaged.android.moments

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.unpaged.android.library.LibraryMoment
import org.json.JSONArray
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MomentEditSheet(moment: LibraryMoment, editing: Boolean = false, aiGenerated: Boolean = false, warning: String? = null, onSave: (LibraryMoment) -> Unit, onCancel: () -> Unit) {
    var name by rememberSaveable(moment.id) { mutableStateOf(moment.label) }
    var note by rememberSaveable(moment.id) { mutableStateOf(moment.notes) }
    var quote by rememberSaveable(moment.id) { mutableStateOf(moment.quoteLine.orEmpty()) }
    var categories by rememberSaveable(moment.id) { mutableStateOf<List<String>>(ArrayList(moment.categories.map { it.name })) }
    var characters by rememberSaveable(moment.id) { mutableStateOf<List<String>>(ArrayList(moment.characters)) }
    var mood by rememberSaveable(moment.id) { mutableStateOf(moment.mood) }
    var character by rememberSaveable { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onCancel, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = MaterialTheme.colorScheme.background,
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("moment.editor")) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onCancel) { Text("Cancel") }
            Text(if (editing) "Edit Moment" else "Name this Moment", Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            TextButton(enabled = name.trim().isNotEmpty(), modifier = Modifier.testTag("moment.done"), onClick = {
                onSave(moment.copy(label = name.trim(), notes = note, quoteLine = quote.takeIf { it.isNotEmpty() },
                    categoriesJson = JSONArray(categories).toString(), charactersJson = JSONArray(characters).toString(), mood = mood))
            }) { Text("Done") }
        }
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).testTag("moment.scroll").navigationBarsPadding().padding(20.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            warning?.let { Text(it, Modifier.testTag("moment.warning"), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            MomentSection("Name") { TextField(name, { name = it }, Modifier.fillMaxWidth().testTag("moment.name"), colors = momentFieldColors(), placeholder = { Text("Moment name") }, singleLine = true) }
            MomentSection("Note", badge = if (aiGenerated) "AI generated" else null) { TextField(note, { note = it }, Modifier.fillMaxWidth().testTag("moment.note"), colors = momentFieldColors(), placeholder = { Text("Add a note (optional)") }, minLines = 4, maxLines = 8) }
            MomentSection("Quote") { TextField(quote, { quote = it }, Modifier.fillMaxWidth().testTag("moment.quote"), colors = momentFieldColors(), placeholder = { Text(if (aiGenerated) "On-device AI couldn't extract a quote from this sequence" else "Add a quote (optional)") }, minLines = 2, maxLines = 6, textStyle = LocalTextStyle.current.copy(fontStyle = FontStyle.Italic, fontSize = 14.sp)) }
            MomentSection("Categories") {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    categories.forEach { key -> MomentChip(MomentCategory.valueOf(key).title) { categories = ArrayList(categories - key) } }
                    TagMenu(if (categories.isEmpty()) "Add category" else "Add", MomentCategory.entries.filter { it.name !in categories }.map { it.name to it.title }, "moment.addCategory") { categories = ArrayList(categories + it) }
                }
            }
            MomentSection("Mood") {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    mood?.let { key -> MomentMood.entries.find { it.name == key }?.let { MomentChip(it.title) { mood = null } } }
                    TagMenu(if (mood == null) "Add mood" else "Change", MomentMood.entries.map { it.name to it.title }, "moment.addMood") { mood = it }
                }
            }
            MomentSection("Characters") {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { characters.forEach { key -> MomentChip(key) { characters = ArrayList(characters - key) } } }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TextField(character, { character = it }, Modifier.weight(1f).testTag("moment.character"), colors = momentFieldColors(), placeholder = { Text("Add character") }, singleLine = true)
                    TextButton(onClick = { characters = ArrayList(addCharacter(characters, character)); character = "" }, enabled = addCharacter(characters, character) != characters, modifier = Modifier.testTag("moment.addCharacter")) { Text("+") }
                }
            }
        }
    }
}

@Composable
private fun MomentSection(title: String, badge: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth()) {
            Text(title.uppercase(Locale.ROOT), Modifier.weight(1f), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            badge?.let { Text(it, Modifier.testTag("moment.aiGenerated"), fontSize = 10.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        Surface(shape = RoundedCornerShape(12.dp)) { Column(Modifier.fillMaxWidth().padding(8.dp), content = content) }
    }
}
@Composable
fun MomentChip(title: String, remove: () -> Unit) { InputChip(selected = false, onClick = remove, label = { Text(title, fontSize = 12.sp) }, trailingIcon = { Text("×") }) }
@Composable
private fun TagMenu(title: String, options: List<Pair<String, String>>, tag: String, select: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        AssistChip(onClick = { open = true }, label = { Text("+ $title", fontSize = 12.sp) }, modifier = Modifier.testTag(tag))
        DropdownMenu(open, { open = false }) { options.forEach { (key, text) -> DropdownMenuItem(text = { Text(text) }, onClick = { select(key); open = false }) } }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MomentFilterSheet(moments: List<LibraryMoment>, filters: MomentFilters, change: (MomentFilters) -> Unit, dismiss: () -> Unit) {
    // Fully expanded so the trailing Clear All row is reachable above the navigation bar.
    ModalBottomSheet(onDismissRequest = dismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = MaterialTheme.colorScheme.background,
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("moment.filters")) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Filter Moments", Modifier.weight(1f)); TextButton(onClick = dismiss) { Text("Done") }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).testTag("moment.filterScroll").navigationBarsPadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            val categories = moments.flatMap { it.categories }.distinct().sortedBy { it.name }
            if (categories.isNotEmpty()) MomentSection("Categories") { categories.forEach { option -> FilterOption(option.title, option.name in filters.categories) { change(filters.copy(categories = filters.categories.toggle(option.name))) } } }
            val characters = moments.flatMap { it.characters }.distinctBy { it.lowercase(Locale.ROOT) }.sorted()
            if (characters.isNotEmpty()) MomentSection("Characters") { characters.forEach { name -> val key = name.lowercase(Locale.ROOT); FilterOption(name, key in filters.characters) { change(filters.copy(characters = filters.characters.toggle(key))) } } }
            val moods = moments.mapNotNull { it.moodValue }.distinct().sortedBy { it.name }
            if (moods.isNotEmpty()) MomentSection("Moods") { moods.forEach { option -> FilterOption(option.title, option.name in filters.moods) { change(filters.copy(moods = filters.moods.toggle(option.name))) } } }
            if (filters.active) TextButton(onClick = { change(MomentFilters()) }, modifier = Modifier.testTag("moment.clearFilters")) { Text("Clear All", color = MaterialTheme.colorScheme.error) }
        }
    }
}
private fun Set<String>.toggle(key: String) = if (key in this) this - key else this + key
@Composable
private fun FilterOption(title: String, selected: Boolean, action: () -> Unit) {
    TextButton(onClick = action, modifier = Modifier.fillMaxWidth()) { Text(title, Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Start); if (selected) Text("✓") }
}

@Composable
private fun momentFieldColors() = TextFieldDefaults.colors(
    focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
    focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent)
