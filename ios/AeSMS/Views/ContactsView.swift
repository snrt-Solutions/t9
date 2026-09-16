import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

struct ContactsView: View {
    @EnvironmentObject var app: AppState
    @State private var scanPayload = ""
    @State private var status = ""
    @State private var showScanner = false
    @State private var copiedHint = false
    @State private var pairCode = ""
    @State private var pairBusy = false
    @State private var offerTask: Task<Void, Never>?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            ScreenChrome(
                title: "Contacts",
                subtitle: "No search. No invites. Rotating pair QR — scan in person."
            ) {
                VStack(alignment: .leading, spacing: T9Theme.space3) {
                    VStack(alignment: .leading, spacing: 12) {
                        FieldLabel(text: "My pair QR")
                        if let img = qrImage(for: pairURI()) {
                            Image(uiImage: img)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 180, height: 180)
                                .padding(T9Theme.space2)
                                .frame(maxWidth: .infinity)
                                .background(T9Theme.surface)
                                .overlay(Rectangle().stroke(T9Theme.hair.opacity(0.45), lineWidth: T9Theme.stroke))
                        } else {
                            Text(pairBusy ? "Minting pair code…" : "Waiting for pair code")
                                .font(T9Theme.font(13))
                                .foregroundStyle(T9Theme.muted)
                                .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                                .background(T9Theme.surface)
                                .overlay(Rectangle().stroke(T9Theme.hair.opacity(0.45), lineWidth: T9Theme.stroke))
                        }
                        Button {
                            copyConnectionLink()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(pairCode.isEmpty ? "aesms://pair?c=…" : pairURI())
                                    .font(T9Theme.font(10))
                                    .foregroundStyle(T9Theme.muted)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(copiedHint ? "Copied" : "Copy")
                                    .font(T9Theme.font(12, .semibold))
                                    .foregroundStyle(copiedHint ? T9Theme.teal : T9Theme.accent)
                            }
                            .padding(14)
                            .background(T9Theme.surface)
                            .overlay(Rectangle().stroke(T9Theme.hair.opacity(0.45), lineWidth: T9Theme.stroke))
                        }
                        .buttonStyle(.plain)
                        .disabled(pairCode.isEmpty)
                        .accessibilityHint("Copies the connection link to the clipboard")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        FieldLabel(text: "Add contact")
                        SecondaryButton(title: "Scan QR") {
                            showScanner = true
                        }
                        TextField("aesms://pair?c=…", text: $scanPayload)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .t9Field()
                        PrimaryButton(title: "Claim from paste", tint: T9Theme.teal, busy: pairBusy) {
                            Task { await claimFromPayload(scanPayload) }
                        }
                        if !status.isEmpty {
                            Text(status)
                                .font(T9Theme.font(13))
                                .foregroundStyle(T9Theme.muted)
                        }
                    }

                    if !app.contacts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            FieldLabel(text: "Saved")
                            SurfacePanel(padding: 0) {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(app.contacts.enumerated()), id: \.element.id) { idx, c in
                                        if idx > 0 { RowDivider() }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(c.username)
                                                .font(T9Theme.font(15, .semibold))
                                            Text("srv \(c.serverFingerprint)")
                                                .font(T9Theme.font(11))
                                                .foregroundStyle(
                                                    c.serverFingerprint == app.fingerprint
                                                    ? T9Theme.teal
                                                    : T9Theme.warn
                                                )
                                        }
                                        .padding(.horizontal, T9Theme.space2)
                                        .padding(.vertical, 14)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, T9Theme.space3)
        }
        .background(T9Theme.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView(
                onCode: { code in
                    showScanner = false
                    scanPayload = code
                    Task { await claimFromPayload(code) }
                },
                onCancel: { showScanner = false }
            )
        }
        .onAppear { startPairLoop() }
        .onDisappear { stopPairLoop() }
    }

    private func pairURI() -> String {
        guard !pairCode.isEmpty else { return "" }
        let c = pairCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pairCode
        let srv = app.fingerprint.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "aesms://pair?c=\(c)&srv=\(srv)"
    }

    private func copyConnectionLink() {
        let link = pairURI()
        guard !link.isEmpty else { return }
        UIPasteboard.general.string = link
        copiedHint = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedHint = false
        }
    }

    private func startPairLoop() {
        stopPairLoop()
        offerTask = Task { @MainActor in
            while !Task.isCancelled {
                await refreshOffer()
                try? await Task.sleep(nanoseconds: 45_000_000_000)
            }
        }
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                await pollOffer()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopPairLoop() {
        offerTask?.cancel()
        pollTask?.cancel()
        offerTask = nil
        pollTask = nil
    }

    private func refreshOffer() async {
        guard let tok = app.deviceToken else {
            status = "device token required"
            return
        }
        pairBusy = true
        defer { pairBusy = false }
        do {
            let resp = try await app.api.createPairOffer(
                base: app.serverURL,
                token: tok,
                pubkey: app.keys.publicKeyB64()
            )
            pairCode = resp.code
            if status.hasPrefix("Minting") || status.isEmpty || status == "device token required" {
                status = "pair code rotating"
            }
        } catch {
            let msg = error.localizedDescription
            if msg.contains("handshake pending") {
                status = "handshake pending — waiting for peer"
            } else {
                status = msg
            }
        }
    }

    private func pollOffer() async {
        guard let tok = app.deviceToken else { return }
        do {
            let resp = try await app.api.pollPairOffer(base: app.serverURL, token: tok)
            guard resp.status == "claimed", let peer = resp.peer else { return }
            if savePeer(username: peer.username, pubkey: peer.pubkey, srv: app.fingerprint) {
                status = "paired with \(peer.username)"
            }
            await refreshOffer()
        } catch {
            // Keep polling quietly; surface lasting errors from offer mint.
        }
    }

    private func claimFromPayload(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("aesms://contact") {
            addLegacyContact(trimmed)
            return
        }
        guard let url = URL(string: trimmed), url.scheme == "aesms", url.host == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            status = "bad payload"
            return
        }
        let code = items.first(where: { $0.name == "c" })?.value ?? ""
        let srv = items.first(where: { $0.name == "srv" })?.value ?? ""
        guard !code.isEmpty else {
            status = "missing fields"
            return
        }
        guard let tok = app.deviceToken else {
            status = "device token required"
            return
        }
        pairBusy = true
        defer { pairBusy = false }
        do {
            let resp = try await app.api.claimPairOffer(
                base: app.serverURL,
                token: tok,
                code: code,
                pubkey: app.keys.publicKeyB64()
            )
            let peerSrv = srv.isEmpty ? app.fingerprint : srv
            if savePeer(username: resp.peer.username, pubkey: resp.peer.pubkey, srv: peerSrv) {
                if !srv.isEmpty && !app.fingerprint.isEmpty && srv != app.fingerprint {
                    status = "paired with \(resp.peer.username) (srv mismatch flag)"
                } else {
                    status = "paired with \(resp.peer.username)"
                }
            }
            scanPayload = ""
        } catch {
            status = error.localizedDescription
        }
    }

    private func addLegacyContact(_ raw: String) {
        guard let url = URL(string: raw), url.scheme == "aesms", url.host == "contact",
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
        _ = savePeer(username: u, pubkey: pk, srv: srv)
        scanPayload = ""
    }

    @discardableResult
    private func savePeer(username: String, pubkey: String, srv: String) -> Bool {
        if username.caseInsensitiveCompare(app.username) == .orderedSame {
            status = "that is your own QR"
            return false
        }
        if app.contacts.contains(where: { $0.username.caseInsensitiveCompare(username) == .orderedSame }) {
            status = "already saved: \(username)"
            return false
        }
        if !srv.isEmpty && !app.fingerprint.isEmpty && srv != app.fingerprint {
            status = "warning: server fingerprint mismatch - contact saved with flag"
        } else {
            status = "contact saved: \(username)"
        }
        let c = Contact(username: username, pubkey: pubkey, serverFingerprint: srv, addedAt: Date())
        app.contacts.append(c)
        app.store.saveContacts(app.contacts)
        return true
    }

    private func qrImage(for string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
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
