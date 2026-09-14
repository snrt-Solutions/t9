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
                    .font(.system(size: 32, weight: .bold, design: .rounded))
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
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(T9Theme.muted)
                        Text(app.statusLine)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(T9Theme.muted)
                    }
                }
            }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(T9Theme.muted)
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.94)))
        }
    }

    private func labeledSecure(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(T9Theme.muted)
            SecureField(title, text: text)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.94)))
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
