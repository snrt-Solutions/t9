package io.aesms.app.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Contacts
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import io.aesms.app.AppViewModel
import io.aesms.app.Phase
import io.aesms.app.crypto.base64Url
import io.aesms.app.data.ChatSummary
import io.aesms.app.data.Contact
import io.aesms.app.data.LocalMessage
import io.aesms.app.ui.theme.EmptyStateBlock
import io.aesms.app.ui.theme.FieldLabel
import io.aesms.app.ui.theme.GhostButton
import io.aesms.app.ui.theme.PrimaryButton
import io.aesms.app.ui.theme.ScreenChrome
import io.aesms.app.ui.theme.SecondaryButton
import io.aesms.app.ui.theme.StatusBadge
import io.aesms.app.ui.theme.SurfacePanel
import io.aesms.app.ui.theme.T9TextField
import io.aesms.app.ui.theme.T9Theme
import io.aesms.app.ui.theme.rememberKeyboardDismiss
import io.aesms.app.ui.theme.t9KeyboardDismiss
import io.aesms.app.util.Grapheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.util.Date

@Composable
fun MailboxScreen(vm: AppViewModel) {
    var tab by remember { mutableIntStateOf(0) }
    var openChat by remember { mutableStateOf<String?>(null) }
    var pickingNewChat by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        vm.startPushIfNeeded()
        vm.fetchInboxQuiet()
    }

    if (openChat != null) {
        ChatThreadScreen(vm, openChat!!) { openChat = null }
        return
    }

    if (pickingNewChat) {
        NewChatScreen(
            vm = vm,
            onPick = { username ->
                pickingNewChat = false
                openChat = username
            },
            onBack = { pickingNewChat = false },
        )
        return
    }

    Scaffold(
        containerColor = T9Theme.bg,
        bottomBar = {
            NavigationBar(containerColor = T9Theme.surface) {
                val items = listOf(
                    Triple("Chats", Icons.AutoMirrored.Filled.Chat, vm.unreadTotal),
                    Triple("Contacts", Icons.Default.Contacts, 0),
                    Triple("Settings", Icons.Default.Settings, 0),
                )
                items.forEachIndexed { index, (label, icon, badge) ->
                    NavigationBarItem(
                        selected = tab == index,
                        onClick = { tab = index },
                        icon = {
                            Box {
                                Icon(icon, contentDescription = label)
                                if (badge > 0 && index == 0) {
                                    Text(
                                        "$badge",
                                        style = T9Theme.text(10, FontWeight.Bold).copy(color = Color.White),
                                        modifier = Modifier
                                            .align(Alignment.TopEnd)
                                            .background(T9Theme.accent)
                                            .padding(horizontal = 4.dp, vertical = 1.dp),
                                    )
                                }
                            }
                        },
                        label = { Text(label, style = T9Theme.text(11)) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = T9Theme.accent,
                            selectedTextColor = T9Theme.accent,
                            indicatorColor = T9Theme.accent.copy(alpha = 0.12f),
                        ),
                    )
                }
            }
        },
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            when (tab) {
                0 -> InboxScreen(
                    vm = vm,
                    onOpen = { openChat = it },
                    onNewChat = { pickingNewChat = true },
                )
                1 -> ContactsScreen(vm)
                2 -> SettingsScreen(vm)
            }
        }
    }
}

@Composable
fun InboxScreen(vm: AppViewModel, onOpen: (String) -> Unit, onNewChat: () -> Unit) {
    var busy by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<ChatSummary?>(null) }
    val scope = rememberCoroutineScope()
    val chats = vm.chatSummaries()

    Column(modifier = Modifier.fillMaxSize().background(T9Theme.bg)) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = T9Theme.pageInset, vertical = T9Theme.space1),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Chats", style = T9Theme.text(26, FontWeight.Bold))
                    Spacer(Modifier.width(12.dp))
                    if (vm.pushOnline) StatusBadge("Live")
                }
                Text(
                    "Local copies only. Long-press a chat to clear it.",
                    style = T9Theme.text(14).copy(color = T9Theme.muted),
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = {
                    scope.launch {
                        busy = true
                        val n = vm.fetchInboxQuiet()
                        vm.setStatus(if (n > 0) (if (n == 1) "1 new message" else "$n new messages") else "fetched")
                        busy = false
                    }
                }) {
                    Text(if (busy) "…" else "Fetch", style = T9Theme.text(14, FontWeight.SemiBold).copy(color = T9Theme.accent))
                }
                TextButton(onClick = onNewChat) {
                    Icon(
                        Icons.Default.Edit,
                        contentDescription = "New chat",
                        tint = T9Theme.accent,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
        }
        Box(
            Modifier
                .fillMaxWidth()
                .height(T9Theme.rule)
                .background(T9Theme.hair.copy(alpha = 0.35f)),
        )
        if (chats.isEmpty()) {
            Box(modifier = Modifier.padding(horizontal = T9Theme.pageInset)) {
                EmptyStateBlock(
                    title = "No chats yet",
                    detail = "Fetch sealed messages, or start a new chat with a QR contact.",
                )
            }
        } else {
            LazyColumn {
                items(chats, key = { it.id }) { chat ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clickable { onOpen(chat.username) }
                            .padding(horizontal = T9Theme.pageInset, vertical = 14.dp),
                    ) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(chat.username, style = T9Theme.text(15, FontWeight.SemiBold).copy(color = T9Theme.teal))
                            if (chat.unreadCount > 0) {
                                Text(
                                    "${chat.unreadCount}",
                                    style = T9Theme.text(11, FontWeight.Bold).copy(color = Color.White),
                                    modifier = Modifier
                                        .background(T9Theme.accent)
                                        .padding(horizontal = 7.dp, vertical = 3.dp),
                                )
                            } else {
                                Text("${chat.count}", style = T9Theme.text(12, FontWeight.Medium).copy(color = T9Theme.muted))
                            }
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(
                            if (chat.latest.outbound) "You: ${chat.latest.plaintext}" else chat.latest.plaintext,
                            style = T9Theme.text(14, if (chat.unreadCount > 0) FontWeight.SemiBold else FontWeight.Normal),
                            maxLines = 2,
                        )
                        TextButton(onClick = { pendingDelete = chat }) {
                            Text("Delete chat", style = T9Theme.text(12).copy(color = T9Theme.warn))
                        }
                    }
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(1.dp)
                            .background(T9Theme.hair.copy(alpha = 0.12f)),
                    )
                }
            }
        }
        if (vm.statusLine.isNotEmpty()) {
            Text(
                vm.statusLine,
                style = T9Theme.text(12).copy(color = T9Theme.muted),
                modifier = Modifier.padding(horizontal = T9Theme.pageInset, vertical = 10.dp),
            )
        }
    }

    pendingDelete?.let { chat ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("Delete chat with ${chat.username}?") },
            text = { Text("Removes local messages from this sender. Server copies are already gone after fetch.") },
            confirmButton = {
                TextButton(onClick = {
                    vm.deleteChat(chat.username)
                    pendingDelete = null
                }) { Text("Delete chat") }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) { Text("Cancel") }
            },
        )
    }
}

@Composable
fun ChatThreadScreen(vm: AppViewModel, username: String, onBack: () -> Unit) {
    var confirmClear by remember { mutableStateOf(false) }
    var body by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    val messages = vm.messages(username)
    val df = remember { DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val dismissKeyboard = rememberKeyboardDismiss()
    val contact = vm.contacts.firstOrNull { it.username.equals(username, true) }
    val graphemes = Grapheme.count(body)
    val over = graphemes > 160
    val canSend = !over && body.isNotEmpty() && contact != null && !sending

    LaunchedEffect(username) { vm.markChatRead(username) }
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.lastIndex)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(T9Theme.bg)
            .imePadding(),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = T9Theme.pageInset, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            GhostButton("Back") { onBack() }
            Text(username, style = T9Theme.text(16, FontWeight.SemiBold))
            TextButton(onClick = { confirmClear = true }, enabled = messages.isNotEmpty()) {
                Text("Clear", style = T9Theme.text(14, FontWeight.SemiBold).copy(color = T9Theme.warn))
            }
        }
        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
            if (messages.isEmpty()) {
                Box(modifier = Modifier.padding(horizontal = T9Theme.pageInset)) {
                    EmptyStateBlock(
                        if (contact == null) "Unknown contact" else "No messages yet",
                        if (contact == null) {
                            "This peer is not in your contact list. Re-pair via Contacts to send."
                        } else {
                            "Say hello — messages stay sealed end to end."
                        },
                    )
                }
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = T9Theme.pageInset),
                ) {
                    items(messages, key = { it.id }) { msg ->
                        MessageBubble(msg, df)
                        Spacer(Modifier.height(8.dp))
                    }
                }
            }
        }
        Column(
            Modifier
                .fillMaxWidth()
                .background(T9Theme.bg)
                .t9KeyboardDismiss()
                .padding(horizontal = T9Theme.pageInset, vertical = 10.dp),
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(T9Theme.rule)
                    .background(T9Theme.hair.copy(alpha = 0.35f)),
            )
            Spacer(Modifier.height(10.dp))
            if (contact == null) {
                Text(
                    "Re-pair this contact to send.",
                    style = T9Theme.text(12).copy(color = T9Theme.warn),
                )
                Spacer(Modifier.height(8.dp))
            }
            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                T9TextField(
                    value = body,
                    onValueChange = { body = it },
                    placeholder = "Message",
                    singleLine = false,
                    minHeight = 44.dp,
                    enabled = !sending && contact != null,
                    modifier = Modifier.weight(1f),
                )
                TextButton(
                    onClick = {
                        dismissKeyboard()
                        scope.launch {
                            val tok = vm.deviceToken ?: return@launch
                            val peer = contact ?: run {
                                status = "re-pair via Contacts"
                                return@launch
                            }
                            sending = true
                            status = "Sending…"
                            try {
                                vm.fetchInboxQuiet()
                                val plain = body
                                val sealed = withContext(Dispatchers.Default) {
                                    vm.keys.seal(plain, peer.pubkey)
                                }
                                val id = withContext(Dispatchers.IO) {
                                    vm.api.postMessage(
                                        vm.serverURL,
                                        tok,
                                        peer.username,
                                        sealed.base64Url(),
                                        graphemes,
                                        vm.keys.publicKeyB64(),
                                    )
                                }
                                vm.recordOutbound(id, peer.username, plain)
                                status = ""
                                body = ""
                            } catch (e: Exception) {
                                status = e.message ?: "send failed"
                            } finally {
                                sending = false
                            }
                        }
                    },
                    enabled = canSend,
                ) {
                    Text(
                        if (sending) "…" else "Send",
                        style = T9Theme.text(14, FontWeight.SemiBold).copy(
                            color = if (canSend) T9Theme.accent else T9Theme.muted,
                        ),
                    )
                }
            }
            Spacer(Modifier.height(6.dp))
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    "$graphemes/160",
                    style = T9Theme.text(12, FontWeight.Medium).copy(
                        color = if (over) T9Theme.warn else T9Theme.muted,
                    ),
                )
                if (status.isNotEmpty()) {
                    Text(
                        status,
                        style = T9Theme.text(12).copy(color = if (sending) T9Theme.teal else T9Theme.muted),
                        maxLines = 1,
                    )
                }
            }
        }
    }

    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text("Clear chat with $username?") },
            text = { Text("Deletes all local messages in this chat (sent and received).") },
            confirmButton = {
                TextButton(onClick = {
                    vm.deleteChat(username)
                    confirmClear = false
                }) { Text("Clear chat") }
            },
            dismissButton = {
                TextButton(onClick = { confirmClear = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
fun NewChatScreen(vm: AppViewModel, onPick: (String) -> Unit, onBack: () -> Unit) {
    val sorted = vm.contacts.sortedBy { it.username.lowercase() }

    Column(modifier = Modifier.fillMaxSize().background(T9Theme.bg)) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = T9Theme.pageInset, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            GhostButton("Back") { onBack() }
            Text("New chat", style = T9Theme.text(16, FontWeight.SemiBold))
            Spacer(Modifier.width(64.dp))
        }
        Box(
            Modifier
                .fillMaxWidth()
                .height(T9Theme.rule)
                .background(T9Theme.hair.copy(alpha = 0.35f)),
        )
        if (sorted.isEmpty()) {
            Box(modifier = Modifier.padding(horizontal = T9Theme.pageInset, vertical = T9Theme.space2)) {
                EmptyStateBlock(
                    title = "No contacts yet",
                    detail = "Pair via QR on the Contacts tab first — there is no server address book.",
                )
            }
        } else {
            LazyColumn {
                items(sorted, key = { it.id }) { contact ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clickable { onPick(contact.username) }
                            .padding(horizontal = T9Theme.pageInset, vertical = 14.dp),
                    ) {
                        Text(contact.username, style = T9Theme.text(15, FontWeight.SemiBold))
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "srv ${contact.serverFingerprint}",
                            style = T9Theme.text(11).copy(
                                color = if (contact.serverFingerprint == vm.fingerprint) {
                                    T9Theme.teal
                                } else {
                                    T9Theme.warn
                                },
                            ),
                        )
                    }
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(1.dp)
                            .background(T9Theme.hair.copy(alpha = 0.12f)),
                    )
                }
            }
        }
    }
}

@Composable
private fun MessageBubble(msg: LocalMessage, df: DateFormat) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = if (msg.outbound) Arrangement.End else Arrangement.Start,
    ) {
        Column(
            Modifier
                .fillMaxWidth(0.82f)
                .background(if (msg.outbound) T9Theme.ink.copy(alpha = 0.06f) else T9Theme.surface)
                .border(
                    T9Theme.stroke,
                    T9Theme.hair.copy(alpha = if (msg.outbound) 0.18f else 0.4f),
                    RectangleShape,
                )
                .padding(horizontal = 14.dp, vertical = 12.dp),
            horizontalAlignment = if (msg.outbound) Alignment.End else Alignment.Start,
        ) {
            Text(
                if (msg.outbound) "You" else msg.fromUsername,
                style = T9Theme.text(11, FontWeight.SemiBold).copy(
                    color = if (msg.outbound) T9Theme.muted else T9Theme.teal,
                ),
            )
            Spacer(Modifier.height(6.dp))
            Text(
                msg.plaintext,
                style = T9Theme.text(15),
                textAlign = if (msg.outbound) TextAlign.End else TextAlign.Start,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                df.format(Date(msg.createdAtEpochMs)),
                style = T9Theme.text(11).copy(color = T9Theme.muted),
            )
        }
    }
}

@Composable
fun ContactsScreen(vm: AppViewModel) {
    var scanPayload by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var pairCode by remember { mutableStateOf("") }
    var pairBusy by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val dismissKeyboard = rememberKeyboardDismiss()

    fun pairUri(): String {
        if (pairCode.isEmpty()) return ""
        val c = Uri.encode(pairCode)
        val srv = Uri.encode(vm.fingerprint)
        return "aesms://pair?c=$c&srv=$srv"
    }

    fun savePeer(username: String, pubkey: String, srv: String): Boolean {
        if (username.equals(vm.username, true)) {
            status = "that is your own QR"
            return false
        }
        val existingIdx = vm.contacts.indexOfFirst { it.username.equals(username, true) }
        if (existingIdx >= 0) {
            val existing = vm.contacts[existingIdx]
            if (existing.pubkey == pubkey) {
                status = "already saved: $username"
                return false
            }
            // Re-pair with a corrected pubkey (fixes one-way decrypt after a bad first save).
            val updated = existing.copy(
                pubkey = pubkey,
                serverFingerprint = srv.ifEmpty { existing.serverFingerprint },
            )
            val next = vm.contacts.toMutableList()
            next[existingIdx] = updated
            vm.updateContacts(next)
            status = "updated contact key: $username"
            return true
        }
        status = if (srv.isNotEmpty() && vm.fingerprint.isNotEmpty() && srv != vm.fingerprint) {
            "warning: server fingerprint mismatch - contact saved with flag"
        } else {
            "contact saved: $username"
        }
        vm.updateContacts(
            vm.contacts + Contact(username, pubkey, srv),
        )
        return true
    }

    suspend fun refreshOffer() {
        val tok = vm.deviceToken
        if (tok == null) {
            status = "device token required"
            return
        }
        pairBusy = true
        try {
            val resp = withContext(Dispatchers.IO) {
                vm.api.createPairOffer(vm.serverURL, tok, vm.keys.publicKeyB64())
            }
            pairCode = resp.code
            if (status.startsWith("Minting") || status.isEmpty() || status == "device token required") {
                status = "pair code rotating"
            }
        } catch (e: Exception) {
            val msg = e.message.orEmpty()
            status = if (msg.contains("handshake pending")) "handshake pending — waiting for peer" else msg
        } finally {
            pairBusy = false
        }
    }

    DisposableEffect(Unit) {
        val offerJob = scope.launch {
            while (isActive) {
                refreshOffer()
                delay(45_000)
            }
        }
        val pollJob = scope.launch {
            while (isActive) {
                val tok = vm.deviceToken
                if (tok != null) {
                    try {
                        val resp = withContext(Dispatchers.IO) { vm.api.pollPairOffer(vm.serverURL, tok) }
                        if (resp.status == "claimed" && resp.peer != null) {
                            if (savePeer(resp.peer.username, resp.peer.pubkey, vm.fingerprint)) {
                                status = "paired with ${resp.peer.username}"
                            }
                            refreshOffer()
                        }
                    } catch (_: Exception) {
                    }
                }
                delay(2_000)
            }
        }
        onDispose {
            offerJob.cancel()
            pollJob.cancel()
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(T9Theme.bg)
            .t9KeyboardDismiss()
            .verticalScroll(rememberScrollState())
            .padding(vertical = T9Theme.space2),
    ) {
        ScreenChrome(
            title = "Contacts",
            subtitle = "No search. No invites. Rotating pair QR — paste in person.",
        ) {
            FieldLabel("My pair QR")
            Spacer(Modifier.height(12.dp))
            val uri = pairUri()
            val bmp = remember(uri) { if (uri.isEmpty()) null else qrBitmap(uri) }
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(212.dp)
                    .background(T9Theme.surface)
                    .border(T9Theme.stroke, T9Theme.hair.copy(alpha = 0.45f)),
                contentAlignment = Alignment.Center,
            ) {
                if (bmp != null) {
                    Image(bmp.asImageBitmap(), contentDescription = "Pair QR", modifier = Modifier.size(180.dp))
                } else {
                    Text(
                        if (pairBusy) "Minting pair code…" else "Waiting for pair code",
                        style = T9Theme.text(13).copy(color = T9Theme.muted),
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(T9Theme.surface)
                    .border(T9Theme.stroke, T9Theme.hair.copy(alpha = 0.45f))
                    .clickable(enabled = pairCode.isNotEmpty()) {
                        val link = pairUri()
                        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        cm.setPrimaryClip(ClipData.newPlainText("pair", link))
                        copied = true
                        scope.launch {
                            delay(1_500)
                            copied = false
                        }
                    }
                    .padding(14.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    if (pairCode.isEmpty()) "aesms://pair?c=…" else uri,
                    style = T9Theme.text(10).copy(color = T9Theme.muted),
                    modifier = Modifier.weight(1f),
                    maxLines = 2,
                )
                Text(
                    if (copied) "Copied" else "Copy",
                    style = T9Theme.text(12, FontWeight.SemiBold).copy(
                        color = if (copied) T9Theme.teal else T9Theme.accent,
                    ),
                )
            }
            Spacer(Modifier.height(T9Theme.space3))
            FieldLabel("Add contact")
            Spacer(Modifier.height(10.dp))
            T9TextField(
                value = scanPayload,
                onValueChange = { scanPayload = it },
                placeholder = "aesms://pair?c=…",
            )
            Spacer(Modifier.height(10.dp))
            PrimaryButton(
                title = "Claim from paste",
                tint = T9Theme.teal,
                busy = pairBusy,
                onClick = {
                    dismissKeyboard()
                    scope.launch {
                        val trimmed = scanPayload.trim()
                        if (trimmed.startsWith("aesms://contact")) {
                            val uriParsed = Uri.parse(trimmed)
                            val u = uriParsed.getQueryParameter("u").orEmpty()
                            val pk = uriParsed.getQueryParameter("pk").orEmpty()
                            val srv = uriParsed.getQueryParameter("srv").orEmpty()
                            if (u.isEmpty() || pk.isEmpty()) {
                                status = "missing fields"
                            } else {
                                savePeer(u, pk, srv)
                                scanPayload = ""
                            }
                            return@launch
                        }
                        val uriParsed = Uri.parse(trimmed)
                        if (uriParsed.scheme != "aesms" || uriParsed.host != "pair") {
                            status = "bad payload"
                            return@launch
                        }
                        val code = uriParsed.getQueryParameter("c").orEmpty()
                        val srv = uriParsed.getQueryParameter("srv").orEmpty()
                        if (code.isEmpty()) {
                            status = "missing fields"
                            return@launch
                        }
                        val tok = vm.deviceToken
                        if (tok == null) {
                            status = "device token required"
                            return@launch
                        }
                        pairBusy = true
                        try {
                            val resp = withContext(Dispatchers.IO) {
                                vm.api.claimPairOffer(vm.serverURL, tok, code, vm.keys.publicKeyB64())
                            }
                            val peerSrv = srv.ifEmpty { vm.fingerprint }
                            if (savePeer(resp.peer.username, resp.peer.pubkey, peerSrv)) {
                                status = if (srv.isNotEmpty() && vm.fingerprint.isNotEmpty() && srv != vm.fingerprint) {
                                    "paired with ${resp.peer.username} (srv mismatch flag)"
                                } else {
                                    "paired with ${resp.peer.username}"
                                }
                            }
                            scanPayload = ""
                        } catch (e: Exception) {
                            status = e.message ?: "claim failed"
                        } finally {
                            pairBusy = false
                        }
                    }
                },
            )
            if (status.isNotEmpty()) {
                Text(status, style = T9Theme.text(13).copy(color = T9Theme.muted))
            }
            if (vm.contacts.isNotEmpty()) {
                Spacer(Modifier.height(T9Theme.space3))
                FieldLabel("Saved")
                Spacer(Modifier.height(10.dp))
                SurfacePanel {
                    vm.contacts.forEachIndexed { idx, c ->
                        if (idx > 0) {
                            Box(
                                Modifier
                                    .fillMaxWidth()
                                    .height(1.dp)
                                    .background(T9Theme.hair.copy(alpha = 0.12f)),
                            )
                            Spacer(Modifier.height(10.dp))
                        }
                        Text(c.username, style = T9Theme.text(15, FontWeight.SemiBold))
                        Text(
                            "srv ${c.serverFingerprint}",
                            style = T9Theme.text(11).copy(
                                color = if (c.serverFingerprint == vm.fingerprint) T9Theme.teal else T9Theme.warn,
                            ),
                        )
                        Spacer(Modifier.height(10.dp))
                    }
                }
            }
        }
    }
}

@Composable
fun SettingsScreen(vm: AppViewModel) {
    var passphrase by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var backupB64 by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val dismissKeyboard = rememberKeyboardDismiss()

    Column(
        Modifier
            .fillMaxSize()
            .background(T9Theme.bg)
            .t9KeyboardDismiss()
            .verticalScroll(rememberScrollState())
            .padding(vertical = T9Theme.space2),
    ) {
        ScreenChrome(title = "Settings", subtitle = "Local keys and device session only.") {
            SurfacePanel {
                meta("Server", vm.serverURL)
                meta("User", vm.username)
                meta("Fingerprint", vm.fingerprint)
                meta("Pubkey", vm.keys.publicKeyB64().take(24) + "…")
                meta("Push", if (vm.pushOnline) "SSE online" else "offline")
            }
            Spacer(Modifier.height(T9Theme.space3))
            FieldLabel("Encrypted backup")
            Spacer(Modifier.height(12.dp))
            T9TextField(value = passphrase, onValueChange = { passphrase = it }, placeholder = "passphrase")
            Spacer(Modifier.height(12.dp))
            SecondaryButton(title = "Export backup", onClick = {
                dismissKeyboard()
                try {
                    val id = vm.keys.loadOrCreateIdentity()
                    val priv = android.util.Base64.encodeToString(id.privateKeyRaw, android.util.Base64.NO_WRAP)
                    val data = vm.store.exportBackup(passphrase, priv, id.publicKeyB64, vm.contacts)
                    backupB64 = android.util.Base64.encodeToString(data, android.util.Base64.NO_WRAP)
                    status = "backup ready - copy the blob"
                } catch (e: Exception) {
                    status = e.message ?: "export failed"
                }
            })
            Spacer(Modifier.height(8.dp))
            SecondaryButton(title = "Restore from paste", onClick = {
                dismissKeyboard()
                try {
                    val data = android.util.Base64.decode(backupB64, android.util.Base64.DEFAULT)
                    val (priv, pub, contacts) = vm.store.importBackup(data, passphrase)
                    vm.keys.replaceIdentity(priv, pub)
                    vm.updateContacts(contacts)
                    status = "restored keys+contacts - re-release device on web"
                } catch (e: Exception) {
                    status = e.message ?: "restore failed"
                }
            })
            Spacer(Modifier.height(8.dp))
            T9TextField(
                value = backupB64,
                onValueChange = { backupB64 = it },
                singleLine = false,
                minHeight = 88.dp,
            )
            Text(
                "Restoring keys still requires a fresh web device release.",
                style = T9Theme.text(12).copy(color = T9Theme.muted),
            )
            if (status.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text(status, style = T9Theme.text(13).copy(color = T9Theme.muted))
            }
            Spacer(Modifier.height(T9Theme.space3))
            PrimaryButton(title = "Lock now", tint = T9Theme.ink, onClick = { vm.lockMailbox() })
            Spacer(Modifier.height(12.dp))
            PrimaryButton(
                title = "Revoke device token",
                tint = T9Theme.warn,
                onClick = {
                    scope.launch {
                        val tok = vm.deviceToken ?: return@launch
                        try {
                            withContext(Dispatchers.IO) { vm.api.revoke(vm.serverURL, tok) }
                            vm.updateDeviceToken(null)
                            vm.stopPush()
                            vm.lockMailbox()
                            vm.goToPhase(Phase.Server)
                            status = "revoked"
                        } catch (e: Exception) {
                            status = e.message ?: "revoke failed"
                        }
                    }
                },
            )
        }
    }
}

@Composable
private fun meta(k: String, v: String) {
    Column(modifier = Modifier.padding(vertical = 6.dp)) {
        Text(
            k.uppercase(),
            style = T9Theme.text(10, FontWeight.SemiBold).copy(
                color = T9Theme.muted,
                letterSpacing = 1.2.sp,
            ),
        )
        Text(v.ifEmpty { "-" }, style = T9Theme.text(13))
    }
}

private fun qrBitmap(content: String): Bitmap {
    val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, 512, 512)
    val bmp = Bitmap.createBitmap(matrix.width, matrix.height, Bitmap.Config.RGB_565)
    for (x in 0 until matrix.width) {
        for (y in 0 until matrix.height) {
            bmp.setPixel(x, y, if (matrix[x, y]) 0xFF000000.toInt() else 0xFFFFFFFF.toInt())
        }
    }
    return bmp
}
