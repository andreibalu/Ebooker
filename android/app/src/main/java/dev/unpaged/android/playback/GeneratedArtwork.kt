package dev.unpaged.android.playback

import android.graphics.Bitmap
import androidx.core.graphics.createBitmap
import androidx.core.graphics.withTranslation
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.text.StaticLayout
import android.text.TextPaint
import dev.unpaged.android.library.CoverPalette
import androidx.compose.ui.graphics.toArgb
import java.io.ByteArrayOutputStream

/** Notification artwork uses the same deterministic palette and proportions as the Compose cover. */
object GeneratedArtwork {
    fun png(title: String): ByteArray {
        val bitmap = createBitmap(600, 600)
        val canvas = Canvas(bitmap)
        canvas.drawColor(CoverPalette.background(title).toArgb())
        val ink = CoverPalette.foreground(title).toArgb()
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = ink; textSize = 72.6f; typeface = Typeface.create("serif", Typeface.BOLD) }
        val text = StaticLayout.Builder.obtain(title, 0, title.length, paint, 480).setMaxLines(4)
            .setEllipsize(android.text.TextUtils.TruncateAt.END).build()
        canvas.withTranslation(60f, 93f) { text.draw(this) }
        val line = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ink; strokeWidth = 2f; alpha = 140 }
        canvas.drawLine(60f, 516f, 540f, 516f, line)
        paint.textSize = 23.7f; paint.alpha = 200; paint.letterSpacing = .2f
        canvas.drawText("UNPAGED", 60f, 555f, paint)
        line.alpha = 255; line.strokeWidth = 4f; line.style = Paint.Style.STROKE
        canvas.drawRect(62f, 440f, 99f, 489f, line)
        for (i in 0..2) canvas.drawLine(70f, 451f + i * 9, 90f, 448f + i * 9, line)
        val bytes = ByteArrayOutputStream().use { out -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, out); out.toByteArray() }
        bitmap.recycle()
        return bytes
    }
}
