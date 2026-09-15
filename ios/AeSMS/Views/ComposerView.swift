import SwiftUI

struct ComposerView: View {
    @EnvironmentObject var app: AppState
    @State private var to = ""
    @State private var bodyText = ""
    @State private var status = ""

    private var graphemes: Int { Grapheme.count(bodyText) }
    private var over: Bool { graphemes > 160 }

    var body: some View {
        ScrollView {
            ScreenChrome(title: "Compose", subtitle: "160 grapheme blocks. Sealed to a QR contact.") {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel(text: "To")
                    TextField("contact username", text: $to)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .t9Field()

                    FieldLabel(text: "Message")
                    TextEditor(text: $bodyText)
                        .font(T9Theme.font(16))
                        .frame(minHeight: 140)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(T9Theme.surface)
                        .overlay(Rectangle().stroke(T9Theme.hair, lineWidth: T9Theme.stroke))

                    HStack {
                        Text("\(graphemes)/160")
                            .font(T9Theme.font(13, .semibold))
                            .foregroundStyle(over ? T9Theme.warn : T9Theme.teal)
                        Spacer()
                    }

                    PrimaryButton(title: "Send sealed", tint: over ? T9Theme.warn : T9Theme.ink) {
                        Task { await send() }
                    }
                    .disabled(over || bodyText.isEmpty || to.isEmpty)
                    .opacity(over || bodyText.isEmpty || to.isEmpty ? 0.5 : 1)

                    if !status.isEmpty {
                        Text(status)
                            .font(T9Theme.font(12))
                            .foregroundStyle(T9Theme.muted)
                    }
                }
            }
        }
    }

    private func send() async {
        guard let tok = app.deviceToken else { return }
        guard let contact = app.contacts.first(where: { $0.username.lowercased() == to.lowercased() }) else {
            status = "scan their QR first - no server address book"
            return
        }
        do {
            let sealed = try app.keys.seal(plaintext: bodyText, toRecipientPubB64: contact.pubkey)
            try await app.api.postMessage(
                base: app.serverURL,
                token: tok,
                to: to,
                ciphertextB64: sealed.base64EncodedString(),
                graphemes: graphemes,
                pubkey: app.keys.publicKeyB64()
            )
            status = "sent"
            bodyText = ""
        } catch {
            status = error.localizedDescription
        }
    }
}
