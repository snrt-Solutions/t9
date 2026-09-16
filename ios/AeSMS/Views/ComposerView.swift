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

    var body: some View {
        ScrollView {
            ScreenChrome(title: "Compose", subtitle: "160 grapheme blocks. Sealed to a QR contact.") {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel(text: "To")
                    TextField("contact username", text: $to)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(sending)
                        .t9Field()

                    FieldLabel(text: "Message")
                    TextEditor(text: $bodyText)
                        .font(T9Theme.font(16))
                        .frame(minHeight: 140)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(T9Theme.surface)
                        .overlay(Rectangle().stroke(T9Theme.hair, lineWidth: T9Theme.stroke))
                        .disabled(sending)
                        .opacity(sending ? 0.7 : 1)

                    HStack {
                        Text("\(graphemes)/160")
                            .font(T9Theme.font(13, .semibold))
                            .foregroundStyle(over ? T9Theme.warn : T9Theme.teal)
                        Spacer()
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
                            .font(T9Theme.font(12))
                            .foregroundStyle(sending ? T9Theme.teal : T9Theme.muted)
                    }
                }
            }
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
        do {
            let plain = bodyText
            let sealed = try app.keys.seal(plaintext: plain, toRecipientPubB64: contact.pubkey)
            let id = try await app.api.postMessage(
                base: app.serverURL,
                token: tok,
                to: to,
                ciphertextB64: sealed.base64EncodedString(),
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
