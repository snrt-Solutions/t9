import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

struct ContactsView: View {
    @EnvironmentObject var app: AppState
    @State private var scanPayload = ""
    @State private var status = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: "Physical proximity")
                Text("Contacts")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("No search. No invites. Scan their QR in person.")
                    .foregroundStyle(T9Theme.muted)

                T9Theme.bezel {
                    VStack(spacing: 12) {
                        Text("MY QR")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(T9Theme.muted)
                        if let img = qrImage(for: myQR()) {
                            Image(uiImage: img)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                        }
                        Text(myQR())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(T9Theme.muted)
                            .textSelection(.enabled)
                    }
                }

                T9Theme.bezel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PASTE / SCAN PAYLOAD")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(T9Theme.muted)
                        TextField("t9://contact?u=…", text: $scanPayload)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 13, design: .monospaced))
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.94)))
                        IslandButton(title: "Add contact", tint: T9Theme.teal) {
                            addFromPayload()
                        }
                        Text(status)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(T9Theme.muted)
                        Text("Camera QR scanning: wire AVFoundation / CodeScanner in a signed build; MVP accepts pasted t9:// payloads.")
                            .font(.system(size: 12))
                            .foregroundStyle(T9Theme.muted)
                    }
                }

                ForEach(app.contacts) { c in
                    T9Theme.bezel {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.username)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text("srv \(c.serverFingerprint)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(c.serverFingerprint == app.fingerprint ? T9Theme.teal : T9Theme.warn)
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
            status = "warning: server fingerprint mismatch — contact saved with flag"
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
