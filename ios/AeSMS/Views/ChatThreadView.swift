import SwiftUI

struct ChatThreadView: View {
    @EnvironmentObject var app: AppState
    let username: String

    @State private var bodyText = ""
    @State private var status = ""
    @State private var sending = false
    @State private var confirmClear = false

    private var messages: [LocalMessage] { app.messages(fromUsername: username) }
    private var graphemes: Int { Grapheme.count(bodyText) }
    private var over: Bool { graphemes > 160 }
    private var contact: Contact? {
        app.contacts.first { $0.username.caseInsensitiveCompare(username) == .orderedSame }
    }
    private var canSend: Bool {
        !over && !bodyText.isEmpty && contact != nil && !sending
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            composerBar
        }
        .background(T9Theme.bg.ignoresSafeArea())
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { app.markChatRead(username: username) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    confirmClear = true
                }
                .font(T9Theme.font(14, .semibold))
                .foregroundStyle(T9Theme.warn)
                .disabled(messages.isEmpty)
                .opacity(messages.isEmpty ? 0.4 : 1)
            }
        }
        .confirmationDialog(
            "Clear chat with \(username)?",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("Clear chat", role: .destructive) {
                app.deleteChat(fromUsername: username)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes all local messages in this chat (sent and received).")
        }
    }

    @ViewBuilder
    private var messageList: some View {
        if messages.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                EmptyStateBlock(
                    title: contact == nil ? "Unknown contact" : "No messages yet",
                    detail: contact == nil
                        ? "This peer is not in your contact list. Re-pair via Contacts to send."
                        : "Say hello — messages stay sealed end to end."
                )
                .padding(.horizontal, T9Theme.pageInset)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(messages) { msg in
                        messageBubble(msg)
                            .id(msg.id)
                            .listRowInsets(EdgeInsets(
                                top: 8,
                                leading: T9Theme.pageInset,
                                bottom: 8,
                                trailing: T9Theme.pageInset
                            ))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    app.deleteMessage(id: msg.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    app.deleteMessage(id: msg.id)
                                } label: {
                                    Label("Delete message", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear { scrollToEnd(proxy) }
                .onChange(of: messages.count) { _, _ in scrollToEnd(proxy) }
            }
        }
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if contact == nil {
                Text("Re-pair this contact to send.")
                    .font(T9Theme.font(12))
                    .foregroundStyle(T9Theme.warn)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $bodyText, axis: .vertical)
                    .font(T9Theme.font(15))
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(T9Theme.surface)
                    .overlay(Rectangle().stroke(T9Theme.hair.opacity(0.55), lineWidth: T9Theme.stroke))
                    .disabled(sending || contact == nil)

                Button {
                    Task { await send() }
                } label: {
                    Text(sending ? "…" : "Send")
                        .font(T9Theme.font(14, .semibold))
                        .foregroundStyle(canSend ? T9Theme.accent : T9Theme.muted)
                        .frame(minWidth: 48, minHeight: 40)
                }
                .disabled(!canSend)
            }
            HStack {
                Text("\(graphemes)/160")
                    .font(T9Theme.font(12, .medium))
                    .foregroundStyle(over ? T9Theme.warn : T9Theme.muted)
                Spacer(minLength: 8)
                if !status.isEmpty {
                    Text(status)
                        .font(T9Theme.font(12))
                        .foregroundStyle(sending ? T9Theme.teal : T9Theme.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, T9Theme.pageInset)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(T9Theme.bg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(T9Theme.hair.opacity(0.35))
                .frame(height: T9Theme.rule)
        }
        .t9KeyboardDismiss()
    }

    private func messageBubble(_ msg: LocalMessage) -> some View {
        HStack {
            if msg.outbound { Spacer(minLength: 40) }
            VStack(alignment: msg.outbound ? .trailing : .leading, spacing: 6) {
                Text(msg.outbound ? "You" : msg.fromUsername)
                    .font(T9Theme.font(11, .semibold))
                    .foregroundStyle(msg.outbound ? T9Theme.muted : T9Theme.teal)
                Text(msg.plaintext)
                    .font(T9Theme.font(15))
                    .foregroundStyle(T9Theme.ink)
                    .multilineTextAlignment(msg.outbound ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(msg.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(T9Theme.font(11))
                    .foregroundStyle(T9Theme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: 300, alignment: msg.outbound ? .trailing : .leading)
            .background(msg.outbound ? T9Theme.ink.opacity(0.06) : T9Theme.surface)
            .overlay(
                Rectangle().stroke(
                    T9Theme.hair.opacity(msg.outbound ? 0.18 : 0.4),
                    lineWidth: T9Theme.stroke
                )
            )
            if !msg.outbound { Spacer(minLength: 40) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func send() async {
        guard !sending else { return }
        Keyboard.dismiss()
        guard let tok = app.deviceToken else { return }
        guard let contact else {
            status = "re-pair via Contacts"
            return
        }
        sending = true
        status = "Sending…"
        defer { sending = false }
        _ = await app.fetchInboxQuiet()
        do {
            let plain = bodyText
            let sealed = try app.keys.seal(plaintext: plain, toRecipientPubB64: contact.pubkey)
            let id = try await app.api.postMessage(
                base: app.serverURL,
                token: tok,
                to: contact.username,
                ciphertextB64: sealed.base64URLEncodedString(),
                graphemes: graphemes,
                pubkey: app.keys.publicKeyB64()
            )
            app.recordOutbound(id: id, toUsername: contact.username, plaintext: plain)
            status = ""
            bodyText = ""
        } catch {
            status = error.localizedDescription
        }
    }
}
