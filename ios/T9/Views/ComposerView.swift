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
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: "160 blocks")
                Text("Compose")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                T9Theme.bezel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TO")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(T9Theme.muted)
                        TextField("contact username", text: $to)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 15, design: .monospaced))
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.94)))

                        TextEditor(text: $bodyText)
                            .font(.system(size: 16, design: .monospaced))
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.94)))

                        HStack {
                            Text(String(repeating: "■", count: min(graphemes, 40)) + (graphemes > 40 ? "…" : ""))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(over ? T9Theme.warn : T9Theme.muted)
                            Spacer()
                            Text("\(graphemes)/160")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(over ? T9Theme.warn : T9Theme.teal)
                        }

                        IslandButton(title: "Send sealed", tint: over ? T9Theme.warn : T9Theme.ink) {
                            Task { await send() }
                        }
                        .disabled(over || bodyText.isEmpty || to.isEmpty)

                        Text(status)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(T9Theme.muted)
                    }
                }
            }
        }
    }

    private func send() async {
        guard let tok = app.deviceToken else { return }
        guard let contact = app.contacts.first(where: { $0.username.lowercased() == to.lowercased() }) else {
            status = "scan their QR first — no server address book"
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
