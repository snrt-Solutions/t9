package io.aesms.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.aesms.app.AppViewModel
import io.aesms.app.Phase
import io.aesms.app.ui.theme.FieldLabel
import io.aesms.app.ui.theme.GhostButton
import io.aesms.app.ui.theme.PrimaryButton
import io.aesms.app.ui.theme.ScreenChrome
import io.aesms.app.ui.theme.T9TextField
import io.aesms.app.ui.theme.T9Theme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun ServerURLScreen(vm: AppViewModel) {
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Column(
        Modifier
            .fillMaxSize()
            .background(T9Theme.bg)
            .verticalScroll(rememberScrollState())
            .padding(top = T9Theme.space2, bottom = T9Theme.space3),
    ) {
        Column(modifier = Modifier.padding(horizontal = T9Theme.pageInset)) {
            Row {
                Text("AeSMS", style = T9Theme.text(32, FontWeight.Bold))
                Text(".io", style = T9Theme.text(32, FontWeight.Bold).copy(color = T9Theme.accent))
            }
            Text(
                "Fetch-once messaging. Pure privacy but feels like SMS.",
                style = T9Theme.text(14, FontWeight.Medium).copy(color = T9Theme.muted),
            )
        }
        Spacer(Modifier.height(T9Theme.space3))
        ScreenChrome(
            title = "Point at your host",
            subtitle = "Enter the public base URL from Docker setup or your Tunnel hostname.",
        ) {
            FieldLabel("Server URL")
            Spacer(Modifier.height(8.dp))
            T9TextField(
                value = vm.serverURL,
                onValueChange = { vm.updateServerURL(it) },
                placeholder = "https://app.aesms.io",
            )
            Spacer(Modifier.height(T9Theme.space2))
            PrimaryButton(
                title = "Continue",
                tint = T9Theme.accent,
                busy = busy,
                onClick = {
                    scope.launch {
                        busy = true
                        try {
                            val trimmed = vm.serverURL.trim()
                            vm.updateServerURL(trimmed)
                            val info = withContext(Dispatchers.IO) {
                                vm.api.assertTransitSafe(trimmed)
                                vm.api.getInfo(trimmed)
                            }
                            if (info.setupNeeded == true) {
                                vm.setStatus("Server is in setup mode. Finish /setup.html on the host first.")
                                return@launch
                            }
                            val fp = info.fingerprint.orEmpty()
                            vm.updateFingerprint(fp)
                            vm.setStatus(if (fp.isEmpty()) "connected" else "fp $fp")
                            vm.goToPhase(Phase.Credentials)
                        } catch (e: Exception) {
                            vm.setStatus(e.message ?: "failed")
                        } finally {
                            busy = false
                        }
                    }
                },
            )
            if (vm.statusLine.isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                Text(vm.statusLine, style = T9Theme.text(13).copy(color = T9Theme.muted))
            }
        }
    }
}

@Composable
fun CredentialsScreen(vm: AppViewModel) {
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Column(
        Modifier
            .fillMaxSize()
            .background(T9Theme.bg)
            .verticalScroll(rememberScrollState())
            .padding(vertical = T9Theme.space2),
    ) {
        ScreenChrome(
            title = "Device login",
            subtitle = "Password alone cannot bind this device. Approve the pending login on the web with TOTP.",
        ) {
            FieldLabel("Username")
            Spacer(Modifier.height(8.dp))
            T9TextField(value = vm.username, onValueChange = { vm.saveUsername(it) }, placeholder = "Username")
            Spacer(Modifier.height(T9Theme.space2))
            FieldLabel("Password")
            Spacer(Modifier.height(8.dp))
            T9TextField(value = password, onValueChange = { password = it }, placeholder = "Password")
            Spacer(Modifier.height(T9Theme.space2))
            PrimaryButton(
                title = "Request release",
                tint = T9Theme.teal,
                busy = busy,
                onClick = {
                    scope.launch {
                        busy = true
                        try {
                            val res = withContext(Dispatchers.IO) {
                                vm.api.deviceLogin(vm.serverURL, vm.username, password, vm.deviceId())
                            }
                            vm.updatePendingID(res.pendingId)
                            vm.setStatus("pending ${res.pendingId}")
                            vm.goToPhase(Phase.WaitingRelease)
                        } catch (e: Exception) {
                            vm.setStatus(e.message ?: "login failed")
                        } finally {
                            busy = false
                        }
                    }
                },
            )
            GhostButton("Back") { vm.goToPhase(Phase.Server) }
            if (vm.statusLine.isNotEmpty()) {
                Text(vm.statusLine, style = T9Theme.text(13).copy(color = T9Theme.muted))
            }
        }
    }
}
