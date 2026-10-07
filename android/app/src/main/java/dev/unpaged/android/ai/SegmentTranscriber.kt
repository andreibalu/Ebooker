package dev.unpaged.android.ai

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.nio.ByteOrder
import java.util.Locale

interface SegmentTranscriber { suspend fun transcribe(file: File, startMs: Long, endMs: Long): String }
object WhisperNative {
    init { System.loadLibrary("unpaged_whisper") }
    external fun transcribe(model: String, samples: FloatArray, language: String): String
    external fun cancel()
}
class WhisperTranscriber(private val models: SpeechModelStore) : SegmentTranscriber {
    private val mutex = Mutex()
    override suspend fun transcribe(file: File, startMs: Long, endMs: Long): String = mutex.withLock {
        withContext(Dispatchers.IO) {
            require(endMs > startMs && endMs - startMs <= 200_000)
            check(SpeechModelStore.verified(models.model)) { "Speech model is not installed." }
            val started = System.nanoTime()
            val pcm = PcmDecoder.decode(file, startMs, endMs)
            val caller = currentCoroutineContext()[Job]
            val text = withContext(Dispatchers.Default) {
                withContext(NonCancellable) {
                    // The cancellation watcher aborts native inference; joining keeps buffers alive until it returns.
                    val watcher = CoroutineScope(Dispatchers.IO).launch { while (caller?.isActive != false) delay(50); WhisperNative.cancel() }
                    try { WhisperNative.transcribe(models.model.path, pcm, Locale.getDefault().language).trim() }
                    finally { watcher.cancel() }
                }
            }
            currentCoroutineContext().ensureActive()
            Log.i("UnpagedASR", "windowMs=${endMs-startMs} elapsedMs=${(System.nanoTime()-started)/1_000_000}")
            check(text.isNotEmpty()) { "Could not transcribe audio." }; text
        }
    }
}

/** Decode only the requested range, average channels, then resample to 16 kHz mono. */
object PcmDecoder {
    suspend fun decode(file: File, startMs: Long, endMs: Long): FloatArray {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(file.path)
            val track = (0 until extractor.trackCount).first { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true }
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            if (format.getString(MediaFormat.KEY_MIME) == "audio/raw") return decodeRaw(extractor, format, startMs, endMs)
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            val decoder = MediaCodec.createDecoderByType(requireNotNull(format.getString(MediaFormat.KEY_MIME)))
            codec = decoder; decoder.configure(format, null, null, 0); decoder.start()
            extractor.seekTo(startMs * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val info = MediaCodec.BufferInfo()
            val output = ArrayList<Float>()
            var inputEnded = false; var outputEnded = false
            var nextTime = startMs * 1000.0
            var previous = 0f
            var previousTime = Double.NaN
            while (!outputEnded) {
                currentCoroutineContext().ensureActive()
                if (!inputEnded) {
                    val index = decoder.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val time = extractor.sampleTime
                        val size = if (time < 0 || time >= endMs * 1000) -1 else extractor.readSampleData(requireNotNull(decoder.getInputBuffer(index)), 0)
                        if (size < 0) { decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputEnded = true }
                        else { decoder.queueInputBuffer(index, 0, size, time, 0); extractor.advance() }
                    }
                }
                val index = decoder.dequeueOutputBuffer(info, 10000)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val out = decoder.outputFormat; rate = out.getInteger(MediaFormat.KEY_SAMPLE_RATE); channels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    encoding = if (out.containsKey(MediaFormat.KEY_PCM_ENCODING)) out.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                    check(encoding == AudioFormat.ENCODING_PCM_16BIT || encoding == AudioFormat.ENCODING_PCM_FLOAT)
                } else if (index >= 0) {
                    val buffer = requireNotNull(decoder.getOutputBuffer(index)).order(ByteOrder.LITTLE_ENDIAN)
                    buffer.position(info.offset); buffer.limit(info.offset + info.size)
                    val sampleBytes = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
                    val frames = info.size / (sampleBytes * channels)
                    for (frame in 0 until frames) {
                        val time = info.presentationTimeUs + frame * 1_000_000.0 / rate
                        var mono = 0f
                        repeat(channels) { mono += if (sampleBytes == 4) buffer.float else buffer.short.toFloat() / 32768f }; mono /= channels
                        if (previousTime.isNaN()) { previous = mono; previousTime = time }
                        while (nextTime <= time && nextTime < endMs * 1000) {
                            if (nextTime >= previousTime) {
                                val fraction = if (time == previousTime) 1.0 else (nextTime - previousTime) / (time - previousTime)
                                output.add((previous + (mono - previous) * fraction).toFloat())
                            }
                            nextTime += 62.5
                        }
                        previous = mono; previousTime = time
                    }
                    outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    decoder.releaseOutputBuffer(index, false)
                }
            }
            check(output.isNotEmpty()); return output.toFloatArray()
        } finally { codec?.runCatching { stop(); release() }; extractor.release() }
    }
    // WAV's PCM track is already decoded; Android has no required audio/raw MediaCodec.
    private suspend fun decodeRaw(extractor: MediaExtractor, format: MediaFormat, startMs: Long, endMs: Long): FloatArray {
        val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val encoding = if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) format.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
        check(rate > 0 && channels > 0)
        check(encoding == AudioFormat.ENCODING_PCM_16BIT || encoding == AudioFormat.ENCODING_PCM_FLOAT)
        val bytes = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
        val buffer = java.nio.ByteBuffer.allocate(1024 * 1024).order(ByteOrder.LITTLE_ENDIAN)
        val output = ArrayList<Float>()
        var nextTime = startMs * 1000.0
        var previous = 0f
        var previousTime = Double.NaN
        extractor.seekTo(startMs * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        while (extractor.sampleTime >= 0 && extractor.sampleTime < endMs * 1000) {
            currentCoroutineContext().ensureActive()
            val baseTime = extractor.sampleTime
            buffer.clear()
            val size = extractor.readSampleData(buffer, 0)
            if (size < 0) break
            buffer.position(0); buffer.limit(size)
            repeat(size / (bytes * channels)) { frame ->
                val time = baseTime + frame * 1_000_000.0 / rate
                var mono = 0f
                repeat(channels) { mono += if (bytes == 4) buffer.float else buffer.short.toFloat() / 32768f }; mono /= channels
                if (previousTime.isNaN()) { previous = mono; previousTime = time }
                while (nextTime <= time && nextTime < endMs * 1000) {
                    if (nextTime >= previousTime) {
                        val fraction = if (time == previousTime) 1.0 else (nextTime - previousTime) / (time - previousTime)
                        output.add((previous + (mono - previous) * fraction).toFloat())
                    }
                    nextTime += 62.5
                }
                previous = mono; previousTime = time
            }
            extractor.advance()
        }
        check(output.isNotEmpty()); return output.toFloatArray()
    }

}
