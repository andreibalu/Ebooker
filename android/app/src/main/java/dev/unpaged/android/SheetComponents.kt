package dev.unpaged.android

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

/** Toolbar capsules and the smaller filled Settings capsule share one implementation. */
@Composable
fun SheetDoneButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, filled: Boolean = false) {
    Surface(onClick = onClick, enabled = enabled, modifier = modifier, shape = CircleShape,
        color = if (filled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.surface,
        contentColor = if (filled) MaterialTheme.colorScheme.background else MaterialTheme.colorScheme.onSurface,
        border = if (filled) null else BorderStroke(.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .15f))) {
        Text("Done", Modifier.padding(horizontal = 16.dp, vertical = if (filled) 7.dp else 10.dp),
            fontSize = if (filled) 13.sp else 17.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** SwiftUI medium/large detents, with a medium height that includes the bottom safe area.
 * BottomSheetScaffold supplies native drag, nested scroll and accessibility expansion.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MediumLargeSheet(onDismissRequest: () -> Unit, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val state = rememberStandardBottomSheetState(initialValue = SheetValue.PartiallyExpanded, skipHiddenState = false)
    LaunchedEffect(state.currentValue) { if (state.currentValue == SheetValue.Hidden) onDismissRequest() }
    Dialog(onDismissRequest, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val largeHeight = maxHeight * .94f
            val mediumHeight = maxHeight * .525f
            // A scaffold keeps the large sheet below the window at its medium detent.
            // Constrain the scroll viewport to the visible portion, including its safe area.
            val visibleHeight = if (state.targetValue == SheetValue.Expanded) largeHeight else mediumHeight - 21.dp
            BottomSheetScaffold(
                scaffoldState = rememberBottomSheetScaffoldState(bottomSheetState = state),
                containerColor = androidx.compose.ui.graphics.Color.Transparent,
                sheetContainerColor = MaterialTheme.colorScheme.background,
                sheetContentColor = MaterialTheme.colorScheme.onSurface,
                sheetPeekHeight = mediumHeight,
                sheetShape = RoundedCornerShape(topStart = 40.dp, topEnd = 40.dp),
                sheetDragHandle = {
                    Box(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 12.dp), contentAlignment = Alignment.Center) {
                        Box(Modifier.width(58.dp).height(3.dp).background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .5f), CircleShape))
                    }
                },
                sheetContent = {
                    Column(Modifier.fillMaxWidth().height(largeHeight)) {
                        Column(modifier.fillMaxWidth().height(visibleHeight).navigationBarsPadding(), content = content)
                    }
                }
            ) {
                Box(Modifier.fillMaxSize().clickable(onClick = onDismissRequest))
            }
        }
    }
}
