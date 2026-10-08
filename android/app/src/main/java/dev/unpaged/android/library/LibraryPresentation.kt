package dev.unpaged.android.library

import androidx.core.graphics.get
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.platform.testTag
import dev.unpaged.android.UnpagedTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.unpaged.android.R
import java.util.Locale

object CoverPalette {
    private val fields = listOf(0xFFD96C2F, 0xFFD9A13B, 0xFF7A8C2E, 0xFFC24E1F,
        0xFF1F8A7A, 0xFFB83A5E, 0xFF2456B3, 0xFF6B3E1E)
    fun index(title: String): Int {
        var hash = 2_166_136_261L
        for (byte in title.lowercase(Locale.ROOT).trim().toByteArray(Charsets.UTF_8))
            hash = ((hash xor (byte.toInt() and 255).toLong()) * 16_777_619L) and 0xffffffffL
        return if (title.isBlank()) 0 else (hash % fields.size).toInt()
    }
    fun background(title: String) = Color(fields[index(title)])
    fun foreground(title: String) = Color(if (index(title) == 1) 0xFF3D2C12 else 0xFFFBF3E4)
}

@Composable
internal fun GeneratedBookCover(title: String, modifier: Modifier = Modifier, cornerRadius: Int = 16) {
    val foreground = CoverPalette.foreground(title)
    BoxWithConstraints(modifier.clip(RoundedCornerShape(cornerRadius.dp)).background(CoverPalette.background(title))
        .semantics { contentDescription = "Cover for $title" }) {
        val side = minOf(maxWidth, maxHeight)
        val inset = side * 0.1f
        Text(title, Modifier.padding(horizontal = inset).padding(top = side * 0.155f),
            fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium,
            fontSize = (side.value * 0.121f).sp, lineHeight = (side.value * 0.142f).sp,
            color = foreground, maxLines = 4, overflow = TextOverflow.Ellipsis)
        if (side >= 60.dp) Column(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(horizontal = inset)
            .padding(bottom = side * 0.05f)) {
            Canvas(Modifier.size(side * 0.095f)) {
                val w = size.width
                val h = size.height
                val page = Path().apply {
                    moveTo(w * .12f, h * .05f); lineTo(w * .75f, 0f)
                    lineTo(w * .75f, h * .85f); lineTo(w * .12f, h); close()
                }
                drawPath(page, foreground, style = Stroke(w * .1f))
                for (line in 1..3) drawLine(foreground,
                    androidx.compose.ui.geometry.Offset(w * .28f, h * (.16f + .17f * line)),
                    androidx.compose.ui.geometry.Offset(w * .6f, h * (.13f + .17f * line)), w * .06f)
                drawLine(foreground, androidx.compose.ui.geometry.Offset(w * .88f, h * .08f),
                    androidx.compose.ui.geometry.Offset(w * .88f, h * .9f), w * .07f)
            }
            Spacer(Modifier.height(side * .047f))
            HorizontalDivider(color = foreground.copy(alpha = .55f), thickness = 1.dp)
            Text("UNPAGED", Modifier.padding(top = side * .026f), color = foreground.copy(alpha = .78f),
                fontFamily = FontFamily.Serif, fontSize = (side.value * .0395f).sp,
                letterSpacing = (side.value * .0118f).sp, lineHeight = (side.value * .06f).sp)
        }
    }
}

@Composable
internal fun LibraryBookCover(book: LibraryBook, modifier: Modifier, cornerRadius: Int = 16, onCoverColor: (Color) -> Unit = {}) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var bitmap by remember(book.id) { mutableStateOf<android.graphics.Bitmap?>(null) }
    LaunchedEffect(book.id, book.coverRevision) {
        bitmap = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            android.graphics.BitmapFactory.decodeFile(java.io.File(context.filesDir, "audiobooks/${book.id}/cover.png").absolutePath)
        }
        bitmap?.let { onCoverColor(Color(it[it.width / 2, it.height / 2])) }
    }
    if (bitmap == null) GeneratedBookCover(book.title, modifier, cornerRadius)
    else androidx.compose.foundation.Image(bitmap!!.asImageBitmap(), "Cover for ${book.title}", modifier.clip(RoundedCornerShape(cornerRadius.dp)), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
}

@Composable
internal fun LibraryHeader(count: Int, canImport: Boolean, onImport: () -> Unit, onSettings: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Surface(Modifier.size(48.dp), shape = CircleShape, color = MaterialTheme.colorScheme.onSurface) {
            Box(contentAlignment = Alignment.Center) {
                Text(count.toString(), fontSize = 17.sp, lineHeight = 20.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.background)
            }
        }
        Text("My Library", Modifier.weight(1f), fontSize = 22.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold)
        HeaderButton("Settings", onSettings) { Icon(Icons.Default.Tune, null, tint = MaterialTheme.colorScheme.onSurface) }
        HeaderButton("Import Audiobook", onImport, canImport) { Icon(Icons.Default.Add, null, tint = MaterialTheme.colorScheme.onSurface) }
    }
}

@Composable
private fun HeaderButton(description: String, onClick: () -> Unit, enabled: Boolean = true, content: @Composable () -> Unit) {
    Surface(shape = RoundedCornerShape(10.dp), shadowElevation = UnpagedTheme.cardShadow) {
        IconButton(onClick, enabled = enabled, modifier = Modifier.size(36.dp).semantics { contentDescription = description }) { content() }
    }
}

@Composable
internal fun LibraryBookCard(book: LibraryBook, onFavorite: () -> Unit, onRemove: () -> Unit, playing: Boolean = false, onResume: () -> Unit = {}, onRename: () -> Unit = {}, onOpen: () -> Unit) {
    var menu by rememberSaveable { mutableStateOf(false) }
    var coverColor by remember(book.id) { mutableStateOf(CoverPalette.background(book.title)) }
    Surface(Modifier.fillMaxWidth().shadow(12.dp, UnpagedTheme.cardShape, ambientColor = Color.Black.copy(alpha = .12f), spotColor = Color.Black.copy(alpha = .12f)).combinedClickable(onClick = onOpen, onLongClick = { menu = true }).testTag("book.card.${book.id}"),
        shape = UnpagedTheme.cardShape, shadowElevation = 0.dp) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Box {
                LibraryBookCover(book, Modifier.fillMaxWidth().height(185.dp), onCoverColor = { coverColor = it })
                if (playing || book.lastPlayedAt != null) {
                    Surface(Modifier.align(Alignment.TopEnd).padding(10.dp), shape = CircleShape,
                        color = MaterialTheme.colorScheme.surface.copy(alpha = .6f)) {
                        Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            if (playing) Icon(Icons.Default.GraphicEq, null, Modifier.size(14.dp))
                            Text(if (playing) "Playing" else relativePlayedAt(book.lastPlayedAt ?: 0), fontSize = 12.sp, lineHeight = 15.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
                Surface(Modifier.align(Alignment.BottomEnd).offset(x = 9.dp, y = 9.dp), shape = CircleShape,
                    color = androidx.compose.ui.graphics.lerp(coverColor, Color.White, .32f)) {
                    IconButton(onClick = onFavorite, modifier = Modifier.size(40.dp).testTag("book.favorite.${book.id}")
                        .semantics { contentDescription = if (book.isFavorite) "Remove favorite" else "Add favorite" }) {
                        Icon(if (book.isFavorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder, null,
                            Modifier.size(20.dp), tint = if (book.isFavorite) UnpagedTheme.favorite else Color.White)
                    }
                }
            }
            // iOS bottom-aligns the text block: a one-line title leaves its slack above the title, not below it.
            Column(Modifier.heightIn(min = 76.dp), verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.Bottom)) {
                Text(book.title, fontSize = 15.sp, lineHeight = 19.sp, fontWeight = FontWeight.SemiBold,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(book.author.ifBlank { stringResource(R.string.unknown_author) }, fontSize = 12.sp, lineHeight = 16.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Schedule, null, Modifier.size(10.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("${shortDuration(book.durationMs)} · ${if (book.isAudioMissing) "Audio Missing" else if (!book.isDownloaded) "Streaming" else "${book.storageBytes / (1024 * 1024)} MB"}", fontSize = 11.sp, lineHeight = 14.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            CatalogDownloadBadge(book.catalogId)
            Box {
                DropdownMenu(menu, onDismissRequest = { menu = false }, modifier = Modifier.semantics { testTagsAsResourceId = true }) {
                    DropdownMenuItem(text = { Text("Resume") }, onClick = { menu = false; onResume() },
                        leadingIcon = { Icon(Icons.Default.PlayArrow, null) }, modifier = Modifier.testTag("book.menu.resume"))
                    DropdownMenuItem(text = { Text(if (book.isFavorite) "Unfavorite" else "Favorite") }, onClick = { menu = false; onFavorite() },
                        leadingIcon = { Icon(Icons.Default.FavoriteBorder, null) }, modifier = Modifier.testTag("book.menu.favorite"))
                    if (!book.isFreeBook) DropdownMenuItem(text = { Text("Rename") }, onClick = { menu = false; onRename() },
                        leadingIcon = { Icon(Icons.Default.Edit, null) }, modifier = Modifier.testTag("book.menu.rename"))
                    DropdownMenuItem(text = { Text(if (!book.isDownloaded) "Remove from Library" else if (book.isFreeBook) "Remove Download" else "Delete") }, onClick = { menu = false; onRemove() },
                        leadingIcon = { Icon(Icons.Default.DeleteOutline, null) })
                }
                BookProgress(book.progress, 4)
            }
        }
    }
}

@Composable
internal fun BookProgress(progress: Float, height: Int = 5) {
    Box(Modifier.fillMaxWidth().height(height.dp).clip(CircleShape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = .08f))) {
        Box(Modifier.fillMaxWidth(progress.coerceIn(0f, 1f)).fillMaxHeight().clip(CircleShape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = .5f)))
    }
}

internal fun relativePlayedAt(timestamp: Long, now: Long = System.currentTimeMillis()): String {
    val minutes = ((now - timestamp).coerceAtLeast(0) / 60_000)
    return when { minutes < 1 -> "Just now"; minutes < 60 -> "$minutes min. ago"; minutes < 1440 -> "${minutes / 60} hr. ago"; else -> "${minutes / 1440} ${if (minutes / 1440 == 1L) "day" else "days"} ago" }
}

@Composable
internal fun EmptyFavorites() {
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Icon(Icons.Default.FavoriteBorder, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(16.dp))
        Text("No Favorites Yet", fontSize = 20.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        Text("Tap the heart on any book to save it here.", fontSize = 15.sp, lineHeight = 18.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
internal fun EmptyLibrary(canImport: Boolean, onImport: () -> Unit, onShelves: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)) {
        val ink = MaterialTheme.colorScheme.onSurfaceVariant
        Canvas(Modifier.size(48.dp)) {
            val w = size.width
            val stroke = Stroke(w * .055f)
            drawRoundRect(ink, androidx.compose.ui.geometry.Offset(w * .04f, w * .21f),
                androidx.compose.ui.geometry.Size(w * .17f, w * .70f), androidx.compose.ui.geometry.CornerRadius(w * .04f), style = stroke)
            drawRoundRect(ink, androidx.compose.ui.geometry.Offset(w * .23f, w * .09f),
                androidx.compose.ui.geometry.Size(w * .22f, w * .82f), androidx.compose.ui.geometry.CornerRadius(w * .04f), style = stroke)
            drawLine(ink, androidx.compose.ui.geometry.Offset(w * .28f, w * .42f), androidx.compose.ui.geometry.Offset(w * .40f, w * .42f), w * .055f)
            val leaning = Path().apply {
                moveTo(w * .58f, w * .19f); lineTo(w * .74f, w * .16f)
                lineTo(w * .89f, w * .88f); lineTo(w * .72f, w * .91f); close()
            }
            drawPath(leaning, ink, style = stroke)
        }
        Text(stringResource(R.string.empty_library), fontSize = 20.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold)
        Text("Import an audiobook from Files, or browse thousands of free public-domain classics.", fontSize = 15.sp, lineHeight = 18.sp,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button(onClick = onImport, enabled = canImport, shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onSurface,
                contentColor = MaterialTheme.colorScheme.background)) { Text(stringResource(R.string.import_book)) }
        TextButton(onClick = onShelves) { Text("Browse Shelves", color = MaterialTheme.colorScheme.onSurface) }
    }
}

@Composable
internal fun shortDuration(milliseconds: Long): String {
    val minutes = milliseconds / 60_000
    return if (minutes >= 60 && minutes % 60 == 0L) "${minutes / 60}h"
        else if (minutes >= 60) stringResource(R.string.short_hours_minutes, minutes / 60, minutes % 60)
        else stringResource(R.string.short_minutes, minutes)
}

internal fun trackDuration(milliseconds: Long): String {
    val seconds = (milliseconds.coerceIn(0, 1_000_000_000L) + 500) / 1000
    return if (seconds >= 3600) String.format(Locale.ROOT, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        else String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60)
}
