import SwiftUI

struct InboxView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false

    var body: some View {
        ScrollView {
            ScreenChrome(
                title: "Inbox",
                subtitle: "Successful fetch deletes ciphertext on the server."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        if app.pushOnline {
                            Text("LIVE")
                                .font(T9Theme.font(10, .semibold))
                                .tracking(1.4)
                                .foregroundStyle(T9Theme.teal)
                        }
                        Spacer()
                        PrimaryButton(title: "Fetch", tint: T9Theme.accent, busy: busy) {
                            Task { await fetch() }
                        }
                        .frame(maxWidth: 160)
                    }

                    if app.inbox.isEmpty {
                        Text("Empty tray")
                            .font(T9Theme.font(15))
                            .foregroundStyle(T9Theme.muted)
                            .padding(.vertical, 28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(app.inbox.enumerated()), id: \.element.id) { idx, msg in
                                if idx > 0 { RowDivider() }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(msg.fromUsername)
                                        .font(T9Theme.font(12, .semibold))
                                        .foregroundStyle(T9Theme.teal)
                                    Text(msg.plaintext)
                                        .font(T9Theme.font(16))
                                        .foregroundStyle(T9Theme.ink)
                                }
                                .padding(.vertical, 14)
                            }
                        }
                        .padding(.horizontal, 4)
                    }

                    if !app.statusLine.isEmpty {
                        Text(app.statusLine)
                            .font(T9Theme.font(12))
                            .foregroundStyle(T9Theme.muted)
                    }
                }
            }
        }
        .onAppear {
            if app.inbox.isEmpty {
                app.inbox = app.store.loadKeptMessages()
            }
        }
    }

    private func fetch() async {
        busy = true
        defer { busy = false }
        await app.fetchInboxQuiet()
        app.statusLine = "fetched"
    }
}
