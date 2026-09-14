import SwiftUI

struct WaitingReleaseView: View {
    @EnvironmentObject var app: AppState
    @State private var dots = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Eyebrow(text: "Awaiting web release")
            Text("Approve on the site")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Open the release page, enter your username + live TOTP, and approve this pending ID.")
                .foregroundStyle(T9Theme.muted)

            T9Theme.bezel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("PENDING ID")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(T9Theme.muted)
                    Text(app.pendingID ?? "—")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)

                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(i == dots % 3 ? T9Theme.teal : T9Theme.accent.opacity(0.35))
                                .frame(width: 8, height: 8)
                                .scaleEffect(i == dots % 3 ? 1.15 : 0.85)
                                .animation(T9Theme.ease, value: dots)
                        }
                        Text("polling")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(T9Theme.muted)
                    }

                    if let id = app.pendingID {
                        Text("\(app.serverURL)/release.html?pending_id=\(id)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(T9Theme.accent)
                            .textSelection(.enabled)
                    }

                    Text(app.statusLine)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(T9Theme.muted)

                    Button("Cancel") {
                        stop()
                        app.phase = .credentials
                    }
                    .foregroundStyle(T9Theme.muted)
                }
            }
            Spacer()
        }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                dots += 1
                await poll()
            }
        }
        Task { await poll() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() async {
        guard let id = app.pendingID else { return }
        do {
            let res = try await app.api.pollPending(base: app.serverURL, id: id)
            app.statusLine = "status \(res.status)"
            if res.status == "approved", let tok = res.device_token, !tok.isEmpty {
                Keychain.set("device_token", value: tok)
                app.deviceToken = tok
                stop()
                app.phase = .mailbox
            } else if res.status == "denied" {
                app.statusLine = "denied on web"
                stop()
            }
        } catch {
            app.statusLine = error.localizedDescription
        }
    }
}
