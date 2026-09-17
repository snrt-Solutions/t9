package io.aesms.app.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class ApiException(message: String) : Exception(message)

class ApiClient {
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    private val json = Json { ignoreUnknownKeys = true }

    fun assertTransitSafe(base: String) {
        val trimmed = base.trim()
        val uri = java.net.URI(trimmed)
        val scheme = (uri.scheme ?: "").lowercase()
        val host = (uri.host ?: "").lowercase()
        val loopback = host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "10.0.2.2"
        when {
            scheme == "https" -> return
            scheme == "http" && loopback -> return
            else -> throw ApiException("HTTPS required (HTTP only allowed for localhost)")
        }
    }

    suspend fun getInfo(base: String): ServerInfo = get(base, "/v1/info")

    suspend fun deviceLogin(base: String, username: String, password: String, deviceId: String): PendingLoginResponse {
        val body = JSONObject()
            .put("username", username)
            .put("password", password)
            .put("device_id", deviceId)
            .put("assertion", ASSERTION)
        return post(base, "/v1/device/login", body)
    }

    suspend fun pollPending(base: String, id: String): PollResponse =
        get(base, "/v1/device/login/$id")

    suspend fun postMessage(
        base: String,
        token: String,
        to: String,
        ciphertextB64: String,
        graphemes: Int,
        pubkey: String,
    ): String {
        val body = JSONObject()
            .put("to_username", to)
            .put("ciphertext", ciphertextB64)
            .put("graphemes", graphemes)
            .put("pubkey", pubkey)
        val resp: PostMessageResponse = post(base, "/v1/messages", body, token)
        return resp.id ?: java.util.UUID.randomUUID().toString()
    }

    suspend fun fetchMessages(base: String, token: String): MessagesResponse =
        get(base, "/v1/messages", token)

    suspend fun revoke(base: String, token: String) {
        assertTransitSafe(base)
        val req = Request.Builder()
            .url(url(base, "/v1/device/revoke"))
            .post("{}".toRequestBody(JSON))
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw ApiException("revoke failed")
        }
    }

    suspend fun createPairOffer(base: String, token: String, pubkey: String): PairOfferResponse {
        val body = JSONObject().put("pubkey", pubkey)
        return post(base, "/v1/pair/offer", body, token)
    }

    suspend fun pollPairOffer(base: String, token: String): PairPollResponse =
        get(base, "/v1/pair/offer", token)

    suspend fun claimPairOffer(base: String, token: String, code: String, pubkey: String): PairClaimResponse {
        val body = JSONObject().put("code", code).put("pubkey", pubkey)
        return post(base, "/v1/pair/claim", body, token)
    }

    private fun url(base: String, path: String): String =
        base.trimEnd('/') + path

    private inline fun <reified T> get(base: String, path: String, token: String? = null): T {
        assertTransitSafe(base)
        val builder = Request.Builder().url(url(base, path)).get()
        if (token != null) builder.header("Authorization", "Bearer $token")
        return decode(builder.build())
    }

    private inline fun <reified T> post(
        base: String,
        path: String,
        body: JSONObject,
        token: String? = null,
    ): T {
        assertTransitSafe(base)
        val builder = Request.Builder()
            .url(url(base, path))
            .post(body.toString().toRequestBody(JSON))
            .header("Content-Type", "application/json")
        if (token != null) builder.header("Authorization", "Bearer $token")
        return decode(builder.build())
    }

    private inline fun <reified T> decode(req: Request): T {
        client.newCall(req).execute().use { resp ->
            val bytes = resp.body?.bytes() ?: ByteArray(0)
            if (!resp.isSuccessful) {
                val err = runCatching {
                    JSONObject(bytes.toString(Charsets.UTF_8)).optString("error")
                }.getOrNull()
                throw ApiException(if (!err.isNullOrBlank()) err else "HTTP ${resp.code}")
            }
            return json.decodeFromString(bytes.toString(Charsets.UTF_8))
        }
    }

    companion object {
        const val ASSERTION = "aesms-android-mvp-signed-placeholder"
        private val JSON = "application/json; charset=utf-8".toMediaType()
    }
}

@Serializable
data class ServerInfo(
    val name: String? = null,
    @SerialName("base_url") val baseUrl: String? = null,
    val fingerprint: String? = null,
    @SerialName("max_graphemes") val maxGraphemes: Int? = null,
    @SerialName("web_login") val webLogin: Boolean? = null,
    @SerialName("fetch_once") val fetchOnce: Boolean? = null,
    @SerialName("setup_needed") val setupNeeded: Boolean? = null,
    val push: Boolean? = null,
)

@Serializable
data class PendingLoginResponse(
    @SerialName("pending_id") val pendingId: String,
    val status: String,
    @SerialName("release_url") val releaseUrl: String? = null,
    @SerialName("expires_at") val expiresAt: String? = null,
)

@Serializable
data class PollResponse(
    @SerialName("pending_id") val pendingId: String? = null,
    val status: String,
    @SerialName("device_token") val deviceToken: String? = null,
    @SerialName("token_type") val tokenType: String? = null,
)

@Serializable
data class MessagesResponse(val messages: List<WireMessage> = emptyList())

@Serializable
data class WireMessage(
    val id: String,
    @SerialName("from_username") val fromUsername: String,
    val ciphertext: String,
    @SerialName("created_at") val createdAt: String? = null,
)

@Serializable
data class PostMessageResponse(val id: String? = null)

@Serializable
data class PairOfferResponse(
    val code: String,
    @SerialName("expires_at") val expiresAt: String? = null,
)

@Serializable
data class PairPeerDto(val username: String, val pubkey: String)

@Serializable
data class PairPollResponse(
    val status: String,
    val peer: PairPeerDto? = null,
)

@Serializable
data class PairClaimResponse(val peer: PairPeerDto)
