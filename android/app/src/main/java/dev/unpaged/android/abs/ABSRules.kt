package dev.unpaged.android.abs

import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.Base64
import java.util.Locale
import org.json.JSONObject
import dev.unpaged.android.library.*

enum class ABSFailure {
    NOT_CONNECTED, INVALID_SERVER_URL, UNREACHABLE_SERVER, BAD_CREDENTIALS, EXPIRED_TOKEN,
    SERVER_ERROR, UNREADABLE_RESPONSE, INVALID_MEDIA_URL, INACTIVE_API_KEY, OFFLINE, NOT_ABS_SERVER
}
class ABSException(val failure: ABSFailure, val status: Int = 0) : java.io.IOException(failure.name)

object ABSRules {
    fun privateHost(raw: String): Boolean {
        val host = raw.lowercase(Locale.ROOT).removeSurrounding("[", "]").removeSuffix(".")
        if (host.isEmpty()) return false
        if (":" in host) {
            val address = host.substringBefore('%')
            if (address == "::1") return true
            val word = address.substringBefore(':').toIntOrNull(16) ?: return false
            return word in 0..65535 && (word and 0xfe00 == 0xfc00 || word and 0xffc0 == 0xfe80)
        }
        if (host == "localhost" || host.endsWith(".localhost") || host.endsWith(".local") || host.endsWith(".ts.net")) return true
        if (host.all { it.isDigit() || it == '.' }) {
            val octets = host.split('.').map { it.toIntOrNull() ?: return false }
            if (octets.size != 4 || octets.any { it !in 0..255 }) return false
            val (a, b) = octets
            return a == 10 || a == 127 || a == 192 && b == 168 || a == 169 && b == 254 ||
                a == 172 && b in 16..31 || a == 100 && b in 64..127
        }
        return '.' !in host
    }
    fun serverURL(input: String): String {
        var text = input.trim()
        if (text.isEmpty() || text.any { it.isWhitespace() }) throw ABSException(ABSFailure.INVALID_SERVER_URL)
        if (!text.startsWith("http://", true) && !text.startsWith("https://", true)) {
            if ("://" in text) throw ABSException(ABSFailure.INVALID_SERVER_URL)
            val authority = text.substringBefore('/')
            val host = if (authority.startsWith('[')) authority.substringBefore(']') + "]" else authority.substringBefore(':')
            // Bare tailnet names usually front tailscale serve HTTPS; explicit ports use the listener.
            val local = privateHost(host) && (!host.endsWith(".ts.net", true) || ':' in authority)
            text = (if (local) "http://" else "https://") + text
        }
        val uri = try { URI(text.trimEnd('/')) } catch (_: Exception) { throw ABSException(ABSFailure.INVALID_SERVER_URL) }
        if (uri.scheme.lowercase(Locale.ROOT) !in listOf("http", "https") || uri.host == null || uri.rawUserInfo != null ||
            uri.rawQuery != null || uri.rawFragment != null || uri.port !in -1..65535) throw ABSException(ABSFailure.INVALID_SERVER_URL)
        return URI("${uri.scheme.lowercase(Locale.ROOT)}://${uri.rawAuthority.lowercase(Locale.ROOT)}${uri.rawPath}").toASCIIString()
    }
    fun insecureWarning(url: String, acknowledged: String? = null, connected: String? = null): Boolean {
        val uri = URI(url)
        return uri.scheme == "http" && !privateHost(uri.host) && url != acknowledged && url != connected
    }
    fun containsCredential(url: String): Boolean {
        val uri = try { URI(url) } catch (_: Exception) { return true }
        return uri.rawUserInfo != null || uri.rawFragment != null || uri.rawQuery?.split('&')?.any {
            URLDecoder.decode(it.substringBefore('='), "UTF-8").lowercase(Locale.ROOT) in
                listOf("token", "api_key", "apikey", "access_token", "refresh_token", "authorization")
        } == true
    }
    fun storedURL(raw: String, base: String): String {
        val b = URI(base)
        val uri = try { b.resolve(raw) } catch (_: Exception) { throw ABSException(ABSFailure.INVALID_MEDIA_URL) }
        if (uri.host != b.host || uri.scheme != b.scheme || uri.port != b.port || containsCredential(uri.toString()))
            throw ABSException(ABSFailure.INVALID_MEDIA_URL)
        return uri.toASCIIString()
    }
    fun appendToken(url: String, token: String): String {
        if (containsCredential(url)) throw ABSException(ABSFailure.INVALID_MEDIA_URL)
        return url + (if (URI(url).rawQuery == null) "?" else "&") + "token=" + URLEncoder.encode(token, "UTF-8")
    }
    fun jwtPayload(token: String): JSONObject? = runCatching {
        val parts = token.split('.')
        if (parts.size != 3) return null
        JSONObject(String(Base64.getUrlDecoder().decode(parts[1]), Charsets.UTF_8))
    }.getOrNull()
    fun needsRefresh(token: String, nowSeconds: Long = System.currentTimeMillis() / 1000): Boolean {
        val payload = jwtPayload(token) ?: return false
        return payload.has("exp") && payload.optDouble("exp") - nowSeconds < 45 * 60
    }
    fun apiKeyJWT(token: String): Boolean = jwtPayload(token)?.let { it.optString("type") == "api" && it.has("keyId") } == true
    fun httpFailure(status: Int, path: String, apiKey: String? = null): ABSException = ABSException(when {
        status == 401 && apiKey != null -> if (apiKeyJWT(apiKey)) ABSFailure.INACTIVE_API_KEY else ABSFailure.BAD_CREDENTIALS
        status == 401 && path == "login" -> ABSFailure.BAD_CREDENTIALS
        status == 401 -> ABSFailure.EXPIRED_TOKEN
        status == 404 && path in listOf("login", "api/authorize") -> ABSFailure.NOT_ABS_SERVER
        status in listOf(502, 503, 504) -> ABSFailure.UNREACHABLE_SERVER
        else -> ABSFailure.SERVER_ERROR
    }, status)
    fun message(error: Throwable, host: String, apiKey: Boolean = false): String = when ((error as? ABSException)?.failure) {
        ABSFailure.INVALID_SERVER_URL -> "That doesn't look like a server address. Try something like https://abs.example.com."
        ABSFailure.UNREACHABLE_SERVER -> if (host.substringBefore(':').endsWith(".ts.net") || host.substringBefore(':').split('.').let { p -> p.size == 4 && p[0] == "100" && (p[1].toIntOrNull() ?: -1) in 64..127 })
            "Can't reach $host. Make sure Tailscale is on and connected on this phone, and that the server is running."
            else "Can't reach $host. Check the address, that the server is running, and that this phone is on the same network or VPN."
        ABSFailure.OFFLINE -> "You're offline. Connect to Wi-Fi or cellular and try again."
        ABSFailure.NOT_ABS_SERVER -> "$host answered, but it isn't an Audiobookshelf server. Check the address."
        ABSFailure.INACTIVE_API_KEY -> "This API key is inactive. Enable it in Audiobookshelf Settings, API Keys, then try again."
        ABSFailure.BAD_CREDENTIALS, ABSFailure.EXPIRED_TOKEN -> if (apiKey) "The server didn't accept this API key. Check that you copied all of it."
            else "That username and password didn't work. Check them and try again."
        ABSFailure.NOT_CONNECTED -> "Connect your Audiobookshelf server to continue."
        ABSFailure.SERVER_ERROR -> "$host had a problem (error ${error.status}). Try again in a moment."
        else -> "$host sent a reply Unpaged couldn't read. Check that it's an Audiobookshelf server."
    }
    fun position(globalMs: Long, durations: List<Long>): Pair<Int, Long> {
        var remaining = globalMs.coerceAtLeast(0)
        durations.forEachIndexed { i, duration ->
            if (remaining < duration || i == durations.lastIndex) return i to remaining.coerceAtMost(duration.coerceAtLeast(0))
            remaining -= duration.coerceAtLeast(0)
        }
        return 0 to 0L
    }
    fun progressPayload(book: LibraryBook): JSONObject {
        val duration = book.durationMs / 1000.0
        val current = if (book.isFinished) duration else (book.globalPositionMs / 1000.0).coerceIn(0.0, duration)
        return JSONObject().put("duration", duration).put("currentTime", current)
            .put("progress", if (book.isFinished) 1.0 else if (duration > 0) current / duration else 0.0)
            .put("isFinished", book.isFinished)
    }
}
