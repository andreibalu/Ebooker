package dev.unpaged.android.library

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/** Outline internal drive, matching the detail metadata's SF Symbol silhouette. */
internal val DriveIcon = ImageVector.Builder("Internal drive", 24.dp, 24.dp, 24f, 24f).apply {
    path(stroke = SolidColor(Color.Black), strokeLineWidth = 1.5f, strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round) {
        moveTo(3f, 13f); lineTo(6f, 5f); lineTo(18f, 5f); lineTo(21f, 13f)
        moveTo(5f, 13f); lineTo(19f, 13f); quadTo(21f, 13f, 21f, 15f)
        lineTo(21f, 18f); quadTo(21f, 20f, 19f, 20f); lineTo(5f, 20f)
        quadTo(3f, 20f, 3f, 18f); lineTo(3f, 15f); quadTo(3f, 13f, 5f, 13f)
        moveTo(7f, 16f); lineTo(7f, 17f); moveTo(10f, 16f); lineTo(10f, 17f)
        moveTo(13f, 16f); lineTo(13f, 17f); moveTo(16f, 16f); lineTo(16f, 17f)
    }
}.build()
