package io.aesms.app.data

import android.content.Context
import android.util.Base64
import io.aesms.app.crypto.KeyStore
import io.aesms.app.crypto.SecureSecrets
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.json.JSONObject
import java.io.File
import java.security.SecureRandom
import java.time.Instant

@Serializable
data class Contact(
    val username: String,
    val pubkey: String,
    val serverFingerprint: String,
    val addedAtEpochMs: Long = System.currentTimeMillis(),
) {
    val id: String get() = "$username|$pubkey"
}

@Serializable
data class LocalMessage(
    val id: String,
    val fromUsername: String,
    val plaintext: String,
    val createdAtEpochMs: Long,
    val keptLocally: Boolean = true,
    val outbound: Boolean = false,
)

data class ChatSummary(
    val username: String,
    val latest: LocalMessage,
    val count: Int,
    val unreadCount: Int = 0,
) {
    val id: String get() = username.lowercase()
}

class LocalStore(
    context: Context,
    private val secrets: SecureSecrets,
) {
    private val dir = File(context.filesDir, "aesms").also { it.mkdirs() }
    private val contactsFile = File(dir, "contacts.sealed")
    private val messagesFile = File(dir, "kept-messages.sealed")
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun loadContacts(): List<Contact> =
        loadSealed(contactsFile) ?: emptyList()

    fun saveContacts(items: List<Contact>) = saveSealed(items, contactsFile)

    fun loadKeptMessages(): List<LocalMessage> =
        loadSealed(messagesFile) ?: emptyList()

    fun saveKeptMessages(items: List<LocalMessage>) = saveSealed(items, messagesFile)

    fun exportBackup(
        passphrase: String,
        identityPrivB64: String,
        identityPubB64: String,
        contacts: List<Contact>,
    ): ByteArray {
        val payload = JSONObject()
            .put("v", 1)
            .put("priv", identityPrivB64)
            .put("pub", identityPubB64)
            .put("contacts", Base64.encodeToString(json.encodeToString(contacts).toByteArray(Charsets.UTF_8), Base64.NO_WRAP))
        val rawJson = payload.toString().toByteArray(Charsets.UTF_8)
        val compressed = runCatching { KeyStore.zlibCompress(rawJson) }.getOrDefault(rawJson)
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val key = KeyStore.deriveBackupKey(passphrase, salt)
        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val sealed = KeyStore.aesGcmEncrypt(key, nonce, compressed)
        return MAGIC_BACKUP + salt + nonce + sealed
    }

    fun importBackup(data: ByteArray, passphrase: String): Triple<String, String, List<Contact>> {
        require(data.size > 5 + 16 + 12 + 16 && data.copyOfRange(0, 5).contentEquals(MAGIC_BACKUP)) {
            "bad format"
        }
        val salt = data.copyOfRange(5, 21)
        val nonce = data.copyOfRange(21, 33)
        val ctAndTag = data.copyOfRange(33, data.size)
        val key = KeyStore.deriveBackupKey(passphrase, salt)
        val opened = KeyStore.aesGcmDecrypt(key, nonce, ctAndTag)
        val plain = runCatching { KeyStore.zlibDecompress(opened) }.getOrDefault(opened)
        val obj = JSONObject(plain.toString(Charsets.UTF_8))
        val priv = obj.getString("priv")
        val pub = obj.getString("pub")
        val cData = Base64.decode(obj.getString("contacts"), Base64.DEFAULT)
        val contacts = json.decodeFromString<List<Contact>>(cData.toString(Charsets.UTF_8))
        return Triple(priv, pub, contacts)
    }

    private inline fun <reified T> saveSealed(value: T, file: File) {
        val raw = json.encodeToString(value).toByteArray(Charsets.UTF_8)
        val compressed = runCatching { KeyStore.zlibCompress(raw) }.getOrDefault(raw)
        val key = storeKey()
        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val sealed = KeyStore.aesGcmEncrypt(key, nonce, compressed)
        file.writeBytes(MAGIC_FILE + nonce + sealed)
    }

    private inline fun <reified T> loadSealed(file: File): T? {
        if (!file.exists()) return null
        val raw = file.readBytes()
        if (raw.size <= MAGIC_FILE.size + 12 + 16 || !raw.copyOfRange(0, MAGIC_FILE.size).contentEquals(MAGIC_FILE)) {
            return null
        }
        val key = storeKey()
        val sealed = raw.copyOfRange(MAGIC_FILE.size, raw.size)
        val nonce = sealed.copyOfRange(0, 12)
        val ctAndTag = sealed.copyOfRange(12, sealed.size)
        val opened = runCatching { KeyStore.aesGcmDecrypt(key, nonce, ctAndTag) }.getOrNull() ?: return null
        val jsonBytes = runCatching { KeyStore.zlibDecompress(opened) }.getOrDefault(opened)
        return runCatching { json.decodeFromString<T>(jsonBytes.toString(Charsets.UTF_8)) }.getOrNull()
    }

    private fun storeKey(): ByteArray {
        val existing = secrets.get(STORE_KEY)
        if (existing != null) {
            val data = Base64.decode(existing, Base64.DEFAULT)
            if (data.size == 32) return data
        }
        val data = ByteArray(32).also { SecureRandom().nextBytes(it) }
        secrets.set(STORE_KEY, Base64.encodeToString(data, Base64.NO_WRAP))
        return data
    }

    companion object {
        private val MAGIC_FILE = "AESMSL1".toByteArray(Charsets.UTF_8)
        private val MAGIC_BACKUP = "T9BK1".toByteArray(Charsets.UTF_8)
        private const val STORE_KEY = "local_store_aes_key"
    }
}

fun Instant.toEpochMs(): Long = toEpochMilli()
