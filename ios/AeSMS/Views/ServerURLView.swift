import SwiftUI

struct ServerURLView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: T9Theme.space3) {
                brand
                    .padding(.horizontal, T9Theme.pageInset)
                    .padding(.top, T9Theme.space2)

                ScreenChrome(
                    title: "Point at your host",
                    subtitle: "Enter the public base URL from Docker setup or your Tunnel hostname."
                ) {
                    VStack(alignment: .leading, spacing: T9Theme.space2) {
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(text: "Server URL")
                            TextField("https://app.aesms.io", text: $app.serverURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .t9Field()
                        }

                        PrimaryButton(title: "Continue", tint: T9Theme.accent, busy: busy) {
                            Task { await continueTap() }
                        }

                        if !app.statusLine.isEmpty {
                            Text(app.statusLine)
                                .font(T9Theme.font(13))
                                .foregroundStyle(T9Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.bottom, T9Theme.space3)
        }
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("AeSMS")
                    .font(T9Theme.font(32, .bold))
                    .foregroundStyle(T9Theme.ink)
                Text(".io")
                    .font(T9Theme.font(32, .bold))
                    .foregroundStyle(T9Theme.accent)
            }
            Text("Fetch-once messaging. Pure privacy but feels like SMS.")
                .font(T9Theme.font(14, .medium))
                .foregroundStyle(T9Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func continueTap() async {
        busy = true
        defer { busy = false }
        let trimmed = app.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        app.serverURL = trimmed
        do {
            try APIClient.assertTransitSafe(base: trimmed)
            let info = try await app.api.getInfo(base: trimmed)
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
