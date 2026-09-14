import SwiftUI
import UIKit

struct CredentialsView: View {
    @EnvironmentObject var app: AppState
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "Device login")
                Text("Credentials stay pending")
                    .font(T9Theme.font(32, .bold))
                    .tracking(-0.6)
                Text("Password alone cannot bind this device. Approve the pending login on the web with TOTP.")
                    .foregroundStyle(T9Theme.muted)

                T9Theme.bezel {
                    VStack(alignment: .leading, spacing: 12) {
                        labeledField("Username", text: Binding(
                            get: { app.username },
                            set: { app.saveUsername($0) }
                        ))
                        labeledSecure("Password", text: $password)
                        IslandButton(title: busy ? "Submitting…" : "Request release", tint: T9Theme.teal) {
                            Task { await login() }
                        }
                        .disabled(busy)
                        Button("Back") { app.phase = .server }
                            .font(T9Theme.font(14, .medium))
                            .foregroundStyle(T9Theme.muted)
                        Text(app.statusLine)
                            .font(T9Theme.font(12))
                            .foregroundStyle(T9Theme.muted)
                    }
                }
            }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(T9Theme.font(11, .semibold))
                .tracking(1.4)
                .foregroundStyle(T9Theme.muted)
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(T9Theme.font(15, .medium))
                .padding(14)
                .background(Color.white.overlay(Rectangle().stroke(Color.black, lineWidth: 2)))
        }
    }

    private func labeledSecure(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(T9Theme.font(11, .semibold))
                .tracking(1.4)
                .foregroundStyle(T9Theme.muted)
            SecureField(title, text: text)
                .font(T9Theme.font(15, .medium))
                .padding(14)
                .background(Color.white.overlay(Rectangle().stroke(Color.black, lineWidth: 2)))
        }
    }

    private func login() async {
        busy = true
        defer { busy = false }
        do {
            let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            let res = try await app.api.deviceLogin(
                base: app.serverURL,
                username: app.username,
                password: password,
                deviceID: deviceID
            )
            app.pendingID = res.pending_id
            app.statusLine = "pending \(res.pending_id)"
            app.phase = .waitingRelease
        } catch {
            app.statusLine = error.localizedDescription
        }
    }
}
