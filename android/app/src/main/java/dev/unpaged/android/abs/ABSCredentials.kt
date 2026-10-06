package dev.unpaged.android.abs

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

// Deliberately no generated toString: credentials must never appear in diagnostics.
class ABSConnection(val server: String, val access: String, val refresh: String?, val username: String?) {
    val apiKey get() = refresh == null
}
interface ABSCredentialStore {
    fun load(): ABSConnection?
    fun save(connection: ABSConnection)
    fun clear()
}

/** A fresh Keystore-generated IV per write, authenticated ciphertext and atomic replacement. */
class KeystoreABSCredentials(context: Context, private val keyProvider: (() -> SecretKey)? = null) : ABSCredentialStore {
    private val file = AtomicFile(File(context.noBackupFilesDir, "abs-credentials.enc"))
    private val alias = "unpaged.abs.aes"
    private fun key(): SecretKey {
        keyProvider?.let { return it() }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    @Synchronized override fun load(): ABSConnection? {
        val bytes = try { file.readFully() } catch (_: java.io.FileNotFoundException) { return null }
        require(bytes.size >= 12 + 16)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        val json = JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
        return ABSConnection(json.getString("server"), json.getString("access"),
            if (json.isNull("refresh")) null else json.getString("refresh"),
            if (json.isNull("username")) null else json.getString("username"))
    }
    @Synchronized override fun save(connection: ABSConnection) {
        val json = JSONObject().put("server", connection.server).put("access", connection.access)
            .put("refresh", connection.refresh ?: JSONObject.NULL).put("username", connection.username ?: JSONObject.NULL)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val output = file.startWrite()
        try { output.write(cipher.iv + cipher.doFinal(json.toString().toByteArray(Charsets.UTF_8))); file.finishWrite(output) }
        catch (error: Exception) { file.failWrite(output); throw error }
    }
    @Synchronized override fun clear() { file.delete() }
}
