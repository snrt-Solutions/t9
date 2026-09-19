import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var passphrase = ""
    @State private var status = ""
    @State private var backupB64 = ""

    var body: some View {
        ScrollView {
            ScreenChrome(title: "Settings", subtitle: "Local keys and device session only.") {
                VStack(alignment: .leading, spacing: T9Theme.space3) {
                    SurfacePanel {
                        VStack(alignment: .leading, spacing: 0) {
                            meta("Server", app.serverURL)
                            RowDivider().padding(.vertical, 10)
                            meta("User", app.username)
                            RowDivider().padding(.vertical, 10)
                            meta("Fingerprint", app.fingerprint)
                            RowDivider().padding(.vertical, 10)
                            meta("Pubkey", String(app.keys.publicKeyB64().prefix(24)) + "…")
                            RowDivider().padding(.vertical, 10)
                            meta("Push", app.pushOnline ? "SSE online" : "offline")
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        FieldLabel(text: "Encrypted backup")
                        SecureField("passphrase", text: $passphrase)
                            .t9Field()
                        SecondaryButton(title: "Export backup") {
                            Keyboard.dismiss()
                            export()
                        }
                        SecondaryButton(title: "Restore from paste") {
                            Keyboard.dismiss()
                            restore()
                        }
                        TextEditor(text: $backupB64)
                            .font(T9Theme.font(11))
                            .frame(minHeight: 88)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                            .background(T9Theme.surface)
                            .overlay(Rectangle().stroke(T9Theme.hair.opacity(0.55), lineWidth: T9Theme.stroke))
                        Text("Restoring keys still requires a fresh web device release.")
                            .font(T9Theme.font(12))
                            .foregroundStyle(T9Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !status.isEmpty {
                        Text(status)
                            .font(T9Theme.font(13))
                            .foregroundStyle(T9Theme.muted)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        PrimaryButton(title: "Lock now", tint: T9Theme.ink) {
                            app.lockMailbox()
                        }
                        PrimaryButton(title: "Revoke device token", tint: T9Theme.warn) {
                            Task { await revoke() }
                        }
                    }
                }
            }
            .padding(.bottom, T9Theme.space3)
        }
        .t9KeyboardDismiss()
        .background(T9Theme.bg.ignoresSafeArea())
    }

    private func meta(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k.uppercased())
                .font(T9Theme.font(10, .semibold))
                .tracking(1.2)
                .foregroundStyle(T9Theme.muted)
            Text(v.isEmpty ? "-" : v)
                .font(T9Theme.font(13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func export() {
        do {
            let id = app.keys.loadOrCreateIdentity()
            let data = try app.store.exportBackup(
                passphrase: passphrase,
                identityPrivB64: id.privateKey.rawRepresentation.base64EncodedString(),
                identityPubB64: id.publicKeyB64,
                contacts: app.contacts
            )
            backupB64 = data.base64EncodedString()
            status = "backup ready - copy the blob"
        } catch {
            status = error.localizedDescription
        }
    }

    private func restore() {
        guard let data = Data(base64Encoded: backupB64) else {
            status = "bad base64"
            return
        }
        do {
            let res = try app.store.importBackup(data: data, passphrase: passphrase)
            app.keys.replaceIdentity(privateKeyB64: res.priv, publicKeyB64: res.pub)
            app.contacts = res.contacts
            app.store.saveContacts(res.contacts)
            status = "restored keys+contacts - re-release device on web"
        } catch {
            status = error.localizedDescription
        }
    }

    private func revoke() async {
        guard let tok = app.deviceToken else { return }
        do {
            try await app.api.revoke(base: app.serverURL, token: tok)
            Keychain.delete("device_token")
            app.deviceToken = nil
            app.stopPush()
            app.unlocked = false
            app.phase = .server
            status = "revoked"
        } catch {
            status = error.localizedDescription
        }
    }
}
