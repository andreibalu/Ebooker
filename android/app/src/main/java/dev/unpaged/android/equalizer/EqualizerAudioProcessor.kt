package dev.unpaged.android.equalizer

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer

/** Always participates in PCM16 pipeline so live toggles need no sink/player restart. */
@androidx.annotation.OptIn(UnstableApi::class)
class EqualizerAudioProcessor : BaseAudioProcessor() {
    @Volatile var configuration = EqualizerConfiguration()
    private var applied: EqualizerConfiguration? = null
    private var dsp: EqualizerDsp? = null
    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        return inputAudioFormat
    }
    override fun onFlush() {
        dsp = if (inputAudioFormat.sampleRate > 0 && inputAudioFormat.channelCount > 0)
            EqualizerDsp(inputAudioFormat.sampleRate, inputAudioFormat.channelCount) else null
        applied = null
    }
    override fun onReset() { dsp = null; applied = null }
    override fun queueInput(inputBuffer: ByteBuffer) {
        val processor = dsp ?: return
        val snapshot = configuration
        if (applied != snapshot) { processor.configure(snapshot); applied = snapshot }
        val output = replaceOutputBuffer(inputBuffer.remaining())
        val channels = inputAudioFormat.channelCount
        while (inputBuffer.remaining() >= channels * 2) {
            for (channel in 0 until channels) {
                val sample = inputBuffer.short.toDouble() / 32768.0
                val processed = processor.process(sample, channel)
                output.putShort((processed * 32768).toInt().coerceIn(-32768, 32767).toShort())
            }
        }
        output.flip()
    }
}
