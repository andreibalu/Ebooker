package dev.unpaged.android.moments

import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import kotlinx.coroutines.launch
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.unpaged.android.library.LibraryMoment
import dev.unpaged.android.library.trackDuration

@Composable
fun MomentList(bookId: String, moments: List<LibraryMoment>, expanded: Boolean, expand: () -> Unit,
               play: (LibraryMoment) -> Unit, save: (LibraryMoment) -> Unit, delete: (String) -> Unit) {
    var editing by rememberSaveable(bookId, stateSaver = MomentSaver) { mutableStateOf<LibraryMoment?>(null) }
    var filters by rememberSaveable(bookId, stateSaver = MomentFiltersSaver) { mutableStateOf(MomentFilters()) }
    var filterSheet by rememberSaveable(bookId) { mutableStateOf(false) }
    val filtered = filters.apply(moments)
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 18.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f).clickable(onClick = expand).testTag("book.moments"), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Bookmark, null, Modifier.size(12.dp)); Spacer(Modifier.width(8.dp))
            Text("${filtered.size} ${if (filtered.size == 1) "moment" else "moments"}${if (filters.active) " · filtered" else ""}", Modifier.weight(1f), fontSize = 15.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium)
            if (moments.isNotEmpty() && filtered.isNotEmpty()) Icon(if (expanded) Icons.Default.KeyboardArrowDown else Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurface.copy(alpha = .55f))
        }
        if ((expanded || filtered.isEmpty()) && moments.any { it.categories.isNotEmpty() || it.mood != null || it.characters.isNotEmpty() }) {
            TextButton(onClick = { filterSheet = true }, modifier = Modifier.testTag("moment.filter")) { Icon(Icons.Default.FilterList, null, Modifier.size(16.dp)); Text("Filter", fontSize = 12.sp) }
        }
    }
    if (expanded || filtered.isEmpty()) Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (filtered.isEmpty()) Text(if (filters.active) "No moments match your filters" else "Tap the bookmark in the player to save a moment", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (filters.active) TextButton(onClick = { filters = MomentFilters() }) { Text("Clear Filters") }
        filtered.forEach { moment ->
            var menu by remember(moment.id) { mutableStateOf(false) }
            SwipeMoment(moment, { delete(moment.id) }) {
                Surface(shape = RoundedCornerShape(16.dp), shadowElevation = 2.dp) {
                    Row(Modifier.fillMaxWidth().combinedClickable(onClick = { editing = moment }, onLongClick = { menu = true })
                        .testTag("moment.row.${moment.id}").padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        IconButton(onClick = { save(moment.copy(isPinned = !moment.isPinned)) }, modifier = Modifier.size(24.dp)) { Icon(if (moment.isPinned) Icons.Default.PushPin else Icons.Default.Flag, if (moment.isPinned) "Unpin moment" else "Pin moment", Modifier.size(16.dp)) }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(moment.label, fontSize = 15.sp)
                            Text(trackDuration(moment.timeMs), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            if (moment.notes.isNotEmpty()) Text(moment.notes, fontSize = 12.sp, maxLines = 2, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Box {
                            IconButton(onClick = { editing = moment }, modifier = Modifier.size(24.dp).testTag("moment.edit.${moment.id}")) { Icon(Icons.Default.Edit, "Edit moment", Modifier.size(16.dp)) }
                            DropdownMenu(menu, { menu = false }, modifier = Modifier.semantics { testTagsAsResourceId = true }) { DropdownMenuItem(text = { Text("Delete") }, onClick = { menu = false; delete(moment.id) }) }
                        }
                        IconButton(onClick = { play(moment) }, modifier = Modifier.size(36.dp)) { Icon(Icons.Default.PlayCircleOutline, "Play from this moment", Modifier.size(20.dp)) }
                    }
                }
            }
        }
    }
    editing?.let { moment -> MomentEditSheet(moment, editing = true, onSave = { save(it); editing = null }, onCancel = { editing = null }) }
    if (filterSheet) MomentFilterSheet(moments, filters, { filters = it }) { filterSheet = false }
}

@Composable
private fun SwipeMoment(moment: LibraryMoment, delete: () -> Unit, content: @Composable () -> Unit) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val scope = rememberCoroutineScope()
    var offset by remember(moment.id) { mutableFloatStateOf(0f) }
    var dragging by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    val animated by androidx.compose.animation.core.animateFloatAsState(offset,
        animationSpec = if (dragging) androidx.compose.animation.core.snap() else androidx.compose.animation.core.spring(dampingRatio = .88f), label = "Moment swipe")
    BoxWithConstraints(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))) {
        val width = with(density) { maxWidth.toPx() }
        val reveal = with(density) { 82.dp.toPx() }
        Surface(color = MaterialTheme.colorScheme.error, modifier = Modifier.matchParentSize()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.CenterEnd) {
                TextButton(onClick = delete, modifier = Modifier.width(82.dp).fillMaxHeight()) {
                    Text("Delete", color = MaterialTheme.colorScheme.onError)
                }
            }
        }
        Box(Modifier.offset { androidx.compose.ui.unit.IntOffset(animated.toInt(), 0) }
            .pointerInput(moment.id, width) {
                detectHorizontalDragGestures(
                    onDragStart = { dragging = true },
                    onHorizontalDrag = { change, distance ->
                        if (!deleting) { change.consume(); offset = (offset + distance).coerceIn(-width * 1.02f, 0f) }
                    },
                    onDragCancel = { dragging = false; offset = 0f },
                    onDragEnd = {
                        dragging = false
                        if (offset <= -kotlin.math.max(width * .72f, reveal + with(density) { 120.dp.toPx() })) {
                            deleting = true; offset = -width - with(density) { 24.dp.toPx() }
                            scope.launch { kotlinx.coroutines.delay(240); delete() }
                        } else offset = if (offset <= -reveal * .55f) -reveal else 0f
                    })
            }) { content() }
    }
}
