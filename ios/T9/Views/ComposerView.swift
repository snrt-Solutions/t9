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
                    .font(T9Theme.font(30, .bold))

                T9Theme.bezel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TO")
                            .font(T9Theme.font(11, .semibold))
                            .tracking(1.4)
                            .foregroundStyle(T9Theme.muted)
                        TextField("contact username", text: $to)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(T9Theme.font(15))
                            .padding(12)
                            .background(Color.white.overlay(Rectangle().stroke(Color.black, lineWidth: 2)))

                        TextEditor(text: $bodyText)
                            .font(T9Theme.font(16))
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(Color.white.overlay(Rectangle().stroke(Color.black, lineWidth: 2)))

                        HStack {
                            Text(String(repeating: "■", count: min(graphemes, 40)) + (graphemes > 40 ? "…" : ""))
                                .font(T9Theme.font(10))
                                .foregroundStyle(over ? T9Theme.warn : T9Theme.muted)
                            Spacer()
                            Text("\(graphemes)/160")
                                .font(T9Theme.font(13, .semibold))
                                .foregroundStyle(over ? T9Theme.warn : T9Theme.teal)
                        }

                        IslandButton(title: "Send sealed", tint: over ? T9Theme.warn : T9Theme.ink) {
                            Task { await send() }
                        }
                        .disabled(over || bodyText.isEmpty || to.isEmpty)

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
