package dev.unpaged.android.activity

import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.drawscope.Stroke
import dev.unpaged.android.library.GeneratedBookCover
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.roundToInt
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

val ActivityAmber = Color(0xFFCC8632)
@Composable
fun reducedMotion(): Boolean {
    val context = LocalContext.current
    var reduced by remember { mutableStateOf(false) }
    DisposableEffect(context) {
        val resolver = context.contentResolver
        fun refresh() { reduced = Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
        val observer = object : android.database.ContentObserver(android.os.Handler(android.os.Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) { refresh() }
        }
        refresh()
        resolver.registerContentObserver(Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE), false, observer)
        onDispose { resolver.unregisterContentObserver(observer) }
    }
    return reduced
}

@Composable
fun ActivityCard(stats: ReadingStats, onClick: () -> Unit) {
    val days = when { stats.daysTracked <= 7 -> 7; stats.daysTracked <= 30 -> 30; else -> 120 }
    Surface(shape = RoundedCornerShape(22.dp), shadowElevation = 2.dp,
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).testTag("activity.card")) {
        Column(Modifier.padding(horizontal = 18.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column {
                    Eyebrow("ACTIVITY")
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(activityDuration(stats.totalMinutes), fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                        Text(" · ${when(days) { 7 -> "Last 7 days"; 30 -> "Last 30 days"; else -> "Last 4 months" }}",
                            fontSize = 17.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Text("›", Modifier.background(MaterialTheme.colorScheme.onSurface.copy(alpha = .06f), RoundedCornerShape(50)).padding(horizontal = 10.dp), fontSize = 26.sp)
            }
            Heatmap(stats, days)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(if (stats.currentStreak > 0) "● ${stats.currentStreak}-day streak" else "Start a streak today",
                    Modifier.background(MaterialTheme.colorScheme.onSurface.copy(alpha = .06f), RoundedCornerShape(50)).padding(horizontal = 9.dp, vertical = 4.dp), fontSize = 11.sp)
                Legend()
            }
        }
    }
}
@Composable
private fun Legend() {
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("Less", fontSize = 10.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        (0..4).forEach { level -> Box(Modifier.size(9.dp).background(heatPalette()[level], RoundedCornerShape(2.dp))) }
        Text("More", fontSize = 10.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable
fun Heatmap(stats: ReadingStats, days: Int = 120) {
    val empty = MaterialTheme.colorScheme.onSurface.copy(alpha = .04f)
    val palette = heatPalette()
    if (days == 7) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
        (6 downTo 0).forEach { offset ->
            val date = stats.today.minusDays(offset.toLong())
            Column(Modifier.padding(horizontal = 3.5.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(date.format(DateTimeFormatter.ofPattern("EEE", Locale.ENGLISH)), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(7.dp))
                Box(Modifier.size(30.dp).background(cellColor(stats.days[date] ?: 0, empty, palette), RoundedCornerShape(6.dp)))
            }
        }
    } else if (days == 30) {
        val start = stats.today.minusDays(29)
        Column {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(start.format(DateTimeFormatter.ofPattern("MMM", Locale.ENGLISH)), fontSize = 10.sp)
                Text(stats.today.format(DateTimeFormatter.ofPattern("MMM", Locale.ENGLISH)), fontSize = 10.sp)
            }
            Canvas(Modifier.fillMaxWidth().height(12.dp)) {
                val gap = 2.dp.toPx(); val cell = (size.width - 29 * gap) / 30
                repeat(30) { index -> drawRoundRect(cellColor(stats.days[start.plusDays(index.toLong())] ?: 0, empty, palette), Offset(index * (cell + gap), 0f), Size(cell, cell), CornerRadius(2.dp.toPx())) }
            }
        }
    } else {
        val end = stats.today
        val start = end.minusDays(days.toLong() - 1).with(java.time.temporal.TemporalAdjusters.previousOrSame(java.time.DayOfWeek.MONDAY))
        val count = java.time.temporal.ChronoUnit.DAYS.between(start, end).toInt() + 1
        val columns = (count + 6) / 7
        Column {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(start.format(DateTimeFormatter.ofPattern("MMM", Locale.ENGLISH)), fontSize = 10.sp)
                Text(end.format(DateTimeFormatter.ofPattern("MMM", Locale.ENGLISH)), fontSize = 10.sp)
            }
            Canvas(Modifier.fillMaxWidth().height(if (days == 30) 68.dp else 100.dp)) {
                val gap = 3.dp.toPx(); val cell = minOf((size.width - (columns - 1) * gap) / columns, (size.height - 6 * gap) / 7)
                for (index in 0 until count) {
                    val date = start.plusDays(index.toLong())
                    drawRoundRect(cellColor(stats.days[date] ?: 0, empty, palette), Offset((index / 7) * (cell + gap), (index % 7) * (cell + gap)),
                        Size(cell, cell), CornerRadius(2.dp.toPx()))
                }
            }
        }
    }
}
@Composable
private fun heatPalette(): List<Color> = if (MaterialTheme.colorScheme.background.red < .5f)
    listOf(0xFF2A2722, 0xFF4A3C26, 0xFF7B5C2A, 0xFFB07A1F, 0xFFE59A19).map { Color(it) }
    else listOf(0xFFECE4D2, 0xFFF3D9A8, 0xFFE8B36C, 0xFFCC8632, 0xFF995510).map { Color(it) }
private fun cellColor(minutes: Int, empty: Color, palette: List<Color>) = if (minutes == 0) empty else palette[when { minutes < 15 -> 1; minutes < 30 -> 2; minutes < 60 -> 3; else -> 4 }]
@Composable
private fun Eyebrow(text: String) { Text(text.uppercase(Locale.ENGLISH), Modifier.testTag("stats.eyebrow.${text.lowercase(Locale.ENGLISH).replace(" ", "_")}"), fontSize = 11.sp, letterSpacing = .7.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant) }
@Composable
private fun Reveal(top: Int = 40, bottom: Int = 30, content: @Composable ColumnScope.() -> Unit) {
    val reduced = reducedMotion()
    val alpha = remember { Animatable(if (reduced) 1f else 0f) }
    LaunchedEffect(reduced) { if (reduced) alpha.snapTo(1f) else alpha.animateTo(1f, tween(450)) }
    Column(Modifier.fillMaxWidth().alpha(alpha.value).padding(top = top.dp, bottom = bottom.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
}
@Composable
private fun Count(value: Int, suffix: String = "", hours: Boolean = false, size: Int = if (hours) 96 else 54) {
    val reduced = reducedMotion()
    val count = remember(value) { Animatable(if (reduced) value.toFloat() else 0f) }
    LaunchedEffect(value, reduced) { if (reduced) count.snapTo(value.toFloat()) else count.animateTo(value.toFloat(), tween(1400)) }
    val number = if (hours) { val h = count.value / 60; if (h < 10) String.format(Locale.ENGLISH, "%.1f", h) else h.toInt().toString() } else count.value.roundToInt().toString()
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(number, fontFamily = FontFamily.Serif, fontSize = size.sp, color = ActivityAmber)
        if (suffix.isNotEmpty()) Text(suffix.trim(), fontFamily = FontFamily.Serif, fontSize = 30.sp, modifier = Modifier.padding(bottom = 10.dp))
    }
}
@Composable
private fun Bars(values: List<Int>, labels: List<String>) {
    val maximum = (values.maxOrNull() ?: 0).coerceAtLeast(1)
    Row(Modifier.fillMaxWidth().height(110.dp), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.Bottom) {
        values.forEachIndexed { index, value -> Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.fillMaxWidth().height((75f * value / maximum).coerceAtLeast(2f).dp).background(ActivityAmber.copy(alpha = if (value == maximum) 1f else .4f), RoundedCornerShape(3.dp)))
            if (labels.size <= 7 || index % 6 == 0) Text(labels[index], fontSize = 9.sp, maxLines = 1)
        } }
    }
}
@Composable
private fun ClockChart(stats: ReadingStats) {
    val ink = MaterialTheme.colorScheme.onSurface.copy(alpha = .18f)
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(240.dp)) {
            val radius = 92.dp.toPx(); val inner = 38.dp.toPx()
            val buckets = List(12) { stats.hours[it] + stats.hours[it + 12] }
            val maximum = (buckets.maxOrNull() ?: 0).coerceAtLeast(1)
            drawCircle(ink, radius, style = Stroke(1.dp.toPx()))
            drawCircle(ink, inner, style = Stroke(1.dp.toPx()))
            buckets.forEachIndexed { index, minutes ->
                val angle = index * Math.PI / 6 - Math.PI / 2
                val direction = Offset(cos(angle).toFloat(), sin(angle).toFloat())
                val length = (radius - inner) * minutes / maximum
                drawLine(if (index == stats.bestHour % 12) ActivityAmber else ActivityAmber.copy(alpha = .4f), center + direction * inner, center + direction * (inner + length.coerceAtLeast(2.dp.toPx())), 10.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round)
            }
        }
        Text("12", Modifier.align(Alignment.TopCenter), fontSize = 12.sp)
        Text("6", Modifier.align(Alignment.BottomCenter), fontSize = 12.sp)
        Text("9", Modifier.align(Alignment.CenterStart).padding(start = 40.dp), fontSize = 12.sp)
        Text("3", Modifier.align(Alignment.CenterEnd).padding(end = 40.dp), fontSize = 12.sp)
    }
}
@Composable
private fun Metric(label: String, value: String, subtitle: String, modifier: Modifier) {
    Surface(modifier, shape = RoundedCornerShape(14.dp)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Eyebrow(label); Text(value, fontFamily = FontFamily.Serif, fontSize = 26.sp); Text(subtitle, fontSize = 11.sp)
        }
    }
}

@Composable
fun ReadingStatsScreen(stats: ReadingStats, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val scroll = androidx.compose.foundation.lazy.rememberLazyListState()
    val showTitle by remember { derivedStateOf { scroll.firstVisibleItemIndex > 0 || scroll.firstVisibleItemScrollOffset > 180 } }
    Surface(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }.testTag("reading.stats"), color = MaterialTheme.colorScheme.background) {
        Column(Modifier.safeDrawingPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onBack) { Text("‹ Library", color = MaterialTheme.colorScheme.onSurface) }
                Text("Reading", Modifier.weight(1f).alpha(if (showTitle) 1f else 0f), fontWeight = FontWeight.SemiBold)
            }
            LazyColumn(Modifier.fillMaxSize().testTag("reading.stats.scroll"), state = scroll, contentPadding = PaddingValues(horizontal = 20.dp)) {
                item { Reveal(20, 28) { Eyebrow("Reading · ${when { stats.daysTracked <= 7 -> "Last 7 days"; stats.daysTracked <= 30 -> "Last 30 days"; else -> "Last 4 months" }}"); Text("Page by page.", fontFamily = FontFamily.Serif, fontSize = 38.sp); Heatmap(stats, if (stats.daysTracked <= 7) 7 else if (stats.daysTracked <= 30) 30 else 120); Text("${stats.firstDay.format(DateTimeFormatter.ofPattern("MMM d", Locale.ENGLISH))} — ${stats.today.format(DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.ENGLISH))}", Modifier.align(Alignment.CenterHorizontally), fontSize = 12.sp) } }
                item { Reveal(60, 40) { Eyebrow("You spent"); Count(stats.totalMinutes, "hours", hours = true); Text("listening across ${stats.sessions.size} sessions and ${stats.days.size} days. That's about ${activityDuration(stats.totalMinutes / stats.daysTracked)} every day you've had the app.") } }
                item { Reveal { Eyebrow("Your best day"); stats.bestDay?.let { day -> Text(day.key.format(DateTimeFormatter.ofPattern("EEEE", Locale.ENGLISH)) + ".", fontFamily = FontFamily.Serif, fontSize = 64.sp); val book = stats.sessions.filter { it.day == day.key }.groupBy { it.bookId }.maxByOrNull { it.value.sumOf { row -> row.minutes } }?.value?.first(); Text("with ${book?.bookAuthor?.substringAfterLast(" ") ?: "a book"}.", fontFamily = FontFamily.Serif, fontSize = 28.sp)
                    Surface(shape = RoundedCornerShape(18.dp)) { Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        GeneratedBookCover(book?.bookTitle ?: "Reading session", Modifier.size(64.dp), cornerRadius = 10)
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) { Text(day.key.format(DateTimeFormatter.ofPattern("EEE, MMMM d", Locale.ENGLISH)).uppercase(Locale.ENGLISH), fontSize = 10.sp); Text(book?.bookTitle.orEmpty(), fontFamily = FontFamily.Serif, fontSize = 17.sp); Text("${day.value} min", color = ActivityAmber, fontSize = 14.sp) }
                    } } } } }
                item { Reveal { Eyebrow("You read most in the"); Text(when(stats.bestHour) { in 0..4 -> "early hours."; in 5..10 -> "mornings."; in 11..13 -> "around noon."; in 14..17 -> "afternoons."; in 18..20 -> "evenings."; else -> "late evenings." }, fontFamily = FontFamily.Serif, fontSize = 38.sp); ClockChart(stats); Text("Peak hour: ${if (stats.bestHour % 12 == 0) 12 else stats.bestHour % 12} ${if (stats.bestHour < 12) "AM" else "PM"}"); Bars(stats.weekdays, listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")) } }
                item { Reveal { Eyebrow("The book you stayed with"); stats.longestBook?.let { GeneratedBookCover(it.bookTitle, Modifier.size(160.dp).rotate(-2f).align(Alignment.CenterHorizontally)); Text(it.bookTitle, Modifier.align(Alignment.CenterHorizontally), fontFamily = FontFamily.Serif, fontSize = 26.sp); Text("by ${it.bookAuthor}", Modifier.align(Alignment.CenterHorizontally), fontFamily = FontFamily.Serif); Count(stats.bookMinutes[it.bookId] ?: 0, "hours", hours = true, size = 56) } } }
                item { Reveal { Eyebrow("On a roll"); Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) { Column { Count(stats.currentStreak); Text("day streak") }; Column { Count(stats.longestStreak); Text("longest") } }; Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    val palette = heatPalette()
                    (27 downTo 0).forEach { offset -> val minutes = stats.days[stats.today.minusDays(offset.toLong())] ?: 0; Box(Modifier.weight(1f).height(28.dp).background(palette[when { minutes == 0 -> 0; minutes < 15 -> 1; minutes < 30 -> 2; minutes < 60 -> 3; else -> 4 }], RoundedCornerShape(2.dp))) }
                }; Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text("4 weeks ago", fontSize = 11.sp); Text("today", fontSize = 11.sp) } } }
                item { Reveal { Eyebrow("The shape of it"); Text("Steady, generous sessions", fontFamily = FontFamily.Serif, fontSize = 28.sp); Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { Metric("Avg session", "${stats.averageSession.roundToInt()}", "min", Modifier.weight(1f)); Metric("Finished", "${stats.booksFinished}", "books", Modifier.weight(1f)); Metric("Top author", stats.topAuthor?.key?.substringAfterLast(" ") ?: "—", "", Modifier.weight(1f)) } } }
                item { Reveal { Eyebrow("Public domain, private joy"); Box(Modifier.fillMaxWidth().height(170.dp), contentAlignment = Alignment.Center) {
                    Canvas(Modifier.size(150.dp)) { drawCircle(ActivityAmber.copy(alpha = .12f), style = Stroke(12.dp.toPx())); drawArc(ActivityAmber, -90f, 360f * stats.freePercent / 100, false, style = Stroke(12.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round)) }
                    Text("${stats.freePercent}%", fontFamily = FontFamily.Serif, fontSize = 36.sp)
                }; Text("${activityDuration(stats.freeMinutes)} of your listening was from free, public-domain recordings.") } }
                item { Reveal { Text("The unread copy of every great\nbook is still a great book.", fontFamily = FontFamily.Serif, fontSize = 28.sp); TextButton(onClick = onBack, Modifier.testTag("reading.stats.backToLibrary")) { Text("Back to Library") } } }
            }
        }
    }
}
