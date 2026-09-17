package io.aesms.app.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import io.aesms.app.AppViewModel
import io.aesms.app.Phase
import io.aesms.app.ui.theme.FieldLabel
import io.aesms.app.ui.theme.GhostButton
import io.aesms.app.ui.theme.PrimaryButton
import io.aesms.app.ui.theme.ScreenChrome
import io.aesms.app.ui.theme.T9Theme
import io.aesms.app.util.AppLock
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun WaitingReleaseScreen(vm: AppViewModel) {
    var dots by remember { mutableIntStateOf(0) }
    var copied by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    DisposableEffect(vm.pendingID) {
        val job = scope.launch {
            while (isActive) {
                dots++
                try {
                    val id = vm.pendingID ?: break
                    val res = withContext(Dispatchers.IO) { vm.api.pollPending(vm.serverURL, id) }
                    vm.setStatus("status ${res.status}")
                    if (res.status == "approved" && !res.deviceToken.isNullOrEmpty()) {
                        vm.updateDeviceToken(res.deviceToken)
                        vm.goToPhase(Phase.Mailbox)
                        break
                    } else if (res.status == "denied") {
                        vm.setStatus("denied on web")
                        break
                    }
                } catch (e: Exception) {
                    vm.setStatus(e.message ?: "poll failed")
                }
                delay(1_500)
            }
        }
        onDispose { job.cancel() }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(T9Theme.bg)
            .verticalScroll(rememberScrollState())
            .padding(vertical = T9Theme.space2),
    ) {
        ScreenChrome(
            title = "Approve on the site",
            subtitle = "Open the release page, enter username + live TOTP, and approve this pending ID.",
        ) {
            FieldLabel("Pending ID")
            Spacer(Modifier.height(8.dp))
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(T9Theme.surface)
                    .border(T9Theme.stroke, T9Theme.hair.copy(alpha = 0.55f))
                    .clickable {
                        val id = vm.pendingID ?: return@clickable
                        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        cm.setPrimaryClip(ClipData.newPlainText("pending_id", id))
                        copied = true
                        scope.launch {
                            delay(1_500)
                            copied = false
                        }
                    }
                    .padding(14.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(vm.pendingID ?: "-", style = T9Theme.text(13, FontWeight.Medium), modifier = Modifier.weight(1f))
                Text(
                    if (copied) "Copied" else "Copy",
                    style = T9Theme.text(12, FontWeight.SemiBold).copy(
                        color = if (copied) T9Theme.teal else T9Theme.accent,
                    ),
                )
            }
            Spacer(Modifier.height(T9Theme.space2))
            Row(verticalAlignment = Alignment.CenterVertically) {
                repeat(3) { i ->
                    androidx.compose.foundation.layout.Box(
                        Modifier
                            .padding(end = 8.dp)
                            .size(8.dp)
                            .background(
                                if (i == dots % 3) T9Theme.teal else T9Theme.ink.copy(alpha = 0.18f),
                                CircleShape,
                            ),
                    )
                }
                Text("Polling for approval", style = T9Theme.text(13).copy(color = T9Theme.muted))
            }
            vm.pendingID?.let { id ->
                Spacer(Modifier.height(12.dp))
                Text(
                    "${vm.serverURL.trimEnd('/')}/release.html?pending_id=$id",
                    style = T9Theme.text(12).copy(color = T9Theme.accent),
                )
            }
            if (vm.statusLine.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text(vm.statusLine, style = T9Theme.text(13).copy(color = T9Theme.muted))
            }
            GhostButton("Cancel") { vm.goToPhase(Phase.Credentials) }
        }
    }
}

@Composable
fun LockGateScreen(vm: AppViewModel, activity: FragmentActivity) {
    var busy by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun unlock() {
        scope.launch {
            busy = true
            val ok = AppLock.authenticate(activity)
            failed = !ok
            if (ok) vm.unlockMailbox()
            busy = false
        }
    }

    DisposableEffect(Unit) {
        unlock()
        onDispose { }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(T9Theme.bg)
            .padding(horizontal = T9Theme.pageInset, vertical = T9Theme.space4),
    ) {
        Text("AeSMS", style = T9Theme.text(32, FontWeight.Bold))
        Spacer(Modifier.height(8.dp))
        Text("Locked", style = T9Theme.text(20, FontWeight.SemiBold))
        Spacer(Modifier.height(8.dp))
        Text(
            "Unlock with ${AppLock.biometryLabel(activity)} or your device passcode to open the mailbox.",
            style = T9Theme.text(15).copy(color = T9Theme.muted),
        )
        Spacer(Modifier.height(T9Theme.space3))
        PrimaryButton(
            title = if (busy) "Unlocking…" else "Unlock",
            tint = T9Theme.accent,
            busy = busy,
            onClick = { unlock() },
        )
        if (failed) {
            Spacer(Modifier.height(12.dp))
            Text("Authentication failed", style = T9Theme.text(13).copy(color = T9Theme.warn))
        }
    }
}
