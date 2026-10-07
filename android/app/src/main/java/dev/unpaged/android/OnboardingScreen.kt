package dev.unpaged.android

import android.Manifest
import android.os.Build
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.geometry.Offset
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DownloadForOffline
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.unpaged.android.activity.*
import kotlinx.coroutines.launch

/** Seven pages: Android permissions, manual moments and private local storage replace Apple-only claims. */
@Composable
fun OnboardingScreen(preferences: UnpagedPreferences) {
    preferenceRevision(preferences)
    val pager = rememberPagerState(pageCount = { 7 })
    val scope = rememberCoroutineScope()
    val reduced = reducedMotion()
    val context = LocalContext.current
    val ambientAmber = ActivityAmber
    var granted by remember { mutableStateOf(Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted = it }
    val owner = androidx.lifecycle.compose.LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) granted = Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    fun jump(page: Int) { scope.launch { if (reduced) pager.scrollToPage(page) else pager.animateScrollToPage(page) } }
    LaunchedEffect(granted, pager.currentPage) {
        if (granted && pager.currentPage == 1) { kotlinx.coroutines.delay(800); if (pager.currentPage == 1) jump(2) }
    }
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, 1f)) {
        Surface(color = MaterialTheme.colorScheme.background, modifier = Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }.testTag("onboarding")) {
            Box(Modifier.safeDrawingPadding()) {
                VerticalPager(pager, Modifier.fillMaxSize()) { page ->
                    val reveal = remember { Animatable(if (reduced) 1f else 0f) }
                    LaunchedEffect(pager.currentPage == page, reduced) {
                        if (reduced) reveal.snapTo(1f) else if (pager.currentPage == page) reveal.animateTo(1f, tween(620)) else reveal.snapTo(0f)
                    }
                    Box(Modifier.fillMaxSize().drawBehind {
                        if (page == 0) drawRect(Brush.radialGradient(
                            listOf(ambientAmber.copy(alpha = .12f), androidx.compose.ui.graphics.Color.Transparent),
                            center = Offset(size.width / 2, size.height * .14f), radius = 340.dp.toPx()))
                    }, contentAlignment = Alignment.TopCenter) {
                    Column(Modifier.fillMaxHeight().widthIn(max = 402.dp).fillMaxWidth().alpha(reveal.value).padding(horizontal = 26.dp).padding(top = if (page == 0) 8.dp else 24.dp, bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(if (page == 0) 0.dp else 16.dp)) {
                        when(page) {
                            0 -> {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Box(Modifier.size(26.dp).background(ActivityAmber, RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) { Text("▤", color = androidx.compose.ui.graphics.Color.White) }
                                    Text("Unpaged", fontSize = 22.sp, fontWeight = FontWeight.Bold)
                                }
                                Spacer(Modifier.height(22.dp))
                                OnboardingHeading("Welcome", "How do you want\nto start?", "Pick one — this sets your home tab. You can change it later.")
                                Spacer(Modifier.height(24.dp))
                                ChoiceCard("Shelves", "Thousands of free public-domain audiobooks, ready to play.", "No import needed", true) { preferences.setShelvesFirst(true); jump(1) }
                                Spacer(Modifier.height(14.dp))
                                ChoiceCard("My books", "Bring audiobooks you already own. Import from Files.", "Your own library", false) { preferences.setShelvesFirst(false); jump(1) }
                                Text("Scroll to continue\n⌄", Modifier.align(Alignment.CenterHorizontally).padding(top = 26.dp), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .4f))
                            }
                            1 -> {
                                OnboardingHeading("Permissions", "Playback, beyond\nthe app.", "Allow notifications for audiobook controls. You can continue without them.")
                                Surface(shape = RoundedCornerShape(24.dp)) { Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                    Text("Notifications", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                                    Text("Control playback from your notification shade while you listen.")
                                    Button(onClick = {
                                        preferences.setText("notificationPrompted", "true")
                                        if (Build.VERSION.SDK_INT >= 33) {
                                            if (preferences.text("onboardingNotificationAsked", "false") == "true" && !granted && !(context as android.app.Activity).shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) {
                                                context.startActivity(android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.fromParts("package", context.packageName, null)))
                                            } else { preferences.setText("onboardingNotificationAsked", "true"); permission.launch(Manifest.permission.POST_NOTIFICATIONS) }
                                        }
                                    }, enabled = !granted, modifier = Modifier.testTag("onboarding.notifications")) { Text(if (granted) "Allowed" else "Continue") }
                                } }
                            }
                            2 -> {
                                OnboardingHeading("Playback", "Set up listening.", "Three quick choices. The defaults are good too.")
                                PreferenceChoices(preferences, "On resume", "resumeBacktrackSeconds", 60, listOf(0, 15, 30, 60))
                                PreferenceChoices(preferences, "Skip back", "skipBackSeconds", 30, listOf(15, 30, 45))
                                PreferenceChoices(preferences, "Skip forward", "skipForwardSeconds", 30, listOf(15, 30, 45))
                                PreferenceChoices(preferences, "Save moment offset", "momentBacktrackSeconds", 0, listOf(0, 15, 30, 60, 120))
                            }
                            3 -> {
                                OnboardingHeading("If you stick with it · A sample year", "Imagine your year.", "Unpaged keeps count, quietly. Here's what a year can look like.")
                                val sampleHours = remember { Animatable(if (reduced) 127f else 0f) }
                                LaunchedEffect(pager.currentPage == 3, reduced) { if (reduced) sampleHours.snapTo(127f) else if (pager.currentPage == 3) sampleHours.animateTo(127f, tween(1700)) else sampleHours.snapTo(0f) }
                                Text("${sampleHours.value.toInt()} hours", fontFamily = FontFamily.Serif, fontSize = 64.sp, color = ActivityAmber)
                                Text("across 240 sessions and 168 days.")
                                val sample = remember { ReadingStats((0..112).filter { it % 5 != 0 }.map { ReadingSession(day = java.time.LocalDate.now().minusDays(it.toLong()), hour = 20, minutes = 45, bookId = "sample", bookTitle = "A sample year", bookAuthor = "", isFreeBook = true) }, 0) }
                                Heatmap(sample)
                                Text("Your activity grows as you listen. Find it in Favorites.")
                            }
                            4 -> {
                                OnboardingHeading("Saved moments", "Keep the passages\nthat stay with you.", "Save a moment while listening, then return to its timestamp from your book.")
                                Surface(shape = RoundedCornerShape(24.dp)) { Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    Text("SAVED MOMENT · 1:24:07", fontSize = 11.sp, color = ActivityAmber)
                                    Text("Saved Moment", fontFamily = FontFamily.Serif, fontSize = 28.sp)
                                    Text("On-device AI can name moments and recap local books on supported phones. Set it up in Settings → On-device AI.")
                                } }
                            }
                            5 -> {
                                OnboardingHeading("Your library", "Your books.\nYour phone.", "Imported audio and listening activity stay in Unpaged's private storage on this device.")
                                Text("Import copies your files; your originals stay where they are. Download Shelves books for offline listening.", fontSize = 17.sp)
                                Text("Android can back up your library metadata when Backup by Google is on. Audio files stay on this phone and need re-importing after restore.", fontSize = 17.sp)
                            }
                            6 -> {
                                Spacer(Modifier.height(28.dp))
                                Text("✓", fontSize = 60.sp, color = ActivityAmber, modifier = Modifier.align(Alignment.CenterHorizontally))
                                OnboardingHeading("Done", "You're all set.", "Starting with ${if (preferences.shelvesFirst()) "Shelves" else "your books"}. Adjust anything in Settings whenever you like.")
                                Surface(shape = RoundedCornerShape(24.dp)) { Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Text("Open To: ${if (preferences.shelvesFirst()) "Shelves" else "Library"}")
                                    Text("Notifications: ${if (granted) "Allowed" else "Skipped"}")
                                    listOf("resumeBacktrackSeconds" to 60, "skipBackSeconds" to 30, "skipForwardSeconds" to 30, "momentBacktrackSeconds" to 0).forEach { (key, default) ->
                                        Text("${when(key) { "resumeBacktrackSeconds" -> "On resume"; "skipBackSeconds" -> "Skip back"; "skipForwardSeconds" -> "Skip forward"; else -> "Save moment offset" }}: ${preferences.seconds(key, default)}s")
                                    }
                                } }
                                Button(onClick = { preferences.setText("onboardingLanding", if (preferences.shelvesFirst()) "Shelves" else "Library"); preferences.setOnboardingComplete(true) }, Modifier.fillMaxWidth().height(52.dp).testTag("onboarding.finish"), shape = RoundedCornerShape(16.dp), colors = ButtonDefaults.buttonColors(containerColor = ActivityAmber, contentColor = androidx.compose.ui.graphics.Color.White)) { Text("Open Library", fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }
                                Text("Takes you straight to your books.", fontSize = 12.sp)
                            }
                        }
                        if (page in 1..5) TextButton(onClick = { jump(page + 1) }, Modifier.testTag("onboarding.next")) { Text("Scroll to continue ↓", color = ActivityAmber) }
                    }
                }
                }
                // Match the iOS rail's 23dp pitch without Compose expanding adjacent
                // hit regions to 48dp and routing a dot tap to its neighbour.
                val viewConfiguration = LocalViewConfiguration.current
                CompositionLocalProvider(LocalViewConfiguration provides object : androidx.compose.ui.platform.ViewConfiguration by viewConfiguration {
                    override val minimumTouchTargetSize = DpSize(44.dp, 23.dp)
                }) {
                    Column(Modifier.align(Alignment.CenterEnd).padding(end = 9.dp)) {
                        listOf("Start", "Permissions", "Playback", "Your year", "Moments", "Local library", "Done").forEachIndexed { index, label ->
                            Box(Modifier.width(44.dp).height(23.dp).clickable { jump(index) }.testTag("onboarding.page.$index").semantics { this.contentDescription = label }, contentAlignment = Alignment.CenterEnd) {
                                Box(Modifier.size(14.dp), contentAlignment = Alignment.Center) {
                                    Box(Modifier.size(if (pager.currentPage == index) 8.dp else 6.dp).background(if (pager.currentPage == index) ActivityAmber else MaterialTheme.colorScheme.onSurface.copy(alpha = .25f), CircleShape))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
@Composable
private fun OnboardingHeading(eyebrow: String, title: String, subtitle: String) {
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Text(eyebrow.uppercase(java.util.Locale.ENGLISH), fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp, color = ActivityAmber)
        Text(title, fontSize = 31.sp, lineHeight = 38.sp, fontWeight = FontWeight.Bold, letterSpacing = (-.8).sp)
        Text(subtitle, fontSize = 15.5.sp, lineHeight = 23.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable
private fun ChoiceCard(title: String, description: String, badge: String, shelves: Boolean, onClick: () -> Unit) {
    Surface(shape = RoundedCornerShape(24.dp), shadowElevation = 2.dp, modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).testTag("onboarding.choice.$title")) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(52.dp).background(ActivityAmber.copy(alpha = .12f), RoundedCornerShape(16.dp)), contentAlignment = Alignment.Center) {
                Icon(if (shelves) Icons.AutoMirrored.Filled.LibraryBooks else Icons.Default.DownloadForOffline, null, Modifier.size(30.dp), tint = ActivityAmber)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text(title, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Text(description, fontSize = 13.5.sp, lineHeight = 19.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(badge, Modifier.background(ActivityAmber.copy(alpha = .12f), CircleShape).padding(horizontal = 9.dp, vertical = 3.dp), fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.SemiBold, color = ActivityAmber)
            }
        }
    }
}
@Composable
private fun PreferenceChoices(preferences: UnpagedPreferences, title: String, key: String, default: Int, choices: List<Int>) {
    Surface(shape = RoundedCornerShape(18.dp)) { Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) { choices.forEach { value ->
            val selected = preferences.seconds(key, default) == value
            Box(Modifier.weight(1f).background(if (selected) ActivityAmber else MaterialTheme.colorScheme.surfaceVariant, CircleShape).clickable { preferences.setSeconds(key, value) }.testTag("onboarding.$key.$value").padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
                Text(if (value == 0) "Exact" else if (value >= 60) "${value / 60}m" else "${value}s", fontSize = 12.sp, color = if (selected) ColorWhite else MaterialTheme.colorScheme.onSurface)
            }
        } }
    } }
}
private val ColorWhite = androidx.compose.ui.graphics.Color.White
