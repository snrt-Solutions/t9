import SwiftUI

struct ServerURLView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                brand
                Eyebrow(text: "Same-server mailbox")
                Text("Point at your T-9 host")
                    .font(T9Theme.font(34, .bold))
                    .tracking(-0.8)
                    .foregroundStyle(T9Theme.ink)
                Text("No App Store directory. Enter the base URL from your Docker or Tunnel deploy.")
                    .font(T9Theme.font(16, .regular))
                    .foregroundStyle(T9Theme.muted)

                T9Theme.bezel {
                    VStack(alignment: .leading, spacing: 12) {
                        fieldLabel("Server URL")
                        TextField("https://t9.example.com", text: $app.serverURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(T9Theme.font(15, .medium))
                            .padding(14)
                            .background(Color.white.overlay(Rectangle().stroke(Color.black, lineWidth: 2)))

                        IslandButton(title: busy ? "Checking…" : "Continue", tint: T9Theme.accent) {
                            Task { await continueTap() }
                        }
                        .disabled(busy)

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
        VStack(alignment: .leading, spacing: 6) {
            Text("T-9")
                .font(T9Theme.font(28, .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text("fetch-once messaging.")
                Text("pure privacy but feels like SMS")
            }
            .font(T9Theme.font(12, .medium))
            .foregroundStyle(T9Theme.muted)
        }
    }

    private func fieldLabel(_ t: String) -> some View {
        Text(t.uppercased())
            .font(T9Theme.font(11, .semibold))
            .tracking(1.4)
            .foregroundStyle(T9Theme.muted)
    }

    private func continueTap() async {
        busy = true
        defer { busy = false }
        do {
            let info = try await app.api.getInfo(base: app.serverURL)
            app.fingerprint = info.fingerprint ?? ""
            app.statusLine = "fp \(app.fingerprint)"
            app.phase = .credentials
        } catch {
            app.statusLine = error.localizedDescription
        }
    }
}
