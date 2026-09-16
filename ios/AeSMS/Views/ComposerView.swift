import SwiftUI

struct ComposerView: View {
    @EnvironmentObject var app: AppState
    @State private var to = ""
    @State private var bodyText = ""
    @State private var status = ""
    @State private var sending = false

    private var graphemes: Int { Grapheme.count(bodyText) }
    private var over: Bool { graphemes > 160 }
    private var canSend: Bool { !over && !bodyText.isEmpty && !to.isEmpty && !sending }
    private var sortedContacts: [Contact] {
        app.contacts.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            ScreenChrome(title: "Compose", subtitle: "160 grapheme blocks. Sealed to a QR contact.") {
                VStack(alignment: .leading, spacing: T9Theme.space2) {
                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel(text: "To")
                        if sortedContacts.isEmpty {
                            Text("scan their QR first - no server address book")
                                .font(T9Theme.font(14))
                                .foregroundStyle(T9Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .frame(minHeight: 48)
                                .background(T9Theme.surface)
                                .overlay(Rectangle().stroke(T9Theme.hair.opacity(0.55), lineWidth: T9Theme.stroke))
                        } else {
                            Menu {
                                ForEach(sortedContacts) { contact in
                                    Button(contact.username) {
                                        to = contact.username
                                    }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(to.isEmpty ? "Choose contact" : to)
                                        .font(T9Theme.font(15, .medium))
                                        .foregroundStyle(to.isEmpty ? T9Theme.muted : T9Theme.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(T9Theme.muted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .frame(minHeight: 48)
                                .background(T9Theme.surface)
                                .overlay(Rectangle().stroke(T9Theme.hair.opacity(0.55), lineWidth: T9Theme.stroke))
                            }
                            .disabled(sending)
                            .accessibilityLabel("To")
                            .accessibilityValue(to.isEmpty ? "No contact selected" : to)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel(text: "Message")
                        TextEditor(text: $bodyText)
                            .font(T9Theme.font(16))
                            .frame(minHeight: 160)
                            .padding(14)
                            .scrollContentBackground(.hidden)
                            .background(T9Theme.surface)
                            .overlay(Rectangle().stroke(T9Theme.hair.opacity(0.55), lineWidth: T9Theme.stroke))
                            .disabled(sending)
                            .opacity(sending ? 0.7 : 1)

                        Text("\(graphemes)/160")
                            .font(T9Theme.font(13, .medium))
                            .foregroundStyle(over ? T9Theme.warn : T9Theme.muted)
                    }

                    PrimaryButton(
                        title: sending ? "Sending…" : "Send sealed",
                        tint: over ? T9Theme.warn : T9Theme.ink,
                        busy: sending
                    ) {
                        Task { await send() }
                    }
                    .disabled(!canSend)
                    .opacity(canSend || sending ? 1 : 0.5)

                    if !status.isEmpty {
                        Text(status)
                            .font(T9Theme.font(13))
                            .foregroundStyle(sending ? T9Theme.teal : T9Theme.muted)
                    }
                }
            }
            .padding(.bottom, T9Theme.space3)
        }
        .background(T9Theme.bg.ignoresSafeArea())
        .onAppear {
            if !to.isEmpty,
               !app.contacts.contains(where: { $0.username.caseInsensitiveCompare(to) == .orderedSame }) {
                to = ""
            }
            Task { await app.fetchInboxQuiet() }
        }
    }

    private func send() async {
        guard !sending else { return }
        guard let tok = app.deviceToken else { return }
        guard let contact = app.contacts.first(where: { $0.username.lowercased() == to.lowercased() }) else {
            status = "scan their QR first - no server address book"
            return
        }
        sending = true
        status = "Sending…"
        defer { sending = false }
        // Pull mail first so badges/inbox stay current and fetch-once stays honest.
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
            status = "Sent"
            bodyText = ""
        } catch {
            status = error.localizedDescription
        }
    }
}
