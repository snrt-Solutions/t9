import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var passphrase = ""
    @State private var status = ""
    @State private var backupB64 = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: "Local only")
                Text("Settings")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                T9Theme.bezel {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Server", app.serverURL)
                        row("User", app.username)
                        row("Fingerprint", app.fingerprint)
                        row("Pubkey", String(app.keys.publicKeyB64().prefix(24)) + "…")
                    }
                }

                T9Theme.bezel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ENCRYPTED BACKUP")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(T9Theme.muted)
                        SecureField("passphrase", text: $passphrase)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.94)))
                        IslandButton(title: "Export backup", tint: T9Theme.accent) { export() }
                        IslandButton(title: "Restore from paste", tint: T9Theme.teal) { restore() }
                        TextEditor(text: $backupB64)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.94)))
                        Text(status)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(T9Theme.muted)
                        Text("Restoring keys still requires a fresh web device release.")
                            .font(.system(size: 12))
                            .foregroundStyle(T9Theme.muted)
                    }
                }

                IslandButton(title: "Revoke device token", tint: T9Theme.warn) {
                    Task { await revoke() }
                }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(T9Theme.muted)
            Text(v)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
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
            status = "backup ready — copy the blob"
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
            Keychain.set("identity_x25519_priv", value: res.priv)
            Keychain.set("identity_x25519_pub", value: res.pub)
            app.contacts = res.contacts
            app.store.saveContacts(res.contacts)
            _ = app.keys.loadOrCreateIdentity()
            status = "restored keys+contacts — re-release device on web"
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
            app.phase = .server
            status = "revoked"
        } catch {
            status = error.localizedDescription
        }
    }
}
