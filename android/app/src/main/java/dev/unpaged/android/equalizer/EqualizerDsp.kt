package dev.unpaged.android.equalizer

import kotlin.math.*

/** RBJ peaking filter, normalized a0; bands at/above Nyquist are bypassed. */
data class Biquad(val b0: Double = 1.0, val b1: Double = 0.0, val b2: Double = 0.0,
                  val a1: Double = 0.0, val a2: Double = 0.0) {
    companion object {
        fun peaking(frequency: Double, gainDB: Double, sampleRate: Int, q: Double = 1.0): Biquad {
            require(sampleRate > 0 && q > 0 && q.isFinite())
            if (frequency <= 0 || frequency >= sampleRate / 2.0 || !frequency.isFinite() || !gainDB.isFinite()) return Biquad()
            val a = 10.0.pow(gainDB.coerceIn(-12.0, 12.0) / 40)
            val w = 2 * PI * frequency / sampleRate
            val alpha = sin(w) / (2 * q)
            val a0 = 1 + alpha / a
            return Biquad((1 + alpha * a) / a0, -2 * cos(w) / a0, (1 - alpha * a) / a0,
                -2 * cos(w) / a0, (1 - alpha / a) / a0)
        }
    }
}

/** Linear below the knee; smoothly approaches full scale without clipping. */
fun softLimit(sample: Double): Double {
    if (!sample.isFinite()) return 0.0
    val magnitude = abs(sample)
    return if (magnitude <= 0.9) sample else sign(sample) * (0.9 + 0.1 * (magnitude - 0.9) / (0.1 + magnitude - 0.9))
}

class EqualizerDsp(private val sampleRate: Int, private val channels: Int) {
    private var config = EqualizerConfiguration()
    private var coefficients = List(5) { Biquad() }
    private val z1 = Array(channels) { DoubleArray(5) }
    private val z2 = Array(channels) { DoubleArray(5) }
    private var amplifier = 1.0
    fun configure(value: EqualizerConfiguration) {
        config = value.normalized()
        coefficients = EqualizerConfiguration.frequencies.mapIndexed { i, hz -> Biquad.peaking(hz, config.bandGainsDB[i], sampleRate) }
        amplifier = 10.0.pow(config.preampDB / 20)
        clear()
    }
    fun clear() { z1.forEach { it.fill(0.0) }; z2.forEach { it.fill(0.0) } }
    fun process(sample: Double, channel: Int): Double {
        if (!config.isEnabled) return sample
        var result = sample * amplifier
        if (config.isEnabled) coefficients.forEachIndexed { i, c ->
            val output = c.b0 * result + z1[channel][i]
            z1[channel][i] = c.b1 * result - c.a1 * output + z2[channel][i]
            z2[channel][i] = c.b2 * result - c.a2 * output
            result = output
        }
        return softLimit(result)
    }
}
