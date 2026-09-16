import SwiftUI

struct MailboxTabView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView {
            InboxView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
            ComposerView()
                .tabItem { Label("Compose", systemImage: "square.and.pencil") }
            ContactsView()
                .tabItem { Label("Contacts", systemImage: "qrcode") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(T9Theme.accent)
        .onAppear { app.startPushIfNeeded() }
    }
}
