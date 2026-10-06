package dev.unpaged.android.equalizer

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class EqualizerDspTest {
    @Test fun zeroGainIsIdentityAcrossRatesAndBands() {
        for (rate in listOf(8000, 44100, 48000, 96000)) {
            val dsp = EqualizerDsp(rate, 2)
            dsp.configure(EqualizerConfiguration(isEnabled = true))
            repeat(2000) { i -> val x = .2 * sin(i * .1); assertEquals(x, dsp.process(x, 0), 1e-9) }
        }
    }
    @Test fun centerFrequencyHasRequestedGain() {
        for (hz in EqualizerConfiguration.frequencies) for (gain in listOf(-12.0, -6.0, 6.0, 12.0)) {
            val c = Biquad.peaking(hz, gain, 48000)
            val w = 2 * PI * hz / 48000
            fun magnitude(x0: Double, x1: Double, x2: Double) = hypot(x0 + x1 * cos(w) + x2 * cos(2*w), -x1 * sin(w) - x2 * sin(2*w))
            val db = 20 * log10(magnitude(c.b0, c.b1, c.b2) / magnitude(1.0, c.a1, c.a2))
            assertEquals(gain, db, 1e-8)
        }
    }
    @Test fun unsupportedNyquistBandsAreIdentity() {
        assertEquals(Biquad(), Biquad.peaking(14000.0, 12.0, 8000))
        assertEquals(Biquad(), Biquad.peaking(4000.0, 12.0, 8000))
    }
    @Test fun disabledBypassesBoostAndToneExactly() {
        val dsp = EqualizerDsp(48000, 1)
        dsp.configure(EqualizerConfiguration(preampDB = 12.0, bandGainsDB = List(5) { 12.0 }))
        for (x in listOf(-1.0, -.5, 0.0, .5, 1.0)) assertEquals(x, dsp.process(x, 0), 0.0)
    }
    @Test fun limiterIsOddContinuousMonotonicAndBounded() {
        assertEquals(.9, softLimit(.9), 0.0)
        assertEquals(.5, softLimit(.5), 0.0)
        var previous = 0.0
        repeat(10000) { i ->
            val x = i / 100.0
            val y = softLimit(x)
            assertTrue(y >= previous && y <= 1.0)
            assertEquals(-y, softLimit(-x), 1e-12)
            previous = y
        }
        assertEquals(0.0, softLimit(Double.NaN), 0.0)
    }
    @Test fun filtersHaveIndependentChannelHistoryAndResetBetweenStreams() {
        val dsp = EqualizerDsp(48000, 2)
        val config = EqualizerConfiguration(isEnabled = true).apply(EqualizerPreset.voiceBoost)
        dsp.configure(config)
        assertTrue(dsp.process(.2, 0) != .2)
        assertEquals(0.0, dsp.process(0.0, 1), 0.0)
        dsp.clear()
        assertEquals(0.0, dsp.process(0.0, 0), 0.0)
    }
    @Test fun worstCaseBoostImpulseRemainsFiniteAndBounded() {
        for (rate in listOf(8000, 44100, 48000)) {
            val dsp = EqualizerDsp(rate, 1)
            dsp.configure(EqualizerConfiguration(isEnabled = true, preampDB = 12.0, bandGainsDB = List(5) { 12.0 }))
            repeat(20000) { i -> val y = dsp.process(if (i == 0) 1.0 else 0.0, 0); assertTrue(y.isFinite() && abs(y) <= 1) }
        }
    }
}
