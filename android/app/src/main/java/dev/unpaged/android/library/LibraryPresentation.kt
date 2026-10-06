package dev.unpaged.android.library

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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
internal fun GeneratedBookCover(title: String, modifier: Modifier = Modifier) {
    val foreground = CoverPalette.foreground(title)
    BoxWithConstraints(modifier.clip(RoundedCornerShape(16.dp)).background(CoverPalette.background(title))
        .semantics { contentDescription = "Cover for $title" }) {
        val side = minOf(maxWidth, maxHeight)
        val inset = side * 0.1f
        Text(title, Modifier.padding(horizontal = inset).padding(top = side * 0.155f),
            fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium,
            fontSize = (side.value * 0.121f).sp, lineHeight = (side.value * 0.142f).sp,
            color = foreground, maxLines = 4, overflow = TextOverflow.Ellipsis)
        Column(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(horizontal = inset)
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
internal fun LibraryHeader(count: Int, canImport: Boolean, onImport: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Surface(Modifier.size(48.dp), shape = CircleShape, color = MaterialTheme.colorScheme.onSurface) {
            Box(contentAlignment = Alignment.Center) {
                Text(count.toString(), fontSize = 17.sp, fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.background)
            }
        }
        Text(stringResource(R.string.your_library), Modifier.weight(1f), fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
        Surface(shape = RoundedCornerShape(10.dp), shadowElevation = 3.dp) {
            TextButton(onClick = onImport, enabled = canImport, modifier = Modifier.size(48.dp)
                .semantics { contentDescription = "Import Audiobook" }, contentPadding = PaddingValues(0.dp)) {
                Text("+", fontSize = 28.sp, color = MaterialTheme.colorScheme.onSurface)
            }
        }
    }
    // Current implemented destination; Favorites/Shelves will arrive with their functional slices.
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(stringResource(R.string.library), Modifier.padding(top = 12.dp, bottom = 8.dp),
            fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        HorizontalDivider(Modifier.fillMaxWidth(.333f), thickness = 2.dp, color = MaterialTheme.colorScheme.onSurface)
        HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = .12f))
    }
}

@Composable
internal fun LibraryBookCard(book: LibraryBook, onOpen: () -> Unit) {
    Surface(Modifier.fillMaxWidth().clickable(onClick = onOpen), shape = RoundedCornerShape(28.dp),
        shadowElevation = 3.dp) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            GeneratedBookCover(book.title, Modifier.fillMaxWidth().height(185.dp))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(book.title, Modifier.heightIn(min = 38.dp), fontSize = 15.sp, lineHeight = 19.sp, fontWeight = FontWeight.SemiBold,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(book.author.ifBlank { stringResource(R.string.unknown_author) }, fontSize = 12.sp, lineHeight = 16.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(shortDuration(book.durationMs), fontSize = 11.sp, lineHeight = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
internal fun EmptyLibrary(canImport: Boolean, onImport: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
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
        Text(stringResource(R.string.empty_library), fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
        Text(stringResource(R.string.empty_library_hint), fontSize = 15.sp,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button(onClick = onImport, enabled = canImport, shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onSurface,
                contentColor = MaterialTheme.colorScheme.background)) { Text(stringResource(R.string.import_book)) }
    }
}

@Composable
internal fun shortDuration(milliseconds: Long): String {
    val minutes = milliseconds / 60_000
    return if (minutes >= 60) stringResource(R.string.short_hours_minutes, minutes / 60, minutes % 60)
        else stringResource(R.string.short_minutes, minutes)
}

internal fun trackDuration(milliseconds: Long): String {
    val seconds = milliseconds / 1000
    return if (seconds >= 3600) String.format(Locale.ROOT, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        else String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60)
}
