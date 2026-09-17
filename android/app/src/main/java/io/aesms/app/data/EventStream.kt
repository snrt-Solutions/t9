package io.aesms.app.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okio.BufferedSource
import java.util.concurrent.TimeUnit

/** Long-lived SSE to /v1/events — refresh inbox when a message lands. */
class EventStream {
    private val client = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .connectTimeout(30, TimeUnit.SECONDS)
        .build()

    private var job: Job? = null

    fun start(scope: CoroutineScope, base: String, token: String, onMessage: () -> Unit) {
        stop()
        job = scope.launch(Dispatchers.IO) {
            while (isActive) {
                try {
                    listen(base, token, onMessage)
                } catch (_: Exception) {
                    delay(2_000)
                }
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    private fun listen(base: String, token: String, onMessage: () -> Unit) {
        ApiClient().assertTransitSafe(base)
        val url = base.trimEnd('/') + "/v1/events"
        val req = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $token")
            .header("Accept", "text/event-stream")
            .build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("bad SSE response")
            val source = resp.body?.source() ?: return
            readLines(source) { line ->
                if (line.startsWith("event: message") || line.contains("\"event\":\"message\"")) {
                    onMessage()
                }
            }
        }
    }

    private fun readLines(source: BufferedSource, onLine: (String) -> Unit) {
        while (!source.exhausted()) {
            val line = source.readUtf8Line() ?: break
            onLine(line)
        }
    }
}
