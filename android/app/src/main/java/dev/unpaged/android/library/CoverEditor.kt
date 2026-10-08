package dev.unpaged.android.library

import androidx.core.graphics.scale
import androidx.core.net.toUri
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Rect
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

/** Bounded decode and EXIF normalization before a crop, including mirrored images. */
private fun decodeCover(context: android.content.Context, uri: Uri): Bitmap {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    context.contentResolver.openInputStream(uri)!!.use { BitmapFactory.decodeStream(it, null, bounds) }
    require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Couldn't read this photo." }
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 2048) sample *= 2
    val bitmap = context.contentResolver.openInputStream(uri)!!.use {
        BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
    } ?: error("Couldn't read this photo.")
    val orientation = runCatching { context.contentResolver.openInputStream(uri)!!.use {
        androidx.exifinterface.media.ExifInterface(it).getAttributeInt(androidx.exifinterface.media.ExifInterface.TAG_ORIENTATION, 1)
    } }.getOrDefault(1)
    val matrix = Matrix()
    when (orientation) {
        2 -> matrix.setScale(-1f, 1f)
        3 -> matrix.setRotate(180f)
        4 -> matrix.setScale(1f, -1f)
        5 -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
        6 -> matrix.setRotate(90f)
        7 -> { matrix.setRotate(270f); matrix.postScale(-1f, 1f) }
        8 -> matrix.setRotate(270f)
    }
    return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
}

@Composable
fun EditableBookCover(book: LibraryBook, onSave: (Bitmap?) -> Unit) {
    val context = LocalContext.current
    var pendingUri by rememberSaveable { mutableStateOf<String?>(null) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var menu by rememberSaveable { mutableStateOf(false) }
    val pending by produceState<Bitmap?>(null, pendingUri) {
        value = null
        pendingUri?.let { uri ->
            try { value = withContext(Dispatchers.IO) { decodeCover(context, uri.toUri()) } }
            catch (e: Exception) { error = e.message ?: "Couldn't read this photo."; pendingUri = null }
        }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) pendingUri = uri.toString()
    }
    // An Audiobookshelf cover is the downloaded server file; removing it could not be undone.
    val removable = book.coverRevision > 0 && book.absItemID == null
    Box {
        Box(Modifier.size(130.dp).combinedClickable(
            onClick = { picker.launch(arrayOf("image/*")) },
            onLongClick = { if (removable) menu = true }).testTag("book.cover")) {
            LibraryBookCover(book, Modifier.matchParentSize(), cornerRadius = 20)
            Text("Change cover", Modifier.align(Alignment.BottomCenter).padding(8.dp)
                .background(Color.White.copy(alpha = .35f), CircleShape)
                .padding(horizontal = 8.dp, vertical = 4.dp),
                fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.Medium, color = Color.White)
        }
        DropdownMenu(menu, { menu = false }, modifier = Modifier.semantics { testTagsAsResourceId = true }) {
            if (removable) DropdownMenuItem(text = { Text("Remove cover") }, onClick = { menu = false; onSave(null) },
                modifier = Modifier.testTag("book.cover.remove"))
        }
    }
    pending?.let { bitmap -> CoverCrop(bitmap, { onSave(it); pendingUri = null }, { pendingUri = null }) }
    error?.let { message -> AlertDialog(modifier = Modifier.semantics { testTagsAsResourceId = true }, onDismissRequest = { error = null }, title = { Text("Couldn't Change Cover") }, text = { Text(message) },
        confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } }) }
}

@Composable
private fun CoverCrop(bitmap: Bitmap, confirm: (Bitmap) -> Unit, cancel: () -> Unit) {
    var zoom by rememberSaveable { mutableFloatStateOf(1f) }
    var panX by rememberSaveable { mutableFloatStateOf(0f) }
    var panY by rememberSaveable { mutableFloatStateOf(0f) }
    var displaySide by remember { mutableFloatStateOf(1f) }
    fun crop(): Rect {
        val width = minOf(bitmap.width, bitmap.height) / zoom
        val ratio = displaySide / width
        val x = ((bitmap.width - width) / 2 - panX / ratio).coerceIn(0f, bitmap.width - width)
        val y = ((bitmap.height - width) / 2 - panY / ratio).coerceIn(0f, bitmap.height - width)
        val side = width.roundToInt().coerceAtLeast(1)
        val left = x.roundToInt().coerceIn(0, bitmap.width - side)
        val top = y.roundToInt().coerceIn(0, bitmap.height - side)
        return Rect(left, top, left + side, top + side)
    }
    Dialog(cancel, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Column(Modifier.fillMaxSize().background(Color.Black).safeDrawingPadding().semantics { testTagsAsResourceId = true }) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                TextButton(cancel, Modifier.testTag("cover.cancel")) { Text("Cancel", color = Color.White) }
                Text("Crop Cover", Modifier.weight(1f), color = Color.White)
                TextButton({
                    val rect = crop()
                    val cropped = Bitmap.createBitmap(bitmap, rect.left, rect.top, rect.width(), rect.height())
                    confirm(cropped.scale(600, 600))
                }, Modifier.testTag("cover.confirm")) { Text("Use Photo", color = Color.White) }
            }
            Column(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally) {
                Canvas(Modifier.size(300.dp).clip(RoundedCornerShape(24.dp)).testTag("cover.crop")
                    .pointerInput(bitmap) {
                        detectTransformGestures { _, delta, scale, _ ->
                            zoom = (zoom * scale).coerceIn(1f, 12f)
                            val ratio = displaySide / (minOf(bitmap.width, bitmap.height) / zoom)
                            val maxX = (bitmap.width * ratio - displaySide) / 2
                            val maxY = (bitmap.height * ratio - displaySide) / 2
                            panX = (panX + delta.x).coerceIn(-maxX, maxX)
                            panY = (panY + delta.y).coerceIn(-maxY, maxY)
                        }
                    }) {
                    displaySide = size.width
                    val rect = crop()
                    drawImage(bitmap.asImageBitmap(), IntOffset(rect.left, rect.top), IntSize(rect.width(), rect.height()),
                        dstSize = IntSize(size.width.toInt(), size.height.toInt()))
                }
                Spacer(Modifier.height(28.dp))
                Text("Pinch to zoom  ·  Drag to reposition", color = Color.White.copy(alpha = .55f),
                    style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}
