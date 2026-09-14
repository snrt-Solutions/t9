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
                    MailboxTabView()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .environment(\.font, T9Theme.font(15))
        .animation(T9Theme.ease, value: app.phase)
    }
}
