import SwiftUI

struct ServerURLView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                brand
                ScreenChrome(
                    title: "Point at your host",
                    subtitle: "Enter the public base URL from Docker setup or your Tunnel hostname."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        FieldLabel(text: "Server URL")
                        TextField("https://app.aesms.io", text: $app.serverURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .t9Field()

                        PrimaryButton(title: "Continue", tint: T9Theme.accent, busy: busy) {
                            Task { await continueTap() }
                        }

                        if !app.statusLine.isEmpty {
                            Text(app.statusLine)
                                .font(T9Theme.font(12))
                                .foregroundStyle(T9Theme.muted)
                        }
                    }
                }
            }
        }
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AeSMS")
                .font(T9Theme.font(28, .bold))
            Text("fetch-once messaging")
                .font(T9Theme.font(13, .medium))
                .foregroundStyle(T9Theme.muted)
        }
    }

    private func continueTap() async {
        busy = true
        defer { busy = false }
        do {
            let info = try await app.api.getInfo(base: app.serverURL)
            if info.setup_needed == true {
                app.statusLine = "Server is in setup mode. Finish /setup.html on the host first."
                return
            }
            app.fingerprint = info.fingerprint ?? ""
            app.statusLine = app.fingerprint.isEmpty ? "connected" : "fp \(app.fingerprint)"
            app.phase = .credentials
        } catch {
            app.statusLine = error.localizedDescription
        }
    }
}
