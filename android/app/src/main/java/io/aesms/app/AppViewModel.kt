package io.aesms.app

import android.app.Application
import android.content.Context
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.aesms.app.crypto.KeyStore
import io.aesms.app.crypto.SecureSecrets
import io.aesms.app.crypto.decodeBase64UrlOrStd
import io.aesms.app.data.ApiClient
import io.aesms.app.data.ChatSummary
import io.aesms.app.data.Contact
import io.aesms.app.data.EventStream
import io.aesms.app.data.LocalMessage
import io.aesms.app.data.LocalStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.format.DateTimeParseException

enum class Phase {
    Server, Credentials, WaitingRelease, Mailbox
}

class AppViewModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("aesms_prefs", Context.MODE_PRIVATE)
    val secrets = SecureSecrets(app)
    val keys = KeyStore(secrets)
    val store = LocalStore(app, secrets)
    val api = ApiClient()
    private val events = EventStream()

    var serverURL by mutableStateOf(prefs.getString(KEY_SERVER, "https://app.aesms.io") ?: "https://app.aesms.io")
        private set
    var phase by mutableStateOf(Phase.Server)
        private set
    var username by mutableStateOf(prefs.getString(KEY_USER, "") ?: "")
        private set
    var deviceToken by mutableStateOf<String?>(null)
        private set
    var pendingID by mutableStateOf<String?>(null)
        private set
    var statusLine by mutableStateOf("")
        private set
    var contacts by mutableStateOf<List<Contact>>(emptyList())
        private set
    var inbox by mutableStateOf<List<LocalMessage>>(emptyList())
        private set
    var fingerprint by mutableStateOf("")
        private set
    var unlocked by mutableStateOf(false)
        private set
    var pushOnline by mutableStateOf(false)
        private set
    private var unreadIDs by mutableStateOf<Set<String>>(emptySet())

    val unreadTotal: Int get() = unreadIDs.size

    init {
        contacts = store.loadContacts()
        inbox = store.loadKeptMessages()
        unreadIDs = prefs.getStringSet(KEY_UNREAD, emptySet())?.toSet().orEmpty()
            .intersect(inbox.map { it.id }.toSet())
        persistUnread()
        val tok = secrets.get("device_token")
        if (!tok.isNullOrEmpty()) {
            deviceToken = tok
            phase = Phase.Mailbox
            username = prefs.getString(KEY_USER, "") ?: ""
        }
        keys.loadOrCreateIdentity()
    }

    fun updateServerURL(value: String) {
        serverURL = value
        prefs.edit().putString(KEY_SERVER, value).apply()
    }

    fun setStatus(value: String) {
        statusLine = value
    }

    fun updateFingerprint(value: String) {
        fingerprint = value
    }

    fun goToPhase(value: Phase) {
        phase = value
        if (value == Phase.Mailbox) {
            startPushIfNeeded()
        } else {
            stopPush()
            unlocked = false
        }
    }

    fun updatePendingID(value: String?) {
        pendingID = value
    }

    fun replaceInbox(items: List<LocalMessage>) {
        inbox = items
    }

    fun replaceUnread(ids: Set<String>) {
        unreadIDs = ids
        persistUnread()
    }

    fun saveUsername(u: String) {
        username = u
        prefs.edit().putString(KEY_USER, u).apply()
    }

    fun updateDeviceToken(tok: String?) {
        deviceToken = tok
        if (tok == null) secrets.delete("device_token") else secrets.set("device_token", tok)
    }

    fun lockMailbox() {
        unlocked = false
    }

    fun unlockMailbox() {
        unlocked = true
    }

    fun updateContacts(items: List<Contact>) {
        contacts = items
        store.saveContacts(items)
    }

    fun startPushIfNeeded() {
        val tok = deviceToken ?: return
        if (phase != Phase.Mailbox) return
        events.start(viewModelScope, serverURL, tok) {
            viewModelScope.launch {
                statusLine = "new message"
                fetchInboxQuiet()
            }
        }
        pushOnline = true
    }

    fun stopPush() {
        events.stop()
        pushOnline = false
    }

    suspend fun fetchInboxQuiet(): Int {
        val tok = deviceToken ?: return 0
        return try {
            val res = withContext(Dispatchers.IO) { api.fetchMessages(serverURL, tok) }
            var newlyUnread = 0
            var nextInbox = inbox
            var nextUnread = unreadIDs
            for (wire in res.messages) {
                val data = decodeBase64UrlOrStd(wire.ciphertext) ?: continue
                val plain = runCatching { keys.open(data) }.getOrDefault("«undecryptable»")
                val whenMs = parseIso(wire.createdAt) ?: System.currentTimeMillis()
                val local = LocalMessage(
                    id = wire.id,
                    fromUsername = wire.fromUsername,
                    plaintext = plain,
                    createdAtEpochMs = whenMs,
                    keptLocally = true,
                )
                if (nextInbox.none { it.id == local.id }) {
                    nextInbox = listOf(local) + nextInbox
                    if (!local.outbound) {
                        nextUnread = nextUnread + local.id
                        newlyUnread++
                    }
                }
            }
            inbox = nextInbox
            if (nextUnread != unreadIDs) {
                unreadIDs = nextUnread
                persistUnread()
            }
            withContext(Dispatchers.IO) { store.saveKeptMessages(inbox) }
            if (newlyUnread > 0) {
                statusLine = if (newlyUnread == 1) "1 new message" else "$newlyUnread new messages"
            }
            newlyUnread
        } catch (e: Exception) {
            statusLine = e.message ?: "fetch failed"
            0
        }
    }

    fun unreadCount(forUsername: String): Int {
        val key = forUsername.lowercase()
        return inbox.count { !it.outbound && it.fromUsername.lowercase() == key && it.id in unreadIDs }
    }

    fun markChatRead(username: String) {
        val key = username.lowercase()
        val ids = inbox.filter { !it.outbound && it.fromUsername.lowercase() == key }.map { it.id }
        if (ids.isEmpty()) return
        val next = unreadIDs - ids.toSet()
        if (next != unreadIDs) {
            unreadIDs = next
            persistUnread()
        }
    }

    fun deleteMessage(id: String) {
        inbox = inbox.filterNot { it.id == id }
        if (id in unreadIDs) {
            unreadIDs = unreadIDs - id
            persistUnread()
        }
        store.saveKeptMessages(inbox)
    }

    fun recordOutbound(id: String, toUsername: String, plaintext: String) {
        val local = LocalMessage(
            id = id,
            fromUsername = toUsername,
            plaintext = plaintext,
            createdAtEpochMs = System.currentTimeMillis(),
            keptLocally = true,
            outbound = true,
        )
        if (inbox.none { it.id == local.id }) {
            inbox = listOf(local) + inbox
            store.saveKeptMessages(inbox)
        }
    }

    fun deleteChat(fromUsername: String) {
        val key = fromUsername.lowercase()
        val removed = inbox.filter { it.fromUsername.lowercase() == key }.map { it.id }
        inbox = inbox.filterNot { it.fromUsername.lowercase() == key }
        val next = unreadIDs - removed.toSet()
        if (next != unreadIDs) {
            unreadIDs = next
            persistUnread()
        }
        store.saveKeptMessages(inbox)
    }

    fun chatSummaries(): List<ChatSummary> {
        return inbox.groupBy { it.fromUsername.lowercase() }
            .values
            .mapNotNull { msgs ->
                val latest = msgs.maxByOrNull { it.createdAtEpochMs } ?: return@mapNotNull null
                val unread = msgs.count { !it.outbound && it.id in unreadIDs }
                ChatSummary(latest.fromUsername, latest, msgs.size, unread)
            }
            .sortedByDescending { it.latest.createdAtEpochMs }
    }

    fun messages(fromUsername: String): List<LocalMessage> {
        val key = fromUsername.lowercase()
        return inbox.filter { it.fromUsername.lowercase() == key }
            .sortedBy { it.createdAtEpochMs }
    }

    fun deviceId(): String {
        val androidId = Settings.Secure.getString(
            getApplication<Application>().contentResolver,
            Settings.Secure.ANDROID_ID,
        )
        return androidId ?: java.util.UUID.randomUUID().toString()
    }

    private fun persistUnread() {
        prefs.edit().putStringSet(KEY_UNREAD, unreadIDs).apply()
    }

    private fun parseIso(raw: String?): Long? {
        if (raw.isNullOrBlank()) return null
        return try {
            Instant.parse(raw).toEpochMilli()
        } catch (_: DateTimeParseException) {
            null
        }
    }

    companion object {
        private const val KEY_SERVER = "aesms.serverURL"
        private const val KEY_USER = "aesms.username"
        private const val KEY_UNREAD = "aesms.unreadIDs"
    }
}

class AeSMSApp : Application()
