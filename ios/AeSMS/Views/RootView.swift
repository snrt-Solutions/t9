import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            T9Background()
            Group {
                switch app.phase {
                case .server:
                    ServerURLView()
                case .credentials:
                    CredentialsView()
                case .waitingRelease:
                    WaitingReleaseView()
                case .mailbox:
                    if app.unlocked {
                        MailboxTabView()
                    } else {
                        LockGateView()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .environment(\.font, T9Theme.font(15))
        .animation(T9Theme.ease, value: app.phase)
        .animation(T9Theme.ease, value: app.unlocked)
        .onChange(of: app.phase) { _, phase in
            if phase == .mailbox {
                app.startPushIfNeeded()
            } else {
                app.stopPush()
                app.unlocked = false
            }
        }
    }
}
