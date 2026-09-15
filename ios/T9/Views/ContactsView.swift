import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

struct ContactsView: View {
    @EnvironmentObject var app: AppState
    @State private var scanPayload = ""
    @State private var status = ""

    var body: some View {
        ScrollView {
            ScreenChrome(
                title: "Contacts",
                subtitle: "No search. No invites. Scan their QR in person."
            ) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 12) {
                        FieldLabel(text: "My QR")
                        if let img = qrImage(for: myQR()) {
                            Image(uiImage: img)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                                .padding(12)
                                .background(T9Theme.surface)
                                .overlay(Rectangle().stroke(T9Theme.hair, lineWidth: T9Theme.stroke))
                        }
                        Text(myQR())
                            .font(T9Theme.font(10))
                            .foregroundStyle(T9Theme.muted)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 10) {
                        FieldLabel(text: "Paste payload")
                        TextField("t9://contact?u=…", text: $scanPayload)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .t9Field()
                        PrimaryButton(title: "Add contact", tint: T9Theme.teal) {
                            addFromPayload()
                        }
                        if !status.isEmpty {
                            Text(status)
                                .font(T9Theme.font(12))
                                .foregroundStyle(T9Theme.muted)
                        }
                    }

                    if !app.contacts.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(app.contacts.enumerated()), id: \.element.id) { idx, c in
                                if idx > 0 { RowDivider() }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(c.username)
                                        .font(T9Theme.font(16, .semibold))
                                    Text("srv \(c.serverFingerprint)")
                                        .font(T9Theme.font(11))
                                        .foregroundStyle(c.serverFingerprint == app.fingerprint ? T9Theme.teal : T9Theme.warn)
                                }
                                .padding(.vertical, 12)
                            }
                        }
                    }
                }
            }
        }
    }

    private func myQR() -> String {
        let u = app.username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? app.username
        let pk = app.keys.publicKeyB64().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let srv = app.fingerprint.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "t9://contact?u=\(u)&pk=\(pk)&srv=\(srv)"
    }

    private func addFromPayload() {
        guard let url = URL(string: scanPayload), url.scheme == "t9", url.host == "contact",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            status = "bad payload"
            return
        }
        let u = items.first(where: { $0.name == "u" })?.value ?? ""
        let pk = items.first(where: { $0.name == "pk" })?.value ?? ""
        let srv = items.first(where: { $0.name == "srv" })?.value ?? ""
        guard !u.isEmpty, !pk.isEmpty else {
            status = "missing fields"
            return
        }
        if srv != app.fingerprint && !app.fingerprint.isEmpty {
            status = "warning: server fingerprint mismatch - contact saved with flag"
        } else {
            status = "contact saved"
        }
        let c = Contact(username: u, pubkey: pk, serverFingerprint: srv, addedAt: Date())
        if !app.contacts.contains(where: { $0.username == u }) {
            app.contacts.append(c)
            app.store.saveContacts(app.contacts)
        }
        scanPayload = ""
    }

    private func qrImage(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
