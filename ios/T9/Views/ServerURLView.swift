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
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(T9Theme.ink)
                Text("No App Store directory. Enter the base URL from your Docker or Tunnel deploy.")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(T9Theme.muted)

                T9Theme.bezel {
                    VStack(alignment: .leading, spacing: 12) {
                        fieldLabel("Server URL")
                        TextField("https://t9.example.com", text: $app.serverURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.94)))

                        IslandButton(title: busy ? "Checking…" : "Continue", tint: T9Theme.accent) {
                            Task { await continueTap() }
                        }
                        .disabled(busy)

                        if !app.statusLine.isEmpty {
                            Text(app.statusLine)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(T9Theme.muted)
                        }
                    }
                }
            }
        }
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("T-9")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("FETCH-ONCE")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(T9Theme.muted)
        }
    }

    private func fieldLabel(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
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
