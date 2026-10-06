package dev.unpaged.android.abs

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import dev.unpaged.android.library.*
import java.util.UUID

data class ABSSummary(val server: String, val username: String?, val apiKey: Boolean)
data class ABSLibrary(val id: String, val name: String)
data class ABSItem(val id: String, val title: String, val author: String, val narrator: String,
    val description: String, val durationMs: Long, val hasCover: Boolean, val tracks: List<LibraryTrack>,
    val chapters: List<ABSChapter>, val addedAt: Long, val subtitle: String = "")
data class ABSChapter(val title: String, val startMs: Long, val endMs: Long)
data class ABSProgress(val currentMs: Long, val finished: Boolean, val hidden: Boolean = false, val updated: Long = 0)
class ABSResponse(val status: Int, val bytes: ByteArray)
fun interface ABSTransport {
    fun send(url: String, method: String, headers: Map<String, String>, body: ByteArray?): ABSResponse
}
class ABSHttpTransport(private val online: () -> Boolean = { true }) : ABSTransport {
    override fun send(url: String, method: String, headers: Map<String, String>, body: ByteArray?): ABSResponse {
        if (!online()) throw ABSException(ABSFailure.OFFLINE)
        try {
            val connection = URI(url).toURL().openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects = false // Never forward credentials across redirects.
                connection.connectTimeout = 20_000; connection.readTimeout = 20_000
                connection.requestMethod = method
                headers.forEach { (key, value) -> connection.setRequestProperty(key, value) }
                if (body != null) {
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.doOutput = true; connection.outputStream.use { it.write(body) }
                }
                val status = connection.responseCode
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                return ABSResponse(status, stream?.use { it.readBytes() } ?: byteArrayOf())
            } finally { connection.disconnect() }
        } catch (error: ABSException) { throw error }
        catch (_: Exception) { throw ABSException(ABSFailure.UNREACHABLE_SERVER) }
    }
}

/** One process owner for connection changes and shared refresh. All network/disk work is on IO. */
class ABSClient(private val credentials: ABSCredentialStore, private val transport: ABSTransport, private val coverRoot: java.io.File? = null) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Any()
    private var active: ABSConnection? = null
    private var initialized = false
    private var generation = 0
    private var refreshAccess: String? = null
    private var refreshTask: Deferred<ABSConnection>? = null
    private val mutableSummary = MutableStateFlow<ABSSummary?>(null)
    val summary = mutableSummary.asStateFlow()
    suspend fun reload() = withContext(Dispatchers.IO) {
        synchronized(lock) {
            if (!initialized) {
                active = credentials.load(); initialized = true; publish()
            }
        }
    }
    private fun publish() { mutableSummary.value = active?.let { ABSSummary(it.server, it.username, it.apiKey) } }
    private fun required(): ABSConnection = synchronized(lock) { active ?: throw ABSException(ABSFailure.NOT_CONNECTED) }
    private fun replace(candidate: ABSConnection?, expectedGeneration: Int? = null) = synchronized(lock) {
        if (expectedGeneration != null && generation != expectedGeneration) throw ABSException(ABSFailure.NOT_CONNECTED)
        if (candidate == null) credentials.clear() else credentials.save(candidate)
        active = candidate; generation++; initialized = true; refreshTask?.cancel(); refreshTask = null; refreshAccess = null; publish()
    }
    suspend fun disconnect() = withContext(Dispatchers.IO) { replace(null) }
    private fun endpoint(base: String, path: String) = base.trimEnd('/') + "/" + path
    private fun send(connection: ABSConnection?, base: String, path: String, method: String = "GET",
        body: JSONObject? = null, headers: Map<String, String> = emptyMap()): ByteArray {
        val auth = connection?.let { mapOf("Authorization" to "Bearer ${it.access}") } ?: emptyMap()
        val response = transport.send(endpoint(base, path), method, headers + auth, body?.toString()?.toByteArray(Charsets.UTF_8))
        if (response.status !in 200..299) throw ABSRules.httpFailure(response.status, path.substringBefore('?'), connection?.takeIf { it.apiKey }?.access)
        return response.bytes
    }
    private fun json(bytes: ByteArray): JSONObject = try { JSONObject(String(bytes, Charsets.UTF_8)) }
        catch (_: Exception) { throw ABSException(ABSFailure.UNREADABLE_RESPONSE) }
    private fun loginConnection(server: String, bytes: ByteArray, username: String?): ABSConnection {
        val user = json(bytes).optJSONObject("user") ?: throw ABSException(ABSFailure.NOT_ABS_SERVER)
        val access = user.optString("accessToken"); val refresh = user.optString("refreshToken")
        if (access.isBlank() || refresh.isBlank()) throw ABSException(ABSFailure.NOT_ABS_SERVER)
        return ABSConnection(server, access, refresh, user.optionalText("username").ifBlank { username })
    }
    suspend fun login(server: String, username: String, password: String) = withContext(Dispatchers.IO) {
        reload()
        val version = synchronized(lock) { generation }
        val base = ABSRules.serverURL(server)
        val candidate = loginConnection(base, send(null, base, "login", "POST",
            JSONObject().put("username", username.trim()).put("password", password), mapOf("x-return-tokens" to "true")), username.trim())
        // Login-shaped replies alone are insufficient: verify the ABS authorization endpoint.
        val authorized = json(send(candidate, base, "api/authorize", "POST"))
        if (authorized.optJSONObject("user") == null) throw ABSException(ABSFailure.NOT_ABS_SERVER)
        replace(candidate, version)
    }
    suspend fun apiKey(server: String, key: String) = withContext(Dispatchers.IO) {
        reload()
        val version = synchronized(lock) { generation }
        val base = ABSRules.serverURL(server)
        val candidate = ABSConnection(base, key.trim(), null, null)
        val user = json(send(candidate, base, "api/authorize", "POST")).optJSONObject("user") ?: throw ABSException(ABSFailure.NOT_ABS_SERVER)
        replace(ABSConnection(base, candidate.access, null, user.optionalText("username").ifBlank { null }), version)
    }
    private suspend fun refresh(failed: ABSConnection): ABSConnection {
        val task = synchronized(lock) {
            val current = required()
            if (current.server != failed.server) throw ABSException(ABSFailure.NOT_CONNECTED)
            if (current.access != failed.access) return current
            if (current.refresh == null) throw ABSException(ABSFailure.BAD_CREDENTIALS)
            if (refreshAccess == failed.access) refreshTask!! else {
                val version = generation
                refreshAccess = failed.access
                scope.async(start = CoroutineStart.LAZY) {
                    val renewed = loginConnection(current.server, send(null, current.server, "auth/refresh", "POST",
                        headers = mapOf("x-refresh-token" to current.refresh)), current.username)
                    synchronized(lock) {
                        if (version != generation || active !== current) throw ABSException(ABSFailure.NOT_CONNECTED)
                        credentials.save(renewed); active = renewed; publish()
                    }
                    renewed
                }.also { task ->
                    refreshTask = task
                    task.invokeOnCompletion {
                        synchronized(lock) { if (refreshTask === task) { refreshTask = null; refreshAccess = null } }
                    }
                    task.start()
                }
            }
        }
        return task.await()
    }
    private suspend fun request(path: String, method: String = "GET", body: JSONObject? = null): ByteArray = withContext(Dispatchers.IO) {
        reload()
        val connection = required()
        try { send(connection, connection.server, path, method, body) }
        catch (error: ABSException) {
            if (error.failure != ABSFailure.EXPIRED_TOKEN || connection.apiKey) throw error
            val renewed = refresh(connection)
            send(renewed, renewed.server, path, method, body) // Exactly one retry.
        }
    }
    suspend fun playbackURL(stored: String): String = withContext(Dispatchers.IO) {
        reload()
        var connection = required()
        ABSRules.storedURL(stored, connection.server)
        if (!connection.apiKey && ABSRules.needsRefresh(connection.access)) connection = refresh(connection)
        synchronized(lock) {
            if (active !== connection) throw ABSException(ABSFailure.NOT_CONNECTED)
            ABSRules.appendToken(ABSRules.storedURL(stored, connection.server), connection.access)
        }
    }
    private fun segment(value: String) = URLEncoder.encode(value, "UTF-8").replace("+", "%20")
    suspend fun libraries(): List<ABSLibrary> {
        val array = json(request("api/libraries")).optJSONArray("libraries") ?: throw ABSException(ABSFailure.UNREADABLE_RESPONSE)
        return (0 until array.length()).map { array.getJSONObject(it) }.filter { it.optString("mediaType") == "book" }
            .map { ABSLibrary(it.getString("id"), it.getString("name")) }
    }
    suspend fun items(library: String): List<ABSItem> {
        val items = mutableListOf<ABSItem>(); var page = 0; var received = 0
        while (true) {
            val data = json(request("api/libraries/${segment(library)}/items?page=$page&limit=100&collapseseries=0"))
            val results = data.optJSONArray("results") ?: throw ABSException(ABSFailure.UNREADABLE_RESPONSE)
            if (data.optInt("page", -1) != page || data.optInt("limit") != 100 || data.optInt("total", -1) < 0) throw ABSException(ABSFailure.UNREADABLE_RESPONSE)
            for (i in 0 until results.length()) if (results.getJSONObject(i).optString("mediaType") == "book") items += parseItem(results.getJSONObject(i))
            received += results.length()
            if (received >= data.getInt("total")) return items.distinctBy { it.id }
            if (results.length() == 0) throw ABSException(ABSFailure.UNREADABLE_RESPONSE)
            page++
        }
    }
    suspend fun item(id: String): ABSItem = parseItem(json(request("api/items/${segment(id)}?expanded=1")))
    private fun parseItem(data: JSONObject): ABSItem {
        try {
            val media = data.getJSONObject("media"); val meta = media.getJSONObject("metadata")
            val array = media.optJSONArray("tracks")?.takeIf { it.length() > 0 } ?: media.optJSONArray("audioTracks") ?: JSONArray()
            val tracks = (0 until array.length()).map { array.getJSONObject(it) }.sortedBy { it.getInt("index") }.map {
                val name = it.getString("title")
                LibraryTrack(it.optJSONObject("metaTags")?.optString("tagTitle")?.takeIf { tag -> tag.isNotBlank() }
                    ?: name.substringBeforeLast('.').ifBlank { "Track ${it.getInt("index")}" }, name, "", (it.getDouble("duration").coerceAtLeast(0.0) * 1000).toLong(), "", it.getString("contentUrl"))
            }
            val chapters = media.optJSONArray("chapters") ?: JSONArray()
            return ABSItem(data.getString("id"), meta.getString("title").trim().ifBlank { "Untitled" },
                meta.optionalText("authorName").trim().ifBlank { "Unknown author" }, meta.optionalText("narratorName"), meta.optionalText("description"),
                (media.optDouble("duration", tracks.sumOf { it.durationMs } / 1000.0) * 1000).toLong(),
                media.optionalText("coverPath").isNotBlank(), tracks, (0 until chapters.length()).map { chapters.getJSONObject(it) }.map {
                    ABSChapter(it.optString("title"), (it.getDouble("start") * 1000).toLong(), (it.getDouble("end") * 1000).toLong()) }, data.optLong("addedAt"), meta.optionalText("subtitle"))
        } catch (_: Exception) { throw ABSException(ABSFailure.UNREADABLE_RESPONSE) }
    }
    suspend fun allProgress(): Map<String, ABSProgress> {
        val array = json(request("api/me/progress")).optJSONArray("mediaProgress") ?: return emptyMap()
        return (0 until array.length()).map { array.getJSONObject(it) }.associate { it.getString("libraryItemId") to parseProgress(it) }
    }
    private fun parseProgress(data: JSONObject) = ABSProgress((data.optDouble("currentTime") * 1000).toLong(), data.optBoolean("isFinished"),
        data.optBoolean("hideFromContinueListening"), data.optLong("lastUpdate"))
    suspend fun progress(id: String): ABSProgress? = try { parseProgress(json(request("api/me/progress/${segment(id)}"))) }
        catch (e: ABSException) { if (e.status == 404) null else throw e }
    suspend fun cover(id: String): Bitmap? = runCatching { val bytes = request("api/items/${segment(id)}/cover?width=400"); BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
    suspend fun startPlayback(id: String) {
        request("api/items/${segment(id)}/play", "POST", JSONObject().put("deviceInfo", JSONObject().put("clientName", "Unpaged"))
            .put("supportedMimeTypes", JSONArray(listOf("audio/mpeg", "audio/mp4", "audio/flac", "audio/ogg", "audio/wav"))))
    }
    suspend fun report(book: LibraryBook) {
        val id = book.absItemID ?: return
        if (book.durationMs <= 0) return
        val base = summary.value?.server ?: return
        if (book.tracks.any { it.remoteUrl?.let { url -> runCatching { ABSRules.storedURL(url, base) }.isFailure } != false }) return
        request("api/me/progress/${segment(id)}", "PATCH", ABSRules.progressPayload(book))
    }
    suspend fun add(item: ABSItem, store: LibraryStore): LibraryBook = withContext(Dispatchers.IO) {
        store.books().firstOrNull { it.absItemID == item.id }?.let { return@withContext it }
        val connection = required()
        if (item.tracks.isEmpty()) throw ABSException(ABSFailure.INVALID_MEDIA_URL)
        var offset = 0L
        val tracks = item.tracks.mapIndexed { index, track ->
            val chapter = if (item.chapters.size == item.tracks.size) item.chapters[index] else item.chapters.firstOrNull { kotlin.math.abs(it.startMs - offset) < 1500 }
            offset += track.durationMs
            track.copy(title = chapter?.title?.takeIf { it.isNotBlank() } ?: track.title,
                remoteUrl = ABSRules.storedURL(track.remoteUrl ?: "", connection.server))
        }
        val progress = progress(item.id)
        val position = ABSRules.position(progress?.currentMs ?: 0, tracks.map { it.durationMs })
        val book = LibraryBook(UUID.randomUUID().toString(), item.title, item.author, tracks, currentTrackIndex = position.first,
            currentPositionMs = position.second, highWaterMarkMs = progress?.currentMs ?: 0, isFinished = progress?.finished ?: false,
            isDownloaded = false, absItemID = item.id, absChaptersJson = JSONArray().apply { item.chapters.forEach {
                put(JSONObject().put("title", it.title).put("start", it.startMs).put("end", it.endMs)) } }.toString())
        val cover = if (item.hasCover && coverRoot != null) cover(item.id) else null
        val folder = coverRoot?.let { java.io.File(it, book.id) }
        try {
            if (cover != null && folder != null) {
                withContext(Dispatchers.IO) {
                    folder.mkdirs()
                    java.io.File(folder, "cover.png").outputStream().use { cover.compress(Bitmap.CompressFormat.PNG, 100, it) }
                }
            }
            synchronized(lock) { if (active !== connection) throw ABSException(ABSFailure.NOT_CONNECTED); store.insert(book) }
        } catch (error: Exception) { folder?.deleteRecursively(); throw error }
        book
    }
    companion object {
        fun create(context: Context): ABSClient {
            val application = context.applicationContext
            return ABSClient(KeystoreABSCredentials(application), ABSHttpTransport {
                val manager = application.getSystemService(ConnectivityManager::class.java)
                manager.getNetworkCapabilities(manager.activeNetwork)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
            }, java.io.File(application.filesDir, "audiobooks"))
        }
    }
}

private fun JSONObject.optionalText(name: String): String = if (isNull(name)) "" else optString(name)
