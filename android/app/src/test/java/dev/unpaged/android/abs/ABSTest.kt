package dev.unpaged.android.abs

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.json.JSONObject
import java.util.Base64
import dev.unpaged.android.library.*
import dev.unpaged.android.UnpagedPreferences
import kotlinx.coroutines.*

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class ABSTest {
    private fun jwt(json: String) = "header." + Base64.getUrlEncoder().withoutPadding().encodeToString(json.toByteArray()) + ".signature"
    private fun reject(failure: ABSFailure, action: () -> Unit) {
        try { action(); fail("Expected $failure") } catch (e: ABSException) { assertEquals(failure, e.failure) }
    }
    @Test fun privateIPv4RangesAndBoundaries() {
        for (host in listOf("10.0.0.1", "172.16.0.1", "172.31.255.255", "192.168.1.1", "127.99.0.1", "169.254.2.3", "100.64.0.0", "100.127.255.255")) assertTrue(host, ABSRules.privateHost(host))
        for (host in listOf("172.15.255.255", "172.32.0.0", "100.63.255.255", "100.128.0.0", "8.8.8.8", "10.0.0.999", "1.2.3", "")) assertFalse(host, ABSRules.privateHost(host))
    }
    @Test fun privateIPv6AndDNSMatchIOS() {
        for (host in listOf("::1", "[::1]", "fc00::1", "fd7a:115c:a1e0::1", "fe80::1%en0", "febf::1", "NAS", "nas.local", "nas.LOCAL.", "a.ts.net", "localhost", "a.localhost")) assertTrue(host, ABSRules.privateHost(host))
        for (host in listOf("::", "2001:db8::1", "fec0::1", "fbff::1", "ts.net", "a.ts.net.evil.com", "example.com")) assertFalse(host, ABSRules.privateHost(host))
    }
    @Test fun warningOnlyPublicHTTPAndAcknowledgementIsAddressScoped() {
        assertTrue(ABSRules.insecureWarning("http://example.com"))
        assertFalse(ABSRules.insecureWarning("https://example.com"))
        assertFalse(ABSRules.insecureWarning("http://nas.ts.net"))
        assertFalse(ABSRules.insecureWarning("http://example.com", connected = "http://example.com"))
        assertFalse(ABSRules.insecureWarning("http://example.com", acknowledged = "http://example.com"))
        assertTrue(ABSRules.insecureWarning("http://other.example.com", acknowledged = "http://example.com"))
    }
    @Test fun normalizationDefaultsPathsPortsAndInvalidInputs() {
        assertEquals("https://example.com/abs", ABSRules.serverURL(" example.com/abs/ "))
        assertEquals("https://example.com/abs%2Fpath", ABSRules.serverURL("https://EXAMPLE.com/abs%2Fpath/"))
        assertEquals("http://10.0.2.2:13378", ABSRules.serverURL("10.0.2.2:13378"))
        assertEquals("https://nas.ts.net", ABSRules.serverURL("nas.ts.net"))
        assertEquals("http://nas.ts.net:13378", ABSRules.serverURL("nas.ts.net:13378"))
        assertEquals("http://[::1]:80", ABSRules.serverURL("[::1]:80"))
        for (input in listOf("", "ftp://example.com", "https://u:p@example.com", "http://example.com?token=a", "http://example.com#x", "not a host", "https://")) reject(ABSFailure.INVALID_SERVER_URL) { ABSRules.serverURL(input) }
    }
    @Test fun storageRefusesCredentialsEncodedNamesAndOtherOrigins() {
        assertEquals("http://nas:80/audio/a?download=1", ABSRules.storedURL("/audio/a?download=1", "http://nas:80"))
        for (url in listOf("/a?token=x", "/a?API_KEY=x", "/a?%61ccess_token=x", "http://u:p@nas:80/a", "http://other:80/a", "https://nas:80/a", "http://nas:81/a", "/a#token")) reject(ABSFailure.INVALID_MEDIA_URL) { ABSRules.storedURL(url, "http://nas:80") }
    }
    @Test fun tokenAppendPreservesQueryAndEscapesToken() {
        assertEquals("http://nas/a?token=a%2Bb%26c", ABSRules.appendToken("http://nas/a", "a+b&c"))
        assertEquals("http://nas/a?x=1&token=abc", ABSRules.appendToken("http://nas/a?x=1", "abc"))
        reject(ABSFailure.INVALID_MEDIA_URL) { ABSRules.appendToken("http://nas/a?token=old", "new") }
    }
    @Test fun refreshThresholdIsStrictlyUnder45MinutesAndSessionsOnly() {
        assertTrue(ABSRules.needsRefresh(jwt("{\"exp\":3699}"), 1000))
        assertFalse(ABSRules.needsRefresh(jwt("{\"exp\":3700}"), 1000))
        assertTrue(ABSRules.needsRefresh(jwt("{\"exp\":900}"), 1000))
        assertFalse(ABSRules.needsRefresh("opaque", 1000))
    }
    @Test fun HTTPFailuresAndInactiveKeyMapping() {
        assertEquals(ABSFailure.BAD_CREDENTIALS, ABSRules.httpFailure(401, "login").failure)
        assertEquals(ABSFailure.EXPIRED_TOKEN, ABSRules.httpFailure(401, "api/libraries").failure)
        assertEquals(ABSFailure.BAD_CREDENTIALS, ABSRules.httpFailure(401, "api/authorize", "mistyped").failure)
        assertEquals(ABSFailure.INACTIVE_API_KEY, ABSRules.httpFailure(401, "api/authorize", jwt("{\"type\":\"api\",\"keyId\":\"id\"}")).failure)
        assertEquals(ABSFailure.NOT_ABS_SERVER, ABSRules.httpFailure(404, "login").failure)
        assertEquals(ABSFailure.NOT_ABS_SERVER, ABSRules.httpFailure(404, "api/authorize").failure)
        assertEquals(ABSFailure.UNREACHABLE_SERVER, ABSRules.httpFailure(503, "api/items").failure)
        assertEquals(403, ABSRules.httpFailure(403, "api/items").status)
        assertTrue(ABSRules.message(ABSException(ABSFailure.UNREACHABLE_SERVER), "nas.ts.net").contains("Tailscale"))
        assertTrue(ABSRules.message(ABSException(ABSFailure.UNREACHABLE_SERVER), "192.168.1.1").contains("VPN"))
        assertFalse(ABSRules.message(ABSException(ABSFailure.UNREACHABLE_SERVER), "100.128.0.1").contains("Tailscale"))
    }
    @Test fun offlineIsDistinctFromUnreachable() {
        reject(ABSFailure.OFFLINE) { ABSHttpTransport { false }.send("http://invalid", "GET", emptyMap(), null) }
    }
    @Test fun progressPayloadIsBookGlobalClampedAndFinished() {
        val book = LibraryBook("id", "Book", "Author", listOf(LibraryTrack("a", "", "", 100000, ""), LibraryTrack("b", "", "", 200000, "")), currentTrackIndex = 1, currentPositionMs = 50000)
        val payload = ABSRules.progressPayload(book)
        assertEquals(300.0, payload.getDouble("duration"), 0.0); assertEquals(150.0, payload.getDouble("currentTime"), 0.0)
        assertEquals(.5, payload.getDouble("progress"), 0.0); assertFalse(payload.getBoolean("isFinished"))
        assertEquals(300.0, ABSRules.progressPayload(book.copy(isFinished = true)).getDouble("currentTime"), 0.0)
        assertEquals(1.0, ABSRules.progressPayload(book.copy(isFinished = true)).getDouble("progress"), 0.0)
        assertEquals(1 to 50000L, ABSRules.position(150000, listOf(100000, 200000)))
        assertEquals(1 to 200000L, ABSRules.position(999999, listOf(100000, 200000)))
    }
    private class MemoryCredentials(var value: ABSConnection? = null) : ABSCredentialStore {
        override fun load() = value
        override fun save(connection: ABSConnection) { value = connection }
        override fun clear() { value = null }
    }
    private fun reply(text: String, status: Int = 200) = ABSResponse(status, text.toByteArray())
    @Test fun concurrent401SharesOneRefreshAndOnlyOneRetry() = runBlocking {
        val credentials = MemoryCredentials(ABSConnection("http://nas", "old", "refresh", "reader"))
        val refreshCount = java.util.concurrent.atomic.AtomicInteger()
        val client = ABSClient(credentials, ABSTransport { url, _, headers, _ ->
            if (url.endsWith("auth/refresh")) {
                refreshCount.incrementAndGet(); Thread.sleep(100)
                assertEquals("refresh", headers["x-refresh-token"])
                reply("{\"user\":{\"accessToken\":\"new\",\"refreshToken\":\"renewed\"}}")
            } else if (headers["Authorization"] == "Bearer old") reply("", 401)
            else reply("{\"libraries\":[{\"id\":\"l\",\"name\":\"Books\",\"mediaType\":\"book\"}]}")
        })
        val results = (1..8).map { async { client.libraries() } }.awaitAll()
        assertEquals(1, refreshCount.get()); assertTrue(results.all { it.single().id == "l" })
        assertEquals("new", credentials.value!!.access)
    }
    @Test fun failedRetryDoesNotRefreshAgain() = runBlocking {
        val refreshCount = java.util.concurrent.atomic.AtomicInteger()
        val client = ABSClient(MemoryCredentials(ABSConnection("http://nas", "old", "r", null)), ABSTransport { url, _, _, _ ->
            if (url.endsWith("auth/refresh")) { refreshCount.incrementAndGet(); reply("{\"user\":{\"accessToken\":\"new\",\"refreshToken\":\"r2\"}}") }
            else reply("", 401)
        })
        try { client.libraries(); fail() } catch (e: ABSException) { assertEquals(ABSFailure.EXPIRED_TOKEN, e.failure) }
        assertEquals(1, refreshCount.get())
    }
    @Test fun disconnectDuringRefreshCannotRestoreCredentials() = runBlocking {
        val entered = java.util.concurrent.CountDownLatch(1); val release = java.util.concurrent.CountDownLatch(1)
        val credentials = MemoryCredentials(ABSConnection("http://nas", "old", "r", null))
        val client = ABSClient(credentials, ABSTransport { url, _, _, _ ->
            if (url.endsWith("auth/refresh")) { entered.countDown(); release.await(); reply("{\"user\":{\"accessToken\":\"new\",\"refreshToken\":\"r2\"}}") }
            else reply("", 401)
        })
        client.reload()
        val request = async { runCatching { client.libraries() } }
        withContext(Dispatchers.IO) { assertTrue(entered.await(5, java.util.concurrent.TimeUnit.SECONDS)) }
        client.disconnect(); release.countDown(); assertTrue(request.await().isFailure)
        assertNull(credentials.value); assertNull(client.summary.value)
    }
    @Test fun loginValidatesABSAndNeverStoresPassword() = runBlocking {
        val credentials = MemoryCredentials()
        val client = ABSClient(credentials, ABSTransport { url, method, headers, body ->
            assertEquals("POST", method)
            if (url.endsWith("login")) {
                assertEquals("true", headers["x-return-tokens"])
                assertEquals("secret", JSONObject(String(body!!)).getString("password"))
                reply("{\"user\":{\"accessToken\":\"access\",\"refreshToken\":\"refresh\",\"username\":\"reader\"}}")
            } else { assertEquals("Bearer access", headers["Authorization"]); reply("{\"user\":{\"username\":\"reader\"}}") }
        })
        client.login("nas", "reader", "secret")
        assertEquals("access", credentials.value!!.access); assertEquals("reader", client.summary.value!!.username)
    }
    @Test fun invalidServerReplyLeavesPreviousConnectionUntouched() = runBlocking {
        val original = ABSConnection("http://nas", "old", "r", "reader")
        val credentials = MemoryCredentials(original)
        val client = ABSClient(credentials, ABSTransport { _, _, _, _ -> reply("{}") })
        try { client.login("other", "reader", "password"); fail() } catch (e: ABSException) { assertEquals(ABSFailure.NOT_ABS_SERVER, e.failure) }
        assertSame(original, credentials.value)
    }
    @Test fun playbackRefreshesExpiringLoginButNeverAPIKeyOrLeaksAcrossOrigins() = runBlocking {
        val expired = jwt("{\"exp\":0}")
        val count = java.util.concurrent.atomic.AtomicInteger()
        val credentials = MemoryCredentials(ABSConnection("http://nas", expired, "r", null))
        val client = ABSClient(credentials, ABSTransport { _, _, _, _ -> count.incrementAndGet(); reply("{\"user\":{\"accessToken\":\"new\",\"refreshToken\":\"r2\"}}") })
        assertEquals("http://nas/audio?token=new", client.playbackURL("http://nas/audio")); assertEquals(1, count.get())
        try { client.playbackURL("http://other/audio"); fail() } catch (e: ABSException) { assertEquals(ABSFailure.INVALID_MEDIA_URL, e.failure) }
        val apiClient = ABSClient(MemoryCredentials(ABSConnection("http://nas", expired, null, null)), ABSTransport { _, _, _, _ -> error("API key must not refresh") })
        assertTrue(apiClient.playbackURL("http://nas/audio").contains("token="))
    }
    @Test fun pageValidationAndMultiplePages() = runBlocking {
        val calls = mutableListOf<String>()
        val client = ABSClient(MemoryCredentials(ABSConnection("http://nas", "key", null, null)), ABSTransport { url, _, _, _ ->
            calls += url
            val page = if (url.contains("page=0")) 0 else 1
            val rows = if (page == 0) (0..99) else (100..100)
            val results = rows.joinToString(",") { id -> """{"id":"$id","mediaType":"book","media":{"metadata":{"title":"Book $id"},"duration":10}}""" }
            reply("""{"page":$page,"limit":100,"total":101,"results":[$results]}""")
        })
        assertEquals((0..100).map { it.toString() }, client.items("lib").map { it.id }); assertEquals(2, calls.size)
    }
    @Test fun nullableServerMetadataUsesEmptyFallbacks() = runBlocking {
        val client = ABSClient(MemoryCredentials(ABSConnection("http://nas", "key", null, null)), ABSTransport { _, _, _, _ ->
            reply("""{"id":"item","media":{"metadata":{"title":"Title","authorName":null,"narratorName":null,"description":null,"subtitle":null},"coverPath":null,"duration":60}}""")
        })
        val item = client.item("item")
        assertEquals("Unknown author", item.author); assertEquals("", item.narrator); assertEquals("", item.description)
        assertEquals("", item.subtitle); assertFalse(item.hasCover)
    }
    @Test fun sourcePreferenceFallsBackWithoutLosingConnectedChoice() {
        val prefs = UnpagedPreferences(RuntimeEnvironment.getApplication())
        prefs.setShelvesSource("audiobookshelf")
        assertEquals("librivox", prefs.shelvesSource(false)); assertEquals("audiobookshelf", prefs.shelvesSource(true))
        prefs.setShelvesSource("unknown"); assertEquals("librivox", prefs.shelvesSource(true))
    }
    @Test fun addSeedsPositionStreamingIdentityAndDuplicateReusesRow() = runBlocking {
        val context = RuntimeEnvironment.getApplication(); context.deleteDatabase("library.db")
        val store = SQLiteLibraryStore(context)
        val client = ABSClient(MemoryCredentials(ABSConnection("http://nas", "key", null, null)), ABSTransport { _, _, _, _ -> reply("{\"currentTime\":15,\"isFinished\":false}") })
        client.reload()
        val item = ABSItem("abs-id", "Server Book", "Author", "", "", 30000, false,
            listOf(LibraryTrack("one", "one.wav", "", 10000, "", "/audio/one"), LibraryTrack("two", "two.wav", "", 20000, "", "/audio/two")), emptyList(), 0)
        try {
            val added = client.add(item, store)
            assertFalse(added.isDownloaded); assertFalse(added.isFreeBook); assertEquals("abs-id", added.absItemID)
            assertEquals(1, added.currentTrackIndex); assertEquals(5000L, added.currentPositionMs)
            assertTrue(added.tracks.all { it.remoteUrl!!.startsWith("http://nas/") && !ABSRules.containsCredential(it.remoteUrl) })
            assertEquals(added.id, client.add(item, store).id); assertEquals(1, store.books().size)
        } finally { store.close() }
    }
    @Test fun sqliteLastLineGuardRefusesCredentialBearingABSRows() {
        val context = RuntimeEnvironment.getApplication(); context.deleteDatabase("library.db")
        val store = SQLiteLibraryStore(context)
        try {
            val unsafe = LibraryBook("bad", "Bad", "", listOf(LibraryTrack("a", "", "", 1000, "", "http://nas/a?token=secret")), isDownloaded = false, absItemID = "abs")
            try { store.insert(unsafe); fail() } catch (_: IllegalArgumentException) { }
            assertTrue(store.books().isEmpty())
        } finally { store.close() }
    }
    @Test fun encryptedCredentialsReopenWithFreshIVAndRejectTampering() {
        val context = RuntimeEnvironment.getApplication()
        val key = javax.crypto.KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val credentials = KeystoreABSCredentials(context) { key }
        credentials.clear()
        val value = ABSConnection("http://nas", "sensitive-access", "sensitive-refresh", "reader")
        val file = java.io.File(context.noBackupFilesDir, "abs-credentials.enc")
        credentials.save(value)
        val first = file.readBytes()
        assertFalse(String(first, Charsets.ISO_8859_1).contains("sensitive-access"))
        val reopened = KeystoreABSCredentials(context) { key }
        assertEquals(value.access, reopened.load()!!.access); assertEquals(value.refresh, reopened.load()!!.refresh)
        reopened.save(value)
        assertFalse(first.copyOfRange(0, 12).contentEquals(file.readBytes().copyOfRange(0, 12)))
        val changed = file.readBytes(); changed[changed.lastIndex] = (changed.last().toInt() xor 1).toByte(); file.writeBytes(changed)
        try { reopened.load(); fail("Authenticated ciphertext must reject tampering") } catch (_: java.security.GeneralSecurityException) { }
        reopened.clear(); assertNull(reopened.load()); assertFalse(file.exists())
    }
    @Test fun failedRefreshCanBeRetriedAfterNetworkRecovery() = runBlocking {
        val attempts = java.util.concurrent.atomic.AtomicInteger()
        val client = ABSClient(MemoryCredentials(ABSConnection("http://nas", "old", "r", null)), ABSTransport { url, _, headers, _ ->
            if (url.endsWith("auth/refresh")) {
                if (attempts.incrementAndGet() == 1) reply("", 503) else reply("{\"user\":{\"accessToken\":\"new\",\"refreshToken\":\"r2\"}}")
            } else if (headers["Authorization"] == "Bearer old") reply("", 401) else reply("{\"libraries\":[]}")
        })
        try { client.libraries(); fail() } catch (e: ABSException) { assertEquals(ABSFailure.UNREACHABLE_SERVER, e.failure) }
        assertTrue(client.libraries().isEmpty()); assertEquals(2, attempts.get())
    }
    @Test fun apiKeyAuthorizationPersistsBearerAndNeverRefreshesOn401() = runBlocking {
        val credentials = MemoryCredentials()
        var requests = 0
        val client = ABSClient(credentials, ABSTransport { url, method, headers, body ->
            requests++
            assertEquals("Bearer key", headers["Authorization"])
            if (url.endsWith("api/authorize")) { assertEquals("POST", method); assertNull(body); reply("{\"user\":{\"username\":\"reader\"}}") }
            else reply("", 401)
        })
        client.apiKey("nas", "key"); assertNull(credentials.value!!.refresh); assertEquals("reader", credentials.value!!.username)
        try { client.libraries(); fail() } catch (e: ABSException) { assertEquals(ABSFailure.BAD_CREDENTIALS, e.failure) }
        assertEquals(2, requests)
    }
    @Test fun serverChaptersMapGlobalOffsetsToFilesAndIgnoreInvalidMarkers() {
        val book = LibraryBook("id", "Title", "Author", listOf(LibraryTrack("one", "", "", 10000, ""), LibraryTrack("two", "", "", 20000, "")), absItemID = "server",
            absChaptersJson = """[{"title":"First","start":0,"end":5000},{"title":"Second","start":5000,"end":10000},{"title":"Third","start":10000,"end":30000},{"title":"Outside","start":90000,"end":100000}]""")
        val chapters = dev.unpaged.android.playback.PlaybackRules.chapters(book)
        assertEquals(3, chapters.size); assertEquals(0, chapters[1].trackIndex); assertEquals(5000L, chapters[1].startMs)
        assertEquals(1, chapters[2].trackIndex); assertEquals(0L, chapters[2].startMs); assertEquals(20000L, chapters[2].durationMs)
    }
    @Test fun actualV3ToV4PreservesRowsAndReopensABSIdentity() {
        val context = RuntimeEnvironment.getApplication(); context.deleteDatabase("library.db")
        // Build actual v3 tables from the current schema SQL, omitting both new columns.
        val schemaStore = SQLiteLibraryStore(context)
        val schemas = schemaStore.readableDatabase.rawQuery("SELECT sql FROM sqlite_master WHERE type IN ('table','index') AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'", null).use { r ->
            buildList { while (r.moveToNext()) add(r.getString(0).replace(", abs_item_id TEXT", "").replace(", abs_chapters_json TEXT", "")) }
        }
        schemaStore.close(); context.deleteDatabase("library.db")
        android.database.sqlite.SQLiteDatabase.openOrCreateDatabase(context.getDatabasePath("library.db"), null).use { db ->
            schemas.forEach { db.execSQL(it) }
            db.execSQL("INSERT INTO books(id,title,author,is_favorite,current_position_ms) VALUES('existing','Existing','Author',1,5000)")
            db.execSQL("INSERT INTO tracks(book_id,position,title,original_name,stored_name,duration_ms,fingerprint) VALUES('existing',0,'Track','1.wav','1.wav',10000,'fingerprint')")
            db.execSQL("INSERT INTO moments(id,book_id,track_index,time_ms,label,notes,categories_json,characters_json,created_at,is_pinned) VALUES('m','existing',0,1,'Saved','','[]','[]',1,1)")
            db.version = 3
        }
        val store = SQLiteLibraryStore(context)
        try {
            assertEquals(5, store.readableDatabase.version)
            val book = store.books().single(); assertEquals("existing", book.id); assertTrue(book.isFavorite); assertEquals(5000L, book.currentPositionMs)
            assertNull(book.absItemID); assertEquals("fingerprint", book.tracks.single().fingerprint); assertTrue(store.moments(book.id).single().isPinned)
            store.insert(LibraryBook("abs", "Server", "Author", listOf(LibraryTrack("Track", "", "", 10000, "", "http://nas/a")), isDownloaded = false, absItemID = "item", absChaptersJson = "[]"))
        } finally { store.close() }
        val reopened = SQLiteLibraryStore(context)
        try { assertEquals("item", reopened.books().first { it.id == "abs" }.absItemID); reopened.delete("abs"); assertEquals(1, reopened.books().size) }
        finally { reopened.close() }
    }
}
