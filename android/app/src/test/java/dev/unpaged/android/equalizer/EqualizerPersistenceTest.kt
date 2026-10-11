package dev.unpaged.android.equalizer

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class EqualizerPersistenceTest {
    @Test fun codecNormalizesAndFallsBackOnInvalidData() {
        val c = EqualizerConfiguration(true, EqualizerPreset.custom, 30.0, listOf(-50.0, 50.0))
        assertEquals(listOf(-12.0, 12.0, 0.0, 0.0, 0.0), EqualizerConfiguration.decode(c.json()).bandGainsDB)
        assertEquals(12.0, EqualizerConfiguration.decode(c.json()).preampDB, 0.0)
        assertEquals(EqualizerConfiguration(), EqualizerConfiguration.decode("broken"))
        assertEquals(EqualizerConfiguration(), EqualizerConfiguration.decode(null))
    }
}
