package io.aesms.app

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.fragment.app.FragmentActivity
import io.aesms.app.ui.screens.CredentialsScreen
import io.aesms.app.ui.screens.LockGateScreen
import io.aesms.app.ui.screens.MailboxScreen
import io.aesms.app.ui.screens.ServerURLScreen
import io.aesms.app.ui.screens.WaitingReleaseScreen
import io.aesms.app.ui.theme.T9Theme

class MainActivity : FragmentActivity() {
    private val vm: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            Root(vm = vm, activity = this)
        }
    }
}

@Composable
fun Root(vm: AppViewModel, activity: FragmentActivity) {
    androidx.compose.foundation.layout.Box(
        Modifier
            .fillMaxSize()
            .background(T9Theme.bg),
    ) {
        when (vm.phase) {
            Phase.Server -> ServerURLScreen(vm)
            Phase.Credentials -> CredentialsScreen(vm)
            Phase.WaitingRelease -> WaitingReleaseScreen(vm)
            Phase.Mailbox -> {
                if (vm.unlocked) {
                    MailboxScreen(vm)
                } else {
                    LockGateScreen(vm, activity)
                }
            }
        }
    }
}
