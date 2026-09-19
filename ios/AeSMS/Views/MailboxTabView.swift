import SwiftUI

struct MailboxTabView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView {
            InboxView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                .badge(app.unreadTotal == 0 ? nil : Text("\(app.unreadTotal)"))

            ContactsView()
                .tabItem { Label("Contacts", systemImage: "person.crop.rectangle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(T9Theme.accent)
        .onAppear {
            app.startPushIfNeeded()
            Task { await app.fetchInboxQuiet() }
        }
    }
}
