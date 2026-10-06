package dev.unpaged.android.equalizer

import org.json.JSONArray
import org.json.JSONObject

/** Immutable snapshots are shared with the audio thread, never mutable slider state. */
data class EqualizerConfiguration(
    val isEnabled: Boolean = false, val preset: EqualizerPreset = EqualizerPreset.flat,
    val preampDB: Double = 0.0, val bandGainsDB: List<Double> = List(5) { 0.0 },
) {
    fun normalized() = copy(preampDB = finite(preampDB).coerceIn(0.0, 12.0),
        bandGainsDB = List(5) { finite(bandGainsDB.getOrElse(it) { 0.0 }).coerceIn(-12.0, 12.0) })
    fun apply(preset: EqualizerPreset) = copy(preset = preset,
        bandGainsDB = if (preset == EqualizerPreset.custom) bandGainsDB else preset.gains)
    fun band(index: Int, gain: Double) = copy(preset = EqualizerPreset.custom,
        bandGainsDB = bandGainsDB.mapIndexed { i, old -> if (i == index) gain else old }).normalized()
    fun reset() = EqualizerConfiguration(isEnabled = isEnabled)
    fun json(): String = normalized().let { c -> JSONObject().put("isEnabled", c.isEnabled)
        .put("preset", c.preset.name).put("preampDB", c.preampDB)
        .put("bandGainsDB", JSONArray(c.bandGainsDB)).toString() }
    companion object {
        val frequencies = listOf(60.0, 230.0, 910.0, 3600.0, 14000.0)
        val labels = listOf("60", "230", "910", "3.6k", "14k")
        private fun finite(value: Double) = value.takeIf { it.isFinite() } ?: 0.0
        fun decode(json: String?): EqualizerConfiguration = runCatching {
            val o = JSONObject(json ?: return EqualizerConfiguration())
            val bands = o.getJSONArray("bandGainsDB")
            EqualizerConfiguration(o.getBoolean("isEnabled"), EqualizerPreset.valueOf(o.getString("preset")),
                o.getDouble("preampDB"), List(bands.length()) { bands.getDouble(it) }).normalized()
        }.getOrDefault(EqualizerConfiguration())
    }
}

enum class EqualizerPreset(val title: String, val gains: List<Double>) {
    flat("Flat", listOf(0.0, 0.0, 0.0, 0.0, 0.0)),
    voiceBoost("Voice Boost", listOf(-2.0, 0.0, 4.0, 5.0, 1.0)),
    bassBoost("Bass Boost", listOf(6.0, 4.0, 0.0, -1.0, -1.0)),
    trebleBoost("Treble Boost", listOf(-2.0, -1.0, 0.0, 3.0, 5.0)),
    podcast("Podcast", listOf(-3.0, 1.0, 3.0, 4.0, 2.0)),
    custom("Custom", List(5) { 0.0 }),
}
