package dev.unpaged.android.equalizer

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EqualizerSheet(config: EqualizerConfiguration, update: (EqualizerConfiguration) -> Unit, dismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = dismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = MaterialTheme.colorScheme.background,
        modifier = Modifier.semantics { testTagsAsResourceId = true }.testTag("equalizer")) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.width(60.dp))
            Text("Equalizer", Modifier.weight(1f), fontWeight = FontWeight.SemiBold, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            TextButton(onClick = dismiss, modifier = Modifier.testTag("equalizer.done")) { Text("Done") }
        }
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).testTag("equalizer.scroll").navigationBarsPadding().padding(horizontal = 20.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            EqCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { EqTitle("Equalizer"); EqSubtitle("Adjust tone and boost quiet books") }
                    Switch(config.isEnabled, { update(config.copy(isEnabled = it)) }, Modifier.testTag("equalizer.enabled"), colors = SwitchDefaults.colors(checkedThumbColor = androidx.compose.ui.graphics.Color.White, checkedTrackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .7f), uncheckedTrackColor = MaterialTheme.colorScheme.surfaceVariant, uncheckedThumbColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .4f), uncheckedBorderColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .2f)))
                }
            }
            EqCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { EqTitle("Volume Boost"); EqSubtitle("Override the max volume for quiet books") }
                    Text("+${config.preampDB.toInt()} dB", fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                }
                Slider(config.preampDB.toFloat(), { update(config.copy(preampDB = it.toDouble())) }, valueRange = 0f..12f, steps = 11, modifier = Modifier.testTag("equalizer.preamp"), colors = eqSliderColors())
                if (config.preampDB > 9) Text("⚠ High boost may distort very quiet passages.", fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
            }
            EqCard(config.isEnabled) {
                EqTitle("Preset")
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    EqualizerPreset.entries.forEach { preset ->
                        FilterChip(selected = config.preset == preset, onClick = { update(config.apply(preset)) }, enabled = config.isEnabled,
                            colors = FilterChipDefaults.filterChipColors(selectedContainerColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .1f), selectedLabelColor = MaterialTheme.colorScheme.onSurface),
                            label = { Text(preset.title, fontSize = 14.sp) }, shape = RoundedCornerShape(14.dp),
                            modifier = Modifier.testTag("equalizer.preset.${preset.name}"))
                    }
                }
            }
            EqCard(config.isEnabled) {
                EqTitle("Manual EQ")
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    config.bandGainsDB.forEachIndexed { index, gain ->
                        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(if (gain > 0) "+${gain.toInt()}" else "${gain.toInt()}", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Slider(gain.toFloat(), { update(config.band(index, it.toDouble())) }, enabled = config.isEnabled, valueRange = -12f..12f, steps = 23,
                                colors = eqSliderColors(), modifier = Modifier.testTag("equalizer.band.$index")
                                    .size(40.dp, 180.dp)
                                    .graphicsLayer { rotationZ = -90f }
                                    .layout { measurable, constraints ->
                                        val placeable = measurable.measure(constraints.copy(minWidth = constraints.minHeight, maxWidth = constraints.maxHeight, minHeight = constraints.minWidth, maxHeight = constraints.maxWidth))
                                        layout(placeable.height, placeable.width) { placeable.place((placeable.height - placeable.width) / 2, (placeable.width - placeable.height) / 2) }
                                    })
                            Text(EqualizerConfiguration.labels[index], fontSize = 11.sp)
                            Text("Hz", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            TextButton(onClick = { update(config.reset()) }, modifier = Modifier.fillMaxWidth().testTag("equalizer.reset")) { Text("Reset to Flat", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}
@Composable
private fun EqCard(enabled: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    Surface(shape = RoundedCornerShape(16.dp), shadowElevation = 2.dp,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .08f)), modifier = Modifier.alpha(if (enabled) 1f else .4f)) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
    }
}
@Composable private fun EqTitle(text: String) { Text(text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
@Composable private fun EqSubtitle(text: String) { Text(text, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
@Composable private fun eqSliderColors() = SliderDefaults.colors(
    activeTrackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .7f),
    inactiveTrackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .12f),
    activeTickColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .7f),
    inactiveTickColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .12f),
    thumbColor = MaterialTheme.colorScheme.surface,
    disabledActiveTrackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .2f),
    disabledInactiveTrackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .08f),
    disabledActiveTickColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .2f),
    disabledInactiveTickColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .08f))
