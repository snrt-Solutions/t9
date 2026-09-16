import SwiftUI
import UIKit

struct CredentialsView: View {
    @EnvironmentObject var app: AppState
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            ScreenChrome(
                title: "Device login",
                subtitle: "Password alone cannot bind this device. Approve the pending login on the web with TOTP."
            ) {
                VStack(alignment: .leading, spacing: T9Theme.space2) {
                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel(text: "Username")
                        TextField("Username", text: Binding(
                            get: { app.username },
                            set: { app.saveUsername($0) }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .t9Field()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel(text: "Password")
                        SecureField("Password", text: $password)
                            .t9Field()
                    }

                    PrimaryButton(title: "Request release", tint: T9Theme.teal, busy: busy) {
                        Task { await login() }
                    }

                    GhostButton(title: "Back") { app.phase = .server }

                    if !app.statusLine.isEmpty {
                        Text(app.statusLine)
                            .font(T9Theme.font(13))
                            .foregroundStyle(T9Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, T9Theme.space2)
            .padding(.bottom, T9Theme.space3)
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
