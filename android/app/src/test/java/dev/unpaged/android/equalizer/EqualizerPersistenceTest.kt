package dev.unpaged.android.equalizer

import dev.unpaged.android.library.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class EqualizerPersistenceTest {
    private fun withStore(context: android.content.Context, block: (SQLiteLibraryStore) -> Unit) {
        val store = SQLiteLibraryStore(context)
        try { block(store) } finally { store.close() }
    }
    @Test fun codecNormalizesAndFallsBackOnInvalidData() {
        val c = EqualizerConfiguration(true, EqualizerPreset.custom, 30.0, listOf(-50.0, 50.0))
        assertEquals(listOf(-12.0, 12.0, 0.0, 0.0, 0.0), EqualizerConfiguration.decode(c.json()).bandGainsDB)
        assertEquals(12.0, EqualizerConfiguration.decode(c.json()).preampDB, 0.0)
        assertEquals(EqualizerConfiguration(), EqualizerConfiguration.decode("broken"))
        assertEquals(EqualizerConfiguration(), EqualizerConfiguration.decode(null))
    }
    @Test fun manualPresetAndResetKeepIosSemantics() {
        val c = EqualizerConfiguration(true, preampDB = 5.0).apply(EqualizerPreset.voiceBoost)
        assertEquals(c, c.apply(EqualizerPreset.custom).copy(preset = EqualizerPreset.voiceBoost))
        assertEquals(EqualizerPreset.custom, c.band(2, 9.0).preset)
        assertEquals(EqualizerConfiguration(true), c.reset())
    }
    @Test fun perBookConfigurationSurvivesReopenWithoutTouchingProgressOrOtherBooks() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("library.db")
        val eq = EqualizerConfiguration(true, preampDB = 6.0).apply(EqualizerPreset.podcast)
        withStore(context) { store ->
            store.insert(LibraryBook("a", "A", "Author", emptyList(), currentPositionMs = 42))
            store.insert(LibraryBook("b", "B", "Author", emptyList()))
            store.updateEqualizer("a", eq.json())
        }
        withStore(context) { store ->
            val a = store.books().first { it.id == "a" }
            assertEquals(eq, EqualizerConfiguration.decode(a.equalizerJson))
            assertEquals(42L, a.currentPositionMs)
            assertNull(store.books().first { it.id == "b" }.equalizerJson)
        }
    }
}
