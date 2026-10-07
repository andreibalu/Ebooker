package dev.unpaged.android.ai

import android.content.Context
import android.os.StatFs
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** Download-only transport. This class never receives audio, prompts, or transcripts. */
class SpeechModelStore(context: Context) {
    companion object {
        const val SIZE = 59_707_625L
        const val SHA256 = "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898"
        const val REVISION = "5359861c739e955e79d9a303bcbc70fb988958b1"
        const val LICENSE = "https://github.com/openai/whisper/blob/main/LICENSE"
        const val MODEL_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/$REVISION/ggml-base-q5_1.bin"
        fun verified(file: File): Boolean = file.isFile && file.length() == SIZE &&
            file.inputStream().use { stream ->
                val digest = MessageDigest.getInstance("SHA-256")
                val bytes = ByteArray(65536)
                while (true) { val n = stream.read(bytes); if (n < 0) break; digest.update(bytes, 0, n) }
                digest.digest().joinToString("") { "%02x".format(it) } == SHA256
            }
    }
    private val directory = File(context.noBackupFilesDir, "speech-model").apply { mkdirs() }
    val model = File(directory, "ggml-base-q5_1.bin")
    private val partial = File(directory, "model.part")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var job: Job? = null
    private val mutableState = MutableStateFlow(ModelState())
    val state = mutableState.asStateFlow()
    init { scope.launch { partial.delete(); refresh() } }
    suspend fun refresh() = withContext(Dispatchers.IO) { mutableState.value = mutableState.value.copy(installed = verified(model)) }
    fun hasSpace() = StatFs(directory.path).availableBytes >= SIZE + 16 * 1024 * 1024
    fun downloadWithConsent() {
        if (job?.isActive == true) return
        job = scope.launch {
            if (!hasSpace()) { mutableState.value = ModelState(error = "Not enough free space. Free at least 77 MB and try again."); return@launch }
            mutableState.value = ModelState(downloading = true)
            var connection: HttpURLConnection? = null
            try {
                connection = URL(MODEL_URL).openConnection() as HttpURLConnection
                connection.connectTimeout = 15000; connection.readTimeout = 15000
                check(connection.responseCode == 200)
                connection.inputStream.use { input -> partial.outputStream().use { output ->
                    val bytes = ByteArray(65536); var total = 0L
                    while (true) {
                        ensureActive(); val n = input.read(bytes); if (n < 0) break
                        total += n; check(total <= SIZE); output.write(bytes, 0, n)
                        mutableState.value = ModelState(downloading = true, bytes = total)
                    }
                } }
                ensureActive(); check(verified(partial)) { "Invalid checksum" }
                check(partial.renameTo(model)); mutableState.value = ModelState(installed = true)
            } catch (e: CancellationException) { mutableState.value = ModelState(); throw e }
            catch (_: Exception) { mutableState.value = ModelState(error = "Couldn't download the speech model. Please try again.") }
            finally { connection?.disconnect(); partial.delete() }
        }
    }
    fun cancel() { job?.cancel() }
    suspend fun delete() { job?.cancelAndJoin(); withContext(Dispatchers.IO) { model.delete(); partial.delete(); mutableState.value = ModelState() } }
}
data class ModelState(val installed: Boolean = false, val downloading: Boolean = false, val bytes: Long = 0, val error: String? = null)
