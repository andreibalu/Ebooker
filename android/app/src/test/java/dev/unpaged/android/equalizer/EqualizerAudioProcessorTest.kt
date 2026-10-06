package dev.unpaged.android.equalizer

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@androidx.annotation.OptIn(UnstableApi::class)
class EqualizerAudioProcessorTest {
    private fun input(vararg samples: Short): ByteBuffer = ByteBuffer.allocateDirect(samples.size * 2)
        .order(ByteOrder.nativeOrder()).apply { samples.forEach { putShort(it) }; flip() }
    @Test fun disabledPcmIsBitExactAndRemainsActiveForLiveChanges() {
        val processor = EqualizerAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(48000, 2, C.ENCODING_PCM_16BIT)); processor.flush()
        assertTrue(processor.isActive)
        val samples = shortArrayOf(-32768, 32767, -1234, 5678, 0, 1)
        processor.queueInput(input(*samples))
        val output = processor.output
        assertEquals(samples.toList(), List(samples.size) { output.short })
        processor.reset()
    }
    @Test fun boostAndToggleApplyToNextBufferWithoutFlushOrConfigure() {
        val processor = EqualizerAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(8000, 1, C.ENCODING_PCM_16BIT)); processor.flush()
        processor.queueInput(input(4096)); assertEquals(4096, processor.output.short.toInt())
        processor.configuration = EqualizerConfiguration(isEnabled = true, preampDB = 6.0)
        processor.queueInput(input(4096)); assertEquals(8172, processor.output.short.toInt())
        processor.configuration = processor.configuration.copy(isEnabled = false)
        processor.queueInput(input(4096)); assertEquals(4096, processor.output.short.toInt())
        processor.queueEndOfStream(); assertTrue(processor.isEnded)
    }
    @Test fun rejectsUnsupportedFormatAndResetBeforeConfigureIsSafe() {
        val processor = EqualizerAudioProcessor()
        processor.reset()
        assertThrows(AudioProcessor.UnhandledAudioFormatException::class.java) {
            processor.configure(AudioProcessor.AudioFormat(48000, 1, C.ENCODING_PCM_FLOAT))
        }
    }
}
