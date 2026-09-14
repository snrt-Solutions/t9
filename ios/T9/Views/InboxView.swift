import SwiftUI

struct InboxView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: "Fetch-once")
                HStack {
                    Text("Inbox")
                        .font(T9Theme.font(30, .bold))
                    Spacer()
                    IslandButton(title: busy ? "…" : "Fetch", tint: T9Theme.accent) {
                        Task { await fetch() }
                    }
                    .disabled(busy)
                }
                Text("Successful fetch deletes ciphertext on the server.")
                    .font(T9Theme.font(14))
                    .foregroundStyle(T9Theme.muted)

                if app.inbox.isEmpty {
                    T9Theme.bezel {
                        Text("Empty tray")
                            .font(T9Theme.font(15))
                            .foregroundStyle(T9Theme.muted)
                    }
                } else {
                    ForEach(app.inbox) { msg in
                        T9Theme.bezel {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(msg.fromUsername)
                                    .font(T9Theme.font(12, .semibold))
                                    .foregroundStyle(T9Theme.teal)
                                Text(msg.plaintext)
                                    .font(T9Theme.font(16))
                            }
                        }
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
        guard let tok = app.deviceToken else { return }
        busy = true
        defer { busy = false }
        do {
            let res = try await app.api.fetchMessages(base: app.serverURL, token: tok)
            for wire in res.messages {
                guard let data = Data(base64Encoded: wire.ciphertext) else { continue }
                let plain = (try? app.keys.open(ciphertext: data)) ?? "«undecryptable»"
                let local = LocalMessage(
                    id: wire.id,
                    fromUsername: wire.from_username,
                    plaintext: plain,
                    createdAt: Date(),
                    keptLocally: true
                )
                app.inbox.insert(local, at: 0)
            }
            app.store.saveKeptMessages(app.inbox)
            app.statusLine = "fetched \(res.messages.count)"
        } catch {
            app.statusLine = error.localizedDescription
        }
    }
}
